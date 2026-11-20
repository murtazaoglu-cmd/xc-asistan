-- X Control Yapı — Şema Güncellemesi v15 (mobil uygulama hazırlığı) — idempotent, tekrar çalıştırılabilir.
-- migrate.js tarafından otomatik uygulanır (kendi transaction'ında). Önceki migrasyonlara dokunmaz.

-- 1) Adres / konum (yol tarifi için) — teklif, müşteri, randevu, proje -----------------------------
ALTER TABLE offers       ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE offers       ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE offers       ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);
ALTER TABLE customers    ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE customers    ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE customers    ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);
ALTER TABLE projects     ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE projects     ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE projects     ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS lat NUMERIC(9,6);
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS lng NUMERIC(9,6);
-- Teklif/projeye bağlı olmayan (doğrudan müşteriye) randevular için müşteri adı/telefonu
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS customer_phone TEXT;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['offers','customers','projects','appointments'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = t::regclass AND conname = t || '_geo_chk') THEN
      EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK ((lat IS NULL) = (lng IS NULL) AND (lat IS NULL OR lat BETWEEN -90 AND 90) AND (lng IS NULL OR lng BETWEEN -180 AND 180))', t, t || '_geo_chk');
    END IF;
  END LOOP;
END $$;

-- 2) Oturum iptali: token_version artınca kullanıcının tüm eski jetonları geçersiz olur ----------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INT NOT NULL DEFAULT 0;

-- 3) Teklif gönderim sonucu (WhatsApp/e-posta) — gerçek durum ---------------------------------------
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS last_send_status TEXT;  -- 'gonderildi' | 'kismen' | 'basarisiz'
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS last_send_at TIMESTAMPTZ;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS last_send_error TEXT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'quotes'::regclass AND conname = 'quotes_send_status_chk') THEN
    ALTER TABLE quotes ADD CONSTRAINT quotes_send_status_chk
      CHECK (last_send_status IS NULL OR last_send_status IN ('gonderildi','kismen','basarisiz'));
  END IF;
END $$;
-- Geriye dönük: daha önce en az bir kanaldan gönderilmiş teklifler "gonderildi" sayılır
UPDATE quotes SET last_send_status = 'gonderildi',
                  last_send_at = COALESCE(sent_via_email_at, sent_via_whatsapp_at)
 WHERE last_send_status IS NULL AND (sent_via_whatsapp_at IS NOT NULL OR sent_via_email_at IS NOT NULL);

-- 4) Mobil cihaz push token'ları (FCM sonra bağlanacak; şimdilik yalnız kayıt) ---------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK (platform IN ('android','ios','web')),
  app_version TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

-- 5) İndeksler (mobil ana ekran sorguları) ---------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_projects_open_end ON projects(end_date) WHERE stage <> 'Tamamlandı';
CREATE INDEX IF NOT EXISTS idx_reminders_pending ON reminders(remind_at) WHERE status = 'bekliyor';
CREATE INDEX IF NOT EXISTS idx_materials_low ON materials(owner_id) WHERE stock_quantity <= low_stock_threshold;
