-- Şema v17 — Asistan altyapısı (çok sektörlü, çok kiracıya HAZIRLIK) — idempotent, tekrar çalıştırılabilir.
-- migrate.js tarafından otomatik, kendi transaction'ında uygulanır. Önceki migrasyonlara dokunmaz.
-- Kapsam: organizations + nullable org_id + backfill, org_counters, org_settings, sector_templates, jobs, notification_outbox,
-- notification_prefs, worker_heartbeats, audit_log, idempotency_keys, feature_flags, device_tokens genişletmesi.
-- NOT NULL ve RLS YOK (Faz 4). Mevcut owner_id izolasyonu aynen çalışır.

-- 1) Kuruluşlar ---------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  sector_key TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- en çok bir varsayılan kuruluş
CREATE UNIQUE INDEX IF NOT EXISTS organizations_one_default ON organizations ((true)) WHERE is_default;

-- 2) Sektör şablonları (tohum aşağıda) ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sector_templates (
  key TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  dictionary JSONB NOT NULL DEFAULT '{}',          -- {terim_anahtarı: "Gösterilen ad"}
  service_types JSONB NOT NULL DEFAULT '[]',
  appointment_types JSONB NOT NULL DEFAULT '[]',
  expense_categories JSONB NOT NULL DEFAULT '[]',
  is_default BOOLEAN NOT NULL DEFAULT false,
  sort_order INT NOT NULL DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3) Kuruluş ayarları ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS org_settings (
  org_id UUID PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
  brand JSONB NOT NULL DEFAULT '{}',               -- {name, logo_url, primary_color}
  sector_dictionary JSONB NOT NULL DEFAULT '{"terms":{}}',
  service_types JSONB NOT NULL DEFAULT '[]',
  appointment_types JSONB NOT NULL DEFAULT '[]',
  expense_categories JSONB NOT NULL DEFAULT '[]',
  timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul',
  briefing_time TIME NOT NULL DEFAULT '07:30',
  closing_time TIME NOT NULL DEFAULT '18:30',
  sector_key TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4) Kuruluş başına sayaçlar (kod üretimi; mevcut global sequence'lere dokunulmaz) ------------------
CREATE TABLE IF NOT EXISTS org_counters (
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  value BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (org_id, key)
);
CREATE OR REPLACE FUNCTION next_org_counter(p_org UUID, p_key TEXT) RETURNS BIGINT AS $$
  INSERT INTO org_counters (org_id, key, value) VALUES (p_org, p_key, 1)
  ON CONFLICT (org_id, key) DO UPDATE SET value = org_counters.value + 1
  RETURNING value;
$$ LANGUAGE sql;

-- 5) Varsayılan kuruluş: mevcut kurulum (kullanıcı var) = X Control Yapı; boş kurulum = genel "İşletmem" -----
INSERT INTO organizations (name, slug, sector_key, is_default)
SELECT CASE WHEN EXISTS (SELECT 1 FROM users) THEN 'X Control Yapı' ELSE 'İşletmem' END,
       CASE WHEN EXISTS (SELECT 1 FROM users) THEN 'x-control-yapi' ELSE 'default' END,
       CASE WHEN EXISTS (SELECT 1 FROM users) THEN 'demir_dograma' ELSE 'genel' END,
       true
WHERE NOT EXISTS (SELECT 1 FROM organizations WHERE is_default);

-- 6) Ana tablolara NULLABLE org_id + backfill + indeks + "yeni satıra varsayılan kuruluşu ata" tetikleyicisi ----
CREATE OR REPLACE FUNCTION set_default_org() RETURNS trigger AS $$
BEGIN
  IF NEW.org_id IS NULL THEN
    NEW.org_id := (SELECT id FROM organizations WHERE is_default LIMIT 1);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t text; d uuid;
BEGIN
  SELECT id INTO d FROM organizations WHERE is_default LIMIT 1;
  FOREACH t IN ARRAY ARRAY['users','services','offers','quotes','projects','payments','expenses','gallery','appointments',
      'whatsapp_messages','push_subscriptions','project_tasks','project_extras','reminders','quote_templates','materials',
      'customers','resource_shares','activity_log','documents','recurring_expenses','recurring_expense_applications','device_tokens'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES organizations(id)', t);
      EXECUTE format('UPDATE %I SET org_id = $1 WHERE org_id IS NULL', t) USING d;
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (org_id)', 'idx_' || t || '_org', t);
      EXECUTE format('DROP TRIGGER IF EXISTS trg_default_org ON %I', t);
      EXECUTE format('CREATE TRIGGER trg_default_org BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_default_org()', t);
    END IF;
  END LOOP;
END $$;

-- 7) Cihaz token'ları (v15) genişletmesi: pasifleştirme ve cihaz bilgisi ---------------------------------
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS disabled_at TIMESTAMPTZ;
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS os_version TEXT;
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS locale TEXT;
CREATE INDEX IF NOT EXISTS idx_device_tokens_active ON device_tokens (user_id) WHERE disabled_at IS NULL;

-- 8) İş kuyruğu -----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  dedupe_key TEXT UNIQUE,                          -- NULL = tekilleştirme yok
  run_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,                          -- süresi geçen iş çalıştırılmaz: 'skipped'
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','done','failed','skipped')),
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  locked_by TEXT,
  locked_at TIMESTAMPTZ,
  last_error TEXT,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_jobs_due ON jobs (run_at) WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS idx_jobs_running ON jobs (locked_at) WHERE status = 'running';
CREATE INDEX IF NOT EXISTS idx_jobs_finished ON jobs (finished_at) WHERE status IN ('done','failed','skipped');

-- 9) Bildirim tercihleri (kullanıcı başına; satır yoksa varsayılanlar + kuruluş saatleri geçerli) -----------
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  org_id UUID REFERENCES organizations(id),
  enabled BOOLEAN NOT NULL DEFAULT true,
  tz TEXT NOT NULL DEFAULT 'Europe/Istanbul',
  morning_enabled BOOLEAN NOT NULL DEFAULT true,
  evening_enabled BOOLEAN NOT NULL DEFAULT true,
  morning_time TIME,                               -- NULL = org_settings.briefing_time
  evening_time TIME,                               -- NULL = org_settings.closing_time
  quiet_enabled BOOLEAN NOT NULL DEFAULT true,
  quiet_start TIME NOT NULL DEFAULT '21:30',
  quiet_end TIME NOT NULL DEFAULT '07:00',
  weekdays SMALLINT NOT NULL DEFAULT 63 CHECK (weekdays BETWEEN 0 AND 127),  -- bit0=Pzt … bit6=Paz (63 = Pzt–Cmt)
  channels JSONB NOT NULL DEFAULT '{"push":true,"inbox":true}',
  categories JSONB NOT NULL DEFAULT '{}',          -- {tür: false} ile tür kapatılır
  max_proactive_per_day INT NOT NULL DEFAULT 5 CHECK (max_proactive_per_day BETWEEN 0 AND 50),
  critical_in_quiet BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10) Bildirim kutusu / giden kuyruğu ---------------------------------------------------------------
-- status: beklemede (gönderilecek / FCM kapalıysa kutuda bekler) · gonderildi · basarisiz · iptal (kapalı tür/süresi geçti)
CREATE TABLE IF NOT EXISTS notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  data JSONB NOT NULL DEFAULT '{}',
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('normal','critical')),
  dedupe_key TEXT NOT NULL UNIQUE,
  not_before TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'beklemede' CHECK (status IN ('beklemede','gonderildi','basarisiz','iptal')),
  attempts INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,                         -- gönderici kısa süreli kirası (çift gönderimi önler)
  last_error TEXT,
  sent_at TIMESTAMPTZ,
  sent_channels TEXT[] NOT NULL DEFAULT '{}',
  read_at TIMESTAMPTZ,
  acked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_outbox_due ON notification_outbox (not_before) WHERE status = 'beklemede';
CREATE INDEX IF NOT EXISTS idx_outbox_user ON notification_outbox (user_id, created_at DESC);

-- 11) Worker kalp atışı -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS worker_heartbeats (
  worker_id TEXT PRIMARY KEY,
  host TEXT, pid INT, version TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_tick_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ticks BIGINT NOT NULL DEFAULT 0,
  stats JSONB NOT NULL DEFAULT '{}',
  last_error TEXT
);

-- 12) Denetim izi (güvenlik/yapılandırma eylemleri; activity_log'dan ayrı) ------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  user_id UUID,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  data JSONB NOT NULL DEFAULT '{}',
  ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity_type, entity_id);

-- 13) Idempotency-Key kayıtları (kullanıcı başına) -----------------------------------------------------
CREATE TABLE IF NOT EXISTS idempotency_keys (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  status_code INT,                                  -- NULL = işleniyor
  response_body JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);
CREATE INDEX IF NOT EXISTS idx_idem_created ON idempotency_keys (created_at);

-- 14) Özellik bayrakları (genel: org_id NULL; kuruluş bazlı ezme; yüzde kademeli açılış) ----------------
CREATE TABLE IF NOT EXISTS feature_flags (
  id BIGSERIAL PRIMARY KEY,
  key TEXT NOT NULL,
  org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT false,
  rollout_percent INT NOT NULL DEFAULT 100 CHECK (rollout_percent BETWEEN 0 AND 100),
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS feature_flags_key_org ON feature_flags (key, COALESCE(org_id, '00000000-0000-0000-0000-000000000000'::uuid));

INSERT INTO feature_flags (key, enabled, description) VALUES
  ('assistant_inbox',          true,  'Uygulama içi bildirim kutusu'),
  ('assistant_briefing',       true,  'Sabah brifingi / akşam kapanış'),
  ('ai_enabled',               false, 'İsteğe bağlı AI katmanı (kapalı)'),
  ('ai_chat',                  false, 'Doğal dilli sohbet (AI)'),
  ('ai_notes',                 false, 'Yazışmadan AI notu'),
  ('briefing_ai_polish',       false, 'Brifing metnini AI ile cilalama'),
  ('wa_import',                false, 'WhatsApp yazışma içe aktarma'),
  ('wa_notification_listener', false, 'Android bildirim dinleme (WhatsApp)')
ON CONFLICT DO NOTHING;

-- 15) Sektör şablonu tohumları (admin düzenlemelerini EZMEZ: ON CONFLICT DO NOTHING) ---------------------
INSERT INTO sector_templates (key, name, description, dictionary, service_types, appointment_types, expense_categories, is_default, sort_order) VALUES
('genel', 'Genel (sektörden bağımsız)', 'Her işletmeye uyan nötr başlangıç ayarları.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"İş","jobs":"İşler","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Ekip","location":"Adres","visit":"Ziyaret"}'::jsonb,
 '["Hizmet","Ürün satışı","Danışmanlık","Bakım / destek","Diğer"]'::jsonb,
 '["Görüşme","Ziyaret","Teslimat","Arama","Diğer"]'::jsonb,
 '["Malzeme","Personel","Kira","Fatura / abonelik","Ulaşım / yakıt","Vergi","Pazarlama","Diğer"]'::jsonb, true, 10),
('tadilat_insaat', 'Tadilat / İnşaat', 'Tadilat, tamirat ve küçük ölçekli inşaat işleri.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"Proje","jobs":"Projeler","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Usta / ekip","location":"Şantiye adresi","visit":"Keşif"}'::jsonb,
 '["Komple tadilat","Boya badana","Elektrik tesisatı","Su tesisatı","Fayans / seramik","Alçıpan / asma tavan","Zemin / parke","Mutfak / banyo yenileme","Çatı / izolasyon","Dış cephe"]'::jsonb,
 '["Keşif","Ölçü alma","Teklif görüşmesi","İş başlangıcı","Ara kontrol","Teslim"]'::jsonb,
 '["Malzeme","İşçilik / usta","Taşeron","Nakliye","Yakıt","Ekipman / sarf","Kira","Fatura / abonelik","Vergi","Diğer"]'::jsonb, false, 20),
('demir_dograma', 'Demir doğrama / çelik imalat', 'Çelik konstrüksiyon, doğrama ve metal imalat (X Control Yapı profili).',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"Proje","jobs":"Projeler","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Usta / ekip","location":"Montaj adresi","visit":"Keşif"}'::jsonb,
 '["Çelik Konstrüksiyon","Demir Doğrama","Çelik Kapı","Korkuluk","Merdiven","Kepenk","Pergola","Cam Balkon","Alüminyum Doğrama","Bakım / Onarım"]'::jsonb,
 '["Keşif","Montaj","Teslim","Bakım","Diğer"]'::jsonb,
 '["Dükkan Kirası","Ev Kirası","Elektrik/Su/Doğalgaz","Maaş","Sigorta/SGK","Malzeme","Yakıt","Araç Bakım","Vergi","Telefon/İnternet","İşçilik","Nakliye","Taşeron","Diğer"]'::jsonb, false, 30),
('klima_teknik_servis', 'Klima / Teknik servis', 'Klima, kombi ve benzeri cihaz montaj-bakım-onarım işleri.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"Servis kaydı","jobs":"Servis kayıtları","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Teknisyen","location":"Cihaz adresi","visit":"Servis ziyareti"}'::jsonb,
 '["Klima montajı","Periyodik bakım","Arıza onarım","Gaz dolumu","Kombi servisi","Yıkama / temizlik","Keşif"]'::jsonb,
 '["Servis ziyareti","Montaj","Periyodik bakım","Keşif","Teslim / kontrol"]'::jsonb,
 '["Yedek parça","Gaz / sarf","Yakıt","Araç bakım","Ekipman","Kira","Fatura / abonelik","Vergi","Diğer"]'::jsonb, false, 40),
('kuafor_berber', 'Kuaför / Berber', 'Randevu ağırlıklı kişisel bakım hizmetleri.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"Hizmet","jobs":"Hizmetler","offer":"Fiyat bilgisi","offers":"Fiyat bilgileri","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Ödeme","payments":"Ödemeler","staff":"Personel","location":"Salon","visit":"Randevu"}'::jsonb,
 '["Saç kesimi","Sakal / tıraş","Boya","Fön / şekillendirme","Keratin / bakım","Manikür / pedikür","Cilt bakımı"]'::jsonb,
 '["Randevu","Danışma / deneme","Gelin / özel gün","Boya işlemi"]'::jsonb,
 '["Ürün / malzeme","Personel / prim","Kira","Elektrik / su","Ekipman","Reklam","Vergi","Diğer"]'::jsonb, false, 50),
('nakliye', 'Nakliye / Taşımacılık', 'Evden eve, ofis ve parça eşya taşıma işleri.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"Taşıma işi","jobs":"Taşıma işleri","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Ekip","location":"Yükleme / indirme adresi","visit":"Ekspertiz"}'::jsonb,
 '["Evden eve nakliyat","Ofis taşıma","Parça eşya","Depolama","Asansörlü taşıma","Şehirlerarası"]'::jsonb,
 '["Ekspertiz (keşif)","Yükleme","Teslimat","Paketleme"]'::jsonb,
 '["Yakıt","Araç bakım / onarım","Sigorta","Köprü / otoyol","Hamal / işçilik","Ambalaj","Kira","Vergi","Diğer"]'::jsonb, false, 60),
('temizlik', 'Temizlik hizmetleri', 'Ev, ofis ve inşaat sonrası temizlik işleri.',
 '{"customer":"Müşteri","customers":"Müşteriler","job":"İş","jobs":"İşler","offer":"Teklif","offers":"Teklifler","appointment":"Randevu","appointments":"Randevular","expense":"Gider","expenses":"Giderler","payment":"Tahsilat","payments":"Tahsilatlar","staff":"Ekip","location":"Adres","visit":"Keşif"}'::jsonb,
 '["Ev temizliği","Ofis temizliği","İnşaat sonrası temizlik","Cam temizliği","Koltuk / halı yıkama","Periyodik temizlik"]'::jsonb,
 '["Keşif","Temizlik","Kontrol","Teslim"]'::jsonb,
 '["Temizlik malzemesi","Personel","Ulaşım / yakıt","Ekipman","Kira","Sigorta","Vergi","Diğer"]'::jsonb, false, 70)
ON CONFLICT (key) DO NOTHING;

-- 16) Varsayılan kuruluşun ayarları: kuruluşun sektör şablonundan (yoksa 'genel'), marka adı kuruluş adı -------
INSERT INTO org_settings (org_id, brand, sector_dictionary, service_types, appointment_types, expense_categories, sector_key)
SELECT o.id,
       jsonb_build_object('name', o.name, 'logo_url', NULL, 'primary_color', NULL),
       jsonb_build_object('terms', t.dictionary),
       t.service_types, t.appointment_types, t.expense_categories, t.key
  FROM organizations o
  JOIN sector_templates t ON t.key = COALESCE(o.sector_key, 'genel')
 WHERE o.is_default
ON CONFLICT (org_id) DO NOTHING;
