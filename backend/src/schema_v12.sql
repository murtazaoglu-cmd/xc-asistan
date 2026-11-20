-- X Control Yapı — Şema Güncellemesi v12
-- "Ortak proje, ayrı firma" modeli: aynı projede birlikte çalışan iki kullanıcı
-- (örn. inşaat/tadilat yapan admin + demir işini yapan bir personel), o projenin
-- görevlerini, giderlerini ve ödemelerini kendi aralarında paylaştırabilsin.
-- Her kayıt bir kullanıcıya "atanır" — o kaydın parası/işi sadece atanan kullanıcının
-- Finans/Görevler alanında görünür, diğer işbirlikçinin verisine karışmaz.

ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS assigned_user_id UUID REFERENCES users(id);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

-- Geriye dönük uyumluluk: mevcut tüm kayıtlar, hesabı ilk oluşturan admin'e ait sayılır
-- (şu ana kadar zaten tek kullanıcı tarafından giriliyordu).
UPDATE expenses SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1)
  WHERE owner_id IS NULL;
UPDATE payments SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1)
  WHERE owner_id IS NULL;
UPDATE project_tasks SET assigned_user_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1)
  WHERE assigned_user_id IS NULL;
