-- Şema v20 — Asistanın "iş yapan" kısmı: müdür motoru (insights), brifing, akşam kapanış, takipler, hatırlatma genişletme.
-- Idempotent (tekrar çalıştırılabilir); migrate.js kendi transaction'ında uygular. Önceki migrasyonlara DOKUNMAZ.
-- Yeni tabloların hepsi org_id taşır + set_default_org() tetikleyicisi (v17) ile varsayılan kuruluşa bağlanır.
-- Başka paketlerin tablolarına (invoices, vat_periods, holidays_tr, ai_actions) BAĞIMLILIK YOKTUR: uygulama kodu varlıklarını
-- çalışma anında to_regclass ile yoklar.

-- 1) Veri tamlığı / geçmiş sütunları (müdür metrikleri için) ------------------------------------------------
ALTER TABLE projects ADD COLUMN IF NOT EXISTS cost_confirmed_at TIMESTAMPTZ;   -- "masraflar tamam" (marj hesabı yalnız bunlarla)
ALTER TABLE projects ADD COLUMN IF NOT EXISTS stage_changed_at TIMESTAMPTZ;    -- tahsilat yaşlandırma: aşamaya geçiş zamanı
ALTER TABLE offers   ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ;   -- teklif yaşı: durum değişim zamanı

-- Geriye dönük doldurma: MEVCUT kayıtlarda aşama zamanı bilinmez → göç anı (sahte "21 gündür gecikmiş" alarmı çıkmasın).
-- Teklifte updated_at durum değişiminde güncellendiği için en iyi tahmindir.
UPDATE projects SET stage_changed_at = now() WHERE stage_changed_at IS NULL;
UPDATE offers   SET status_changed_at = COALESCE(updated_at, created_at) WHERE status_changed_at IS NULL;
ALTER TABLE projects ALTER COLUMN stage_changed_at SET DEFAULT now();
ALTER TABLE offers   ALTER COLUMN status_changed_at SET DEFAULT now();

CREATE OR REPLACE FUNCTION a2_touch_stage() RETURNS trigger AS $$
BEGIN
  IF NEW.stage IS DISTINCT FROM OLD.stage THEN NEW.stage_changed_at := now(); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_a2_stage ON projects;
CREATE TRIGGER trg_a2_stage BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION a2_touch_stage();

CREATE OR REPLACE FUNCTION a2_touch_offer_status() RETURNS trigger AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN NEW.status_changed_at := now(); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_a2_offer_status ON offers;
CREATE TRIGGER trg_a2_offer_status BEFORE UPDATE ON offers FOR EACH ROW EXECUTE FUNCTION a2_touch_offer_status();

-- 2) Brifingler ----------------------------------------------------------------------------------------------
-- kind: morning (sabah) · weekly (haftalık müdür raporu, Pzt) · monthly (aylık, ayın 1'i) · evening (gün sonu özeti)
-- period_start: morning/evening → gün; weekly → raporun kapsadığı haftanın Pazartesi'si; monthly → raporlanan ayın ilk günü
CREATE TABLE IF NOT EXISTS briefings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('morning','weekly','monthly','evening')),
  period_start DATE NOT NULL,
  title TEXT NOT NULL,                              -- bildirim başlığı (tek satır)
  body_text TEXT NOT NULL DEFAULT '',               -- okunabilir metin (şablonla üretilir)
  data JSONB NOT NULL,                              -- yapılandırılmış bloklar (sürümlü şema: data.v)
  generated_by TEXT NOT NULL DEFAULT 'job' CHECK (generated_by IN ('job','on_demand')),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  UNIQUE (user_id, kind, period_start)
);
CREATE INDEX IF NOT EXISTS idx_briefings_user ON briefings (user_id, kind, period_start DESC);

-- 3) Insight'lar (müdür önerileri) -------------------------------------------------------------------------------
-- scope_key: 'business' (admin + muhasebe işletme defteri) | 'user:<uuid>' (ortak: yalnız kendi verisi). Görünürlük buna göredir.
CREATE TABLE IF NOT EXISTS insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  scope_key TEXT NOT NULL,
  rule_key TEXT NOT NULL,                           -- M1 … M13 (alt kurallar: M2b, M3b, M6b, M6c)
  severity TEXT NOT NULL CHECK (severity IN ('info','warn','critical')),
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  evidence JSONB NOT NULL DEFAULT '{}',             -- sayısal dayanak ("Neden?"): metrics[], refs[], thresholds
  actions JSONB NOT NULL DEFAULT '[]',              -- önerilen aksiyon metadatası (hatırlat, ara, WhatsApp şablonu, randevu ekle…)
  entity_type TEXT, entity_id UUID,
  fingerprint TEXT NOT NULL,                        -- kural + varlık (aynı insight tekrar üretilmez)
  score BIGINT NOT NULL DEFAULT 0,                  -- sıralama puanı (önem × büyüklük)
  status TEXT NOT NULL DEFAULT 'acik' CHECK (status IN ('acik','ertelendi','kapatildi','uygulandi')),
  snoozed_until TIMESTAMPTZ,                        -- ertelendi: bitiş · kapatildi(kullanıcı): susturma bitişi (14 gün)
  closed_reason TEXT,                               -- kullanici | kosul_ortadan_kalkti | kural_kapali | uygulandi
  closed_at TIMESTAMPTZ,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  occurrences INT NOT NULL DEFAULT 1,
  feedback TEXT CHECK (feedback IN ('yanlis','alakasiz','yararli')),
  feedback_note TEXT,
  feedback_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (org_id, scope_key, fingerprint)
);
CREATE INDEX IF NOT EXISTS idx_insights_scope ON insights (org_id, scope_key, status, score DESC);
CREATE INDEX IF NOT EXISTS idx_insights_rule ON insights (org_id, rule_key);

CREATE TABLE IF NOT EXISTS insight_rule_config (
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  rule_key TEXT NOT NULL,                           -- M1 … M13; '*' = genel ayarlar (ör. calibration)
  enabled BOOLEAN NOT NULL DEFAULT true,
  params JSONB NOT NULL DEFAULT '{}',               -- yalnız kataloğun tanıdığı eşikler
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID,
  PRIMARY KEY (org_id, rule_key)
);

CREATE TABLE IF NOT EXISTS insight_runs (            -- son hesaplama (tazelik denetimi + hata kaydı)
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  scope_key TEXT NOT NULL,
  ran_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  summary JSONB NOT NULL DEFAULT '{}',
  PRIMARY KEY (org_id, scope_key)
);

-- 4) Akşam kapanış günlüğü ---------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','partial','done','skipped')),
  questions JSONB NOT NULL DEFAULT '[]',            -- üretildiği andaki dondurulmuş sorular (kimlikler sabit)
  answers JSONB NOT NULL DEFAULT '{}',              -- {soru_id: {choice, follow_up, skipped, amount_kurus, note, answered_at, applied[]}}
  free_note TEXT,
  completeness SMALLINT NOT NULL DEFAULT 0 CHECK (completeness BETWEEN 0 AND 100),
  summary JSONB NOT NULL DEFAULT '{}',              -- gün sonu özeti kartı (son hesap)
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  nudged_at TIMESTAMPTZ,                            -- 20:30 tek hatırlatma gönderildi
  closed_at TIMESTAMPTZ,
  UNIQUE (user_id, log_date)
);

-- 5) Açık takipler ("Ahmet'i ara", "teklif hazırla" …) ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS followups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- takibi yapacak kişi
  kind TEXT NOT NULL DEFAULT 'diger' CHECK (kind IN ('ara','teklif','tahsilat','bilgi','diger')),
  title TEXT NOT NULL,
  due_date DATE NOT NULL,
  offer_id UUID, project_id UUID, appointment_id UUID,
  customer_name TEXT, customer_phone TEXT,
  status TEXT NOT NULL DEFAULT 'acik' CHECK (status IN ('acik','yapildi','ertelendi','iptal')),
  source TEXT NOT NULL DEFAULT 'kullanici' CHECK (source IN ('kullanici','sistem','kapanis','insight')),
  source_key TEXT,                                  -- aynı kaynaktan çift üretimi önler
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  done_at TIMESTAMPTZ,
  snoozed_until DATE
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_followups_source ON followups (user_id, source_key) WHERE source_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_followups_due ON followups (user_id, due_date) WHERE status IN ('acik','ertelendi');

-- 6) Hatırlatma genişletme (mevcut /api/reminders sözleşmesi aynen; yeni alanlar yalnız EKLENİR) -----------------------------------
-- Alıcı: owner_id. Etkin zaman: remind_at (ertelemede yeni zamana taşınır; snoozed_until bilgi için).
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS recurrence TEXT;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS snoozed_until TIMESTAMPTZ;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS snooze_count INT NOT NULL DEFAULT 0;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS done_at TIMESTAMPTZ;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'kullanici';
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS source_key TEXT;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS fired_at TIMESTAMPTZ;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS offer_id UUID;
ALTER TABLE reminders ADD COLUMN IF NOT EXISTS appointment_id UUID;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reminders_recurrence_chk') THEN
    ALTER TABLE reminders ADD CONSTRAINT reminders_recurrence_chk CHECK (recurrence IS NULL OR recurrence IN ('daily','weekdays','weekly','monthly'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reminders_source_chk') THEN
    ALTER TABLE reminders ADD CONSTRAINT reminders_source_chk CHECK (source IN ('kullanici','sistem','brifing'));
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_reminders_source ON reminders (owner_id, source_key) WHERE source_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reminders_due_open ON reminders (remind_at) WHERE status = 'bekliyor';

-- 7) org_id varsayılan atama tetikleyicileri (yeni tablolar) ----------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['briefings','insights','daily_logs','followups'] LOOP
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (org_id)', 'idx_' || t || '_org', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_default_org ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_default_org BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_default_org()', t);
  END LOOP;
END $$;
