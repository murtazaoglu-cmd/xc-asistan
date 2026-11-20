-- X Control Yapı — Şema Güncellemesi v14 (ÖNERİ)  — tek seferde, tekrar çalıştırılabilir (idempotent)
-- Çalıştırma:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema_v14.sql   (dosyanın kendi BEGIN/COMMIT'i var; -1 kullanmayın)
-- Önkoşul: schema.sql + v2..v11 uygulanmış olmalı. v12/v13 uygulanmamışsa bu dosya onları da güvenle tamamlar.

BEGIN;

-- 0) Ön kontrol --------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.recurring_expenses') IS NULL
     OR to_regclass('public.resource_shares') IS NULL
     OR to_regclass('public.documents') IS NULL
     OR to_regclass('public.customers') IS NULL
     OR to_regclass('public.materials') IS NULL THEN
    RAISE EXCEPTION 'schema_v2..v11 uygulanmamış; önce onları çalıştırın.';
  END IF;
END $$;

-- 1) Yardımcı (geçici) fonksiyonlar -------------------------------------------
-- FK'nın ON DELETE davranışını (değilse) istenen değere çevirir; zaten doğruysa dokunmaz.
CREATE OR REPLACE FUNCTION pg_temp.set_fk(p_tbl regclass, p_col text, p_ref regclass, p_action text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  c record;
  want "char" := CASE upper(p_action) WHEN 'CASCADE' THEN 'c' WHEN 'SET NULL' THEN 'n' WHEN 'RESTRICT' THEN 'r' ELSE 'a' END;
  tname text := (SELECT relname FROM pg_class WHERE oid = p_tbl);
BEGIN
  SELECT con.conname, con.confdeltype INTO c
  FROM pg_constraint con
  WHERE con.conrelid = p_tbl AND con.contype = 'f' AND con.confrelid = p_ref
    AND con.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = p_tbl AND attname = p_col)];
  IF FOUND THEN
    IF c.confdeltype = want THEN RETURN; END IF;
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', p_tbl, c.conname);
  END IF;
  EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s(id) ON DELETE %s',
                 p_tbl, tname || '_' || p_col || '_fkey', p_col, p_ref, p_action);
END $f$;

-- CHECK kısıtını yoksa ekler; NOT VALID => mevcut hatalı satırlar migrasyonu patlatmaz, yeni yazımlar denetlenir.
CREATE OR REPLACE FUNCTION pg_temp.add_check(p_tbl regclass, p_name text, p_expr text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = p_tbl AND conname = p_name) THEN
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (%s) NOT VALID', p_tbl, p_name, p_expr);
  END IF;
END $f$;

-- 2) v12 + v13 eksik kolonları (v12/v13 sunucuda yoksa burada tamamlanır) -----
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS assigned_user_id UUID REFERENCES users(id);
ALTER TABLE expenses      ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE payments      ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE customers     ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE materials     ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE users         ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);

-- 3) Eksik owner kolonları (appointments, reminders) --------------------------
ALTER TABLE appointments ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE reminders    ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

-- 4) Backfill (hepsi "IS NULL" korumalı => tekrar çalıştırmak güvenli) --------
-- Finans kayıtları: sahibi olmayan -> projenin sahibi, o da yoksa ilk admin
UPDATE expenses e SET owner_id = COALESCE(
    (SELECT p.owner_id FROM projects p WHERE p.id = e.project_id),
    (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1))
 WHERE e.owner_id IS NULL;
UPDATE payments pay SET owner_id = COALESCE(
    (SELECT p.owner_id FROM projects p WHERE p.id = pay.project_id),
    (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1))
 WHERE pay.owner_id IS NULL;
UPDATE project_tasks t SET assigned_user_id = COALESCE(
    (SELECT p.owner_id FROM projects p WHERE p.id = t.project_id),
    (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1))
 WHERE t.assigned_user_id IS NULL;
UPDATE customers SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1) WHERE owner_id IS NULL;
UPDATE materials SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1) WHERE owner_id IS NULL;
UPDATE appointments a SET owner_id = COALESCE(
    (SELECT o.owner_id FROM offers o WHERE o.id = a.offer_id),
    (SELECT p.owner_id FROM projects p WHERE p.id = a.project_id),
    a.assigned_user_id,
    (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1))
 WHERE a.owner_id IS NULL;
UPDATE reminders r SET owner_id = COALESCE(
    (SELECT p.owner_id FROM projects p WHERE p.id = r.project_id),
    (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1))
 WHERE r.owner_id IS NULL;
-- NOT: offers.owner_id / projects.owner_id bilerek backfill EDİLMEZ (web sitesinden gelen anonim teklifler NULL kalır).

-- 5) FK / ON DELETE düzeltmeleri (yetim ve "silinemiyor" hatalarını önler) -----
SELECT pg_temp.set_fk('projects',            'offer_id',             'offers',   'SET NULL');
SELECT pg_temp.set_fk('appointments',        'offer_id',             'offers',   'CASCADE');
SELECT pg_temp.set_fk('appointments',        'project_id',           'projects', 'CASCADE');
SELECT pg_temp.set_fk('whatsapp_messages',   'offer_id',             'offers',   'CASCADE');
SELECT pg_temp.set_fk('gallery',             'project_id',           'projects', 'CASCADE');
-- Kullanıcı silinince: bağlı kayıtlar "sahipsiz" kalsın, silme işlemi FK hatasıyla patlamasın.
-- (expenses.owner_id / payments.owner_id BİLEREK NO ACTION bırakıldı: para kaydı sessizce sahipsiz kalmasın;
--  uygulama silmeden önce kayıtları devretmeli — bkz. rapor, users.js düzeltmesi.)
SELECT pg_temp.set_fk('offers',              'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('projects',            'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('customers',           'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('materials',           'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('appointments',        'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('appointments',        'assigned_user_id',     'users',    'SET NULL');
SELECT pg_temp.set_fk('reminders',           'owner_id',             'users',    'SET NULL');
SELECT pg_temp.set_fk('project_tasks',       'assigned_user_id',     'users',    'SET NULL');
SELECT pg_temp.set_fk('users',               'created_by',           'users',    'SET NULL');
SELECT pg_temp.set_fk('push_subscriptions',  'user_id',              'users',    'CASCADE');
SELECT pg_temp.set_fk('activity_log',        'user_id',              'users',    'SET NULL');
SELECT pg_temp.set_fk('documents',           'uploaded_by',          'users',    'SET NULL');
SELECT pg_temp.set_fk('recurring_expenses',  'created_by',           'users',    'SET NULL');
SELECT pg_temp.set_fk('resource_shares',     'shared_by_user_id',    'users',    'SET NULL');

-- 6) Polimorfik tablolar (resource_shares / documents / activity_log) için yetim temizliği -------
DELETE FROM resource_shares x WHERE x.resource_type = 'offer'   AND NOT EXISTS (SELECT 1 FROM offers   o WHERE o.id = x.resource_id);
DELETE FROM resource_shares x WHERE x.resource_type = 'project' AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = x.resource_id);
DELETE FROM documents       x WHERE x.resource_type = 'offer'   AND NOT EXISTS (SELECT 1 FROM offers   o WHERE o.id = x.resource_id);
DELETE FROM documents       x WHERE x.resource_type = 'project' AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = x.resource_id);
DELETE FROM activity_log    x WHERE x.resource_type = 'offer'   AND NOT EXISTS (SELECT 1 FROM offers   o WHERE o.id = x.resource_id);
DELETE FROM activity_log    x WHERE x.resource_type = 'project' AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = x.resource_id);

CREATE OR REPLACE FUNCTION trg_cleanup_resource_children() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  DELETE FROM resource_shares WHERE resource_type = TG_ARGV[0] AND resource_id = OLD.id;
  DELETE FROM documents       WHERE resource_type = TG_ARGV[0] AND resource_id = OLD.id;
  DELETE FROM activity_log    WHERE resource_type = TG_ARGV[0] AND resource_id = OLD.id;
  RETURN OLD;
END $f$;

DROP TRIGGER IF EXISTS trg_offers_cleanup ON offers;
CREATE TRIGGER trg_offers_cleanup   AFTER DELETE ON offers   FOR EACH ROW EXECUTE FUNCTION trg_cleanup_resource_children('offer');
DROP TRIGGER IF EXISTS trg_projects_cleanup ON projects;
CREATE TRIGGER trg_projects_cleanup AFTER DELETE ON projects FOR EACH ROW EXECUTE FUNCTION trg_cleanup_resource_children('project');

-- 7) CHECK kısıtları (NOT VALID: eski veri patlatmaz, yeni yazımları korur) ---
SELECT pg_temp.add_check('users',        'users_role_chk',        $c$role IN ('admin','muhasebe','personel','ortak','saha')$c$);
SELECT pg_temp.add_check('offers',       'offers_status_chk',     $c$status IN ('Yeni','İncelendi','Keşif Planlandı','Teklif Verildi','Kabul Edildi','Reddedildi')$c$);
SELECT pg_temp.add_check('projects',     'projects_stage_chk',    $c$stage IN ('Malzeme Temini','Üretim','Montaj','Teslim','Tamamlandı')$c$);
SELECT pg_temp.add_check('projects',     'projects_amount_chk',   $c$total_amount >= 0 AND total_amount <> 'NaN'$c$);
SELECT pg_temp.add_check('payments',     'payments_amount_chk',   $c$amount > 0 AND amount <> 'NaN'$c$);
SELECT pg_temp.add_check('expenses',     'expenses_amount_chk',   $c$amount > 0 AND amount <> 'NaN'$c$);
SELECT pg_temp.add_check('expenses',     'expenses_scope_chk',    $c$scope IN ('ev','dukkan','genel')$c$);
SELECT pg_temp.add_check('recurring_expenses', 'recurring_amount_chk', $c$amount > 0 AND amount <> 'NaN'$c$);
SELECT pg_temp.add_check('recurring_expenses', 'recurring_scope_chk',  $c$scope IN ('ev','dukkan','genel')$c$);
SELECT pg_temp.add_check('project_extras','extras_amount_chk',    $c$amount <> 'NaN'$c$);
SELECT pg_temp.add_check('quotes',       'quotes_totals_chk',     $c$subtotal >= 0 AND tax >= 0 AND total = subtotal + tax AND total <> 'NaN'$c$);
SELECT pg_temp.add_check('quotes',       'quotes_items_chk',      $c$jsonb_typeof(items) = 'array'$c$);
SELECT pg_temp.add_check('quote_templates','qtemplates_items_chk',$c$jsonb_typeof(items) = 'array'$c$);
SELECT pg_temp.add_check('resource_shares','shares_type_chk',     $c$resource_type IN ('offer','project')$c$);
SELECT pg_temp.add_check('documents',    'documents_type_chk',    $c$resource_type IN ('offer','project')$c$);
SELECT pg_temp.add_check('activity_log', 'activity_type_chk',     $c$resource_type IN ('offer','project')$c$);
-- (İsteğe bağlı, veri temizlendikten sonra:  ALTER TABLE payments VALIDATE CONSTRAINT payments_amount_chk; vb.)

-- 8) UNIQUE kısıtları — yinelenen veri varsa ATLANIR (NOTICE verir), migrasyon patlamaz --------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM projects WHERE offer_id IS NOT NULL GROUP BY offer_id HAVING count(*) > 1) THEN
    RAISE NOTICE 'ATLANDI: projects.offer_id yinelenen kayıt içeriyor (bir teklif -> birden çok proje). Önce temizleyin.';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_projects_offer ON projects(offer_id) WHERE offer_id IS NOT NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM users GROUP BY lower(email) HAVING count(*) > 1) THEN
    RAISE NOTICE 'ATLANDI: users.email büyük/küçük harf farkıyla yinelenen kayıt içeriyor.';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users(lower(email));
  END IF;

  IF EXISTS (SELECT 1 FROM appointments WHERE project_id IS NOT NULL AND type IN ('baslama','teslim')
             GROUP BY project_id, type HAVING count(*) > 1) THEN
    RAISE NOTICE 'ATLANDI: aynı projede yinelenen baslama/teslim randevusu var.';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_appt_project_type ON appointments(project_id, type)
      WHERE project_id IS NOT NULL AND type IN ('baslama','teslim');
  END IF;
END $$;

-- 9) İndeksler ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_offers_owner           ON offers(owner_id);
CREATE INDEX IF NOT EXISTS idx_offers_created         ON offers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offers_phone_key       ON offers ((regexp_replace(phone, '[^0-9]', '', 'g')));
CREATE INDEX IF NOT EXISTS idx_projects_owner         ON projects(owner_id);
CREATE INDEX IF NOT EXISTS idx_projects_offer         ON projects(offer_id);
CREATE INDEX IF NOT EXISTS idx_projects_start         ON projects(start_date DESC);
CREATE INDEX IF NOT EXISTS idx_quotes_offer_created   ON quotes(offer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_project       ON payments(project_id);
CREATE INDEX IF NOT EXISTS idx_payments_owner_paid    ON payments(owner_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_paid_at       ON payments(paid_at);
CREATE INDEX IF NOT EXISTS idx_expenses_project       ON expenses(project_id);
CREATE INDEX IF NOT EXISTS idx_expenses_owner_date    ON expenses(owner_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_date          ON expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_appointments_offer     ON appointments(offer_id);
CREATE INDEX IF NOT EXISTS idx_appointments_project   ON appointments(project_id);
CREATE INDEX IF NOT EXISTS idx_appointments_assigned  ON appointments(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_owner     ON appointments(owner_id);
CREATE INDEX IF NOT EXISTS idx_appointments_sched     ON appointments(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_gallery_project        ON gallery(project_id);
CREATE INDEX IF NOT EXISTS idx_gallery_published      ON gallery(created_at DESC) WHERE published;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned         ON project_tasks(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_owner        ON reminders(owner_id);
CREATE INDEX IF NOT EXISTS idx_customers_owner        ON customers(owner_id);
CREATE INDEX IF NOT EXISTS idx_customers_phone_key    ON customers ((regexp_replace(phone, '[^0-9]', '', 'g')));
CREATE INDEX IF NOT EXISTS idx_materials_owner        ON materials(owner_id);
CREATE INDEX IF NOT EXISTS idx_recurring_created_by   ON recurring_expenses(created_by);
CREATE INDEX IF NOT EXISTS idx_rea_expense            ON recurring_expense_applications(expense_id);
CREATE INDEX IF NOT EXISTS idx_wa_offer               ON whatsapp_messages(offer_id);
CREATE INDEX IF NOT EXISTS idx_push_user              ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_users_created_by       ON users(created_by);

-- 9b) Çakışmasız kod üretimi (MAX+1 yarışını bitirir) — kullanım: SELECT 'OFR-' || nextval('offer_code_seq');
CREATE SEQUENCE IF NOT EXISTS offer_code_seq;
CREATE SEQUENCE IF NOT EXISTS project_code_seq;
SELECT setval('offer_code_seq', GREATEST(
  (SELECT COALESCE(MAX(CAST(SUBSTRING(code FROM 5) AS INTEGER)), 1000) FROM offers   WHERE code ~ '^OFR-[0-9]+$'),
  (SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM offer_code_seq)));
SELECT setval('project_code_seq', GREATEST(
  (SELECT COALESCE(MAX(CAST(SUBSTRING(code FROM 5) AS INTEGER)), 500)  FROM projects WHERE code ~ '^PRJ-[0-9]+$'),
  (SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM project_code_seq)));

COMMIT;

-- 10) Çalıştırma sonrası teşhis sorguları (salt okunur) ------------------------
-- a) Yinelenen proje (aynı teklif):   SELECT offer_id, count(*) FROM projects WHERE offer_id IS NOT NULL GROUP BY 1 HAVING count(*)>1;
-- b) Sahibi muhasebe olan finans kayıtları (dashboard'da görünmez):
--    SELECT 'payments', count(*) FROM payments p JOIN users u ON u.id=p.owner_id WHERE u.role='muhasebe'
--    UNION ALL SELECT 'expenses', count(*) FROM expenses e JOIN users u ON u.id=e.owner_id WHERE u.role='muhasebe';
-- c) Sahipsiz (NULL) proje / teklif:   SELECT count(*) FROM projects WHERE owner_id IS NULL;
-- d) NaN / negatif tutar:              SELECT id FROM quotes WHERE total = 'NaN' OR total < 0;
