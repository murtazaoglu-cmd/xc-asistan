-- X Control Yapı — Şema Güncellemesi v16 (güvenlik sertleştirme) — idempotent, tekrar çalıştırılabilir.
-- migrate.js tarafından otomatik uygulanır (kendi transaction'ında). Önceki migrasyonlara dokunmaz.

-- 1) F-21: geçersiz/aşırı uzun e-postaları temizle (v16 öncesi doğrulanmamış kayıtlar; nodemailer'ı kilitleyebilirdi).
--    Yalnızca AÇIKÇA geçersiz olanlar (254+ karakter, boşluk/virgül/noktalı virgül/<>/tırnak içeren ya da tek '@' içermeyen) NULL yapılır.
UPDATE offers SET email = NULL
 WHERE email IS NOT NULL
   AND (length(email) > 254 OR email ~ '[\s,;<>()"]' OR length(email) - length(replace(email, '@', '')) <> 1);
UPDATE customers SET email = NULL
 WHERE email IS NOT NULL
   AND (length(email) > 254 OR email ~ '[\s,;<>()"]' OR length(email) - length(replace(email, '@', '')) <> 1);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'offers'::regclass AND conname = 'offers_email_len_chk') THEN
    ALTER TABLE offers ADD CONSTRAINT offers_email_len_chk CHECK (email IS NULL OR length(email) <= 254);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'customers'::regclass AND conname = 'customers_email_len_chk') THEN
    ALTER TABLE customers ADD CONSTRAINT customers_email_len_chk CHECK (email IS NULL OR length(email) <= 254);
  END IF;
END $$;

-- 1b) F-30: müşteri fotoğraf bağlantıları — yalnız genel https adresleri kalsın (javascript:, http:, IP, localhost/iç alan adları atılır)
UPDATE offers SET photo_urls = ARRAY(
    SELECT u FROM unnest(photo_urls) AS u
     WHERE length(u) <= 500
       AND u ~ '^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(/|\?|#|$)'
       AND u !~* '^https://([^/]*\.)?(localhost|local|localdomain|internal|intranet|lan|home|corp|test|invalid)(/|\?|#|$)'
  )
 WHERE photo_urls IS NOT NULL AND cardinality(photo_urls) > 0;

-- 2) F-27: güvenilmeyen push abonelik uç noktalarını (SSRF) sil: https değil ya da bilinen push servisi alan adı değil.
--    (Uygulama katmanı zaten gönderimde de süzer; bu, eski kötü satırları kalıcı temizler. Özel PUSH_ENDPOINT_HOSTS
--    kullanıyorsanız bu migrasyondan sonra o alan adlarına ait aboneliklerin yeniden alınması gerekir.)
DELETE FROM push_subscriptions
 WHERE endpoint !~ '^https://([a-z0-9-]+\.)*(googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com|push\.apple\.com)(/|$)';

-- 3) F-26: /uploads erişim denetimi dosya adından kaydı bulur — dizinler
CREATE INDEX IF NOT EXISTS documents_file_name_idx ON documents ((substring(file_url from '[^/?]+$')));
CREATE INDEX IF NOT EXISTS gallery_file_name_idx   ON gallery   ((substring(image_url from '[^/?]+$')));
CREATE INDEX IF NOT EXISTS push_subscriptions_user_idx ON push_subscriptions (user_id);

-- 4) F-33: şifre değişim zamanı (denetim izi; oturum iptali token_version ile yapılır)
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;
