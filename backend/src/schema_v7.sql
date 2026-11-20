-- X Control Yapı — Şema Güncellemesi v7
-- Her kullanıcının kendi teklif/proje defteri + seçili paylaşım sistemi.

ALTER TABLE offers ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE projects ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

-- Mevcut kayıtları (sahipsiz olanları) ana yöneticiye ata — geriye dönük uyumluluk için.
-- Not: Aşağıdaki UPDATE'i yalnızca bir kez, ilk kurulumda çalıştırın.
UPDATE offers SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1)
  WHERE owner_id IS NULL;
UPDATE projects SET owner_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY created_at LIMIT 1)
  WHERE owner_id IS NULL;

CREATE TABLE IF NOT EXISTS resource_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type TEXT NOT NULL, -- 'offer' | 'project'
  resource_id UUID NOT NULL,
  shared_with_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shared_by_user_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(resource_type, resource_id, shared_with_user_id)
);
CREATE INDEX IF NOT EXISTS idx_resource_shares_lookup ON resource_shares(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_resource_shares_user ON resource_shares(shared_with_user_id);
