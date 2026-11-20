-- X Control Yapı — Şema Güncellemesi v19 (komut çubuğu + yazışma içe aktarma + KVKK kayıtları) — idempotent, tekrar çalıştırılabilir.
-- migrate.js tarafından otomatik uygulanır (kendi transaction'ında). Önceki migrasyonlara dokunmaz.
-- Tasarım: design-assistant.md bölüm 2.5 / 2.7 / 3.3. LLM YOK; tüm çıkarım kural tabanlıdır, veri yalnız bu sunucuda işlenir.
-- org_id (v17): organizations'a FK, NULLABLE; boş eklenen satıra varsayılan kuruluş set_default_org() tetikleyicisiyle atanır (dosya sonu).
-- Bağımlılık: schema_v17 (organizations, set_default_org). Tablolar bağımsız bir kuruluşa taşınabilsin diye her tabloda org_id vardır.
-- Durum değerleri bu kod tabanının geleneği gibi ASCII Türkçe'dir (planlandi, tamamlandi ...).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) Rıza / aydınlatma kayıtları (KVKK ispat yükü) ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS consents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,          -- kaydı giren panel kullanıcısı
  subject_type TEXT NOT NULL DEFAULT 'customer' CHECK (subject_type IN ('customer','user','import')),
  phone_key TEXT,                                                 -- müşteri telefon anahtarı (yalnız rakam)
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,   -- müşteri silinince kayıt da gider
  kind TEXT NOT NULL CHECK (kind IN ('aydinlatma','acik_riza','veri_isleme_ack','ticari_ileti')),
  text_version TEXT NOT NULL,
  granted BOOLEAN NOT NULL DEFAULT true,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('import','manual','web_form','api')),
  note TEXT CHECK (note IS NULL OR length(note) <= 500),
  at TIMESTAMPTZ NOT NULL DEFAULT now(),
  withdrawn_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_consents_phone ON consents (phone_key);
CREATE INDEX IF NOT EXISTS idx_consents_user ON consents (user_id, at DESC);

-- 2) İçe aktarma oturumu (önizleme → onay) -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversation_imports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'whatsapp_export' CHECK (source IN ('whatsapp_export','share','manual')),
  status TEXT NOT NULL DEFAULT 'onizleme' CHECK (status IN ('onizleme','onaylandi','iptal','suresi_doldu')),
  file_label TEXT,                                                -- temizlenmiş görünen ad (diske YAZILMAZ)
  file_kind TEXT CHECK (file_kind IN ('txt','zip')),
  file_bytes INT,
  file_sha256 TEXT,                                               -- aynı dosyanın tekrar yüklenmesini bildirmek için
  stats JSONB NOT NULL DEFAULT '{}'::jsonb,
  candidates JSONB NOT NULL DEFAULT '[]'::jsonb,                  -- müşteri eşleme adayları
  staged JSONB,                                                   -- onaya kadar ayrıştırılmış mesajlar; onay/iptalde SİLİNİR
  consent_id UUID REFERENCES consents(id) ON DELETE SET NULL,
  conversation_id UUID,                                           -- onaydan sonra (FK aşağıda)
  inserted_count INT NOT NULL DEFAULT 0,
  duplicate_count INT NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '24 hours',   -- onaylanmayan önizleme saklama süresi
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_conv_imports_user ON conversation_imports (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conv_imports_expiry ON conversation_imports (expires_at) WHERE status = 'onizleme';

-- 3) Yazışmalar ------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  source TEXT NOT NULL DEFAULT 'whatsapp_export' CHECK (source IN ('whatsapp_export','share','manual')),
  convo_key TEXT NOT NULL,                                        -- 'phone:<son10hane>' | 'name:<katlanmış başlık>' (tekilleştirme kimliği)
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,    -- müşteri silinince yazışma da silinir (KVKK)
  phone_key TEXT,
  offer_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  title TEXT,
  is_group BOOLEAN NOT NULL DEFAULT false,
  participants JSONB NOT NULL DEFAULT '[]'::jsonb,
  owner_sender TEXT,                                              -- yazışmada "ben" olan gönderen adı
  first_message_at TIMESTAMPTZ,
  last_message_at TIMESTAMPTZ,
  message_count INT NOT NULL DEFAULT 0,
  retention_until TIMESTAMPTZ,                                    -- bu tarihten sonra yazışma silinir (IMPORT_RETENTION_DAYS)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_conversations_owner_key
  ON conversations ((COALESCE(owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid)), convo_key);
CREATE INDEX IF NOT EXISTS idx_conversations_phone ON conversations (phone_key);
CREATE INDEX IF NOT EXISTS idx_conversations_customer ON conversations (customer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_retention ON conversations (retention_until) WHERE retention_until IS NOT NULL;

CREATE TABLE IF NOT EXISTS conversation_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  import_id UUID REFERENCES conversation_imports(id) ON DELETE CASCADE,   -- içe aktarma silinince mesajları da gider
  source TEXT NOT NULL DEFAULT 'whatsapp_export' CHECK (source IN ('whatsapp_export','share','manual')),
  role TEXT NOT NULL DEFAULT 'unknown' CHECK (role IN ('customer','owner','unknown')),
  sender TEXT,
  kind TEXT NOT NULL DEFAULT 'text' CHECK (kind IN ('text','media','deleted','location')),
  content TEXT CHECK (content IS NULL OR length(content) <= 8000),
  content_hash TEXT NOT NULL,                                     -- sha256(dakika|gönderen|metin|#sıra): tekilleştirme
  sent_at TIMESTAMPTZ NOT NULL,
  raw_expires_at TIMESTAMPTZ,                                     -- ham metin saklama süresi; dolunca content NULL'lanır (not/öneri kalır)
  redacted BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, content_hash)
);
CREATE INDEX IF NOT EXISTS idx_conv_messages_conv ON conversation_messages (conversation_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_conv_messages_import ON conversation_messages (import_id);
CREATE INDEX IF NOT EXISTS idx_conv_messages_raw_exp ON conversation_messages (raw_expires_at) WHERE redacted = false AND raw_expires_at IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'conv_imports_conversation_fk') THEN
    ALTER TABLE conversation_imports ADD CONSTRAINT conv_imports_conversation_fk
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 4) Notlar ------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  author TEXT NOT NULL CHECK (author IN ('rule','user')),         -- 'rule' = kural/regex çıkarımı, 'user' = elle
  source_type TEXT NOT NULL DEFAULT 'manual' CHECK (source_type IN ('import','command','manual','share')),
  source_id UUID,                                                 -- öneri / mesaj kimliği (bilgi amaçlı)
  import_id UUID REFERENCES conversation_imports(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  source_message_id UUID REFERENCES conversation_messages(id) ON DELETE SET NULL,
  owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 4000),
  tags TEXT[] NOT NULL DEFAULT '{}',
  phone_key TEXT,
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  offer_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','dismissed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_notes_phone ON ai_notes (phone_key, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_notes_owner ON ai_notes (owner_user_id, created_at DESC);

-- 5) Öneriler (yazışmadan çıkan not / hatırlatma / randevu) → kullanıcı onaylar -------------------------------------
CREATE TABLE IF NOT EXISTS ai_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  import_id UUID REFERENCES conversation_imports(id) ON DELETE CASCADE,
  source_message_id UUID REFERENCES conversation_messages(id) ON DELETE CASCADE,   -- her öneri kaynak mesaja bağlıdır
  kind TEXT NOT NULL CHECK (kind IN ('not','hatirlatma','randevu','gorev')),
  payload JSONB NOT NULL,
  origin TEXT NOT NULL DEFAULT 'rule' CHECK (origin IN ('rule')),
  status TEXT NOT NULL DEFAULT 'beklemede' CHECK (status IN ('beklemede','kabul','red','suresi_doldu')),
  dedupe_key TEXT NOT NULL,
  confidence NUMERIC(3,2),
  action_id UUID,                                                 -- kabulde oluşan ai_actions kaydı
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 days',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  UNIQUE (conversation_id, dedupe_key)
);
CREATE INDEX IF NOT EXISTS idx_ai_suggestions_user ON ai_suggestions (user_id, status, created_at DESC);

-- 6) Onay kartı kaydı / denetim günlüğü -------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  origin TEXT NOT NULL CHECK (origin IN ('command_bar','import','system')),
  intent TEXT NOT NULL,
  risk TEXT NOT NULL DEFAULT 'R2' CHECK (risk IN ('R1','R2')),
  raw_text TEXT CHECK (raw_text IS NULL OR length(raw_text) <= 500),   -- komut metni (saklama: raw_expires_at)
  params JSONB NOT NULL DEFAULT '{}'::jsonb,                      -- ayrıştırılmış + düzenlenmiş parametreler
  args JSONB,                                                     -- yürütülecek nihai istek bilgisi (yol/gövde yok: yalnız alanlar)
  preview JSONB NOT NULL DEFAULT '{}'::jsonb,                     -- {summary, fields[], ambiguities[]}
  params_hash TEXT NOT NULL,                                      -- 60 sn tekilleştirme
  status TEXT NOT NULL DEFAULT 'onerildi' CHECK (status IN ('onerildi','onaylandi','reddedildi','uygulandi','hata','geri_alindi','suresi_doldu')),
  result JSONB,
  error TEXT,
  undo_info JSONB,                                                -- geri alma bilgisi {kind, ... , undoable, until}
  suggestion_id UUID,
  raw_expires_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '24 hours',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  applied_at TIMESTAMPTZ,
  undone_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_ai_actions_user ON ai_actions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_actions_hash ON ai_actions (user_id, params_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_actions_pending ON ai_actions (expires_at) WHERE status = 'onerildi';

-- 7) Müşteri (elle eklenen) silinince ilgili yazışma verisi de silinir (KVKK): BEFORE DELETE tetikleyicisi önce içe aktarma kayıtlarını
--    (ayrıştırılmış katılımcı/ad bilgisi içerir), sonra yazışmaları (mesaj/öneri CASCADE) ve notları siler.
--    Eşleşme: conversations.customer_id = müşteri VEYA aynı telefon anahtarı (son 10 hane) + aynı sahip. FK CASCADE yedek güvencedir.
CREATE OR REPLACE FUNCTION trg_customers_delete_conversations() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE k TEXT := right(regexp_replace(COALESCE(OLD.phone, ''), '[^0-9]', '', 'g'), 10);
BEGIN
  DELETE FROM conversation_imports WHERE conversation_id IN (
    SELECT id FROM conversations WHERE customer_id = OLD.id
       OR (length(k) >= 7 AND right(COALESCE(phone_key, ''), 10) = k AND (OLD.owner_id IS NULL OR owner_user_id = OLD.owner_id)));
  DELETE FROM conversations WHERE customer_id = OLD.id
     OR (length(k) >= 7 AND right(COALESCE(phone_key, ''), 10) = k AND (OLD.owner_id IS NULL OR owner_user_id = OLD.owner_id));
  IF length(k) >= 7 THEN
    DELETE FROM ai_notes WHERE right(COALESCE(phone_key, ''), 10) = k AND (OLD.owner_id IS NULL OR owner_user_id = OLD.owner_id);
  END IF;
  RETURN OLD;
END $f$;
DROP TRIGGER IF EXISTS trg_customers_conv_cleanup ON customers;
CREATE TRIGGER trg_customers_conv_cleanup BEFORE DELETE ON customers
  FOR EACH ROW EXECUTE FUNCTION trg_customers_delete_conversations();

-- 8) org_id tetikleyicileri + indeksler (v17 desenindeki gibi) ---------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['consents','conversation_imports','conversations','conversation_messages','ai_notes','ai_suggestions','ai_actions'] LOOP
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (org_id)', 'idx_' || t || '_org', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_default_org ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_default_org BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_default_org()', t);
  END LOOP;
END $$;

-- 9) Özellik bayrağı: wa_import (v17'de kapalı tohumlanmıştı) bu sürümle açılır; admin yine kapatabilir (kill-switch).
--    Yalnız GENEL bayrak satırı, yalnız kapalıysa ve yalnız bu migrasyonun İLK uygulanışında (yeniden çalıştırmada admin tercihini ezmez).
UPDATE feature_flags SET enabled = true, description = 'WhatsApp yazışma içe aktarma (v19)', updated_at = now()
 WHERE key = 'wa_import' AND org_id IS NULL AND enabled = false
   AND NOT EXISTS (SELECT 1 FROM schema_migrations WHERE name = 'schema_v19.sql');
