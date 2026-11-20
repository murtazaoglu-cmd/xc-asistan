-- X Control Yapı — Şema Güncellemesi v2
-- Mevcut canlı veritabanına GÜVENLE uygulanabilir (mevcut tabloları bozmaz).

-- Giderlerin artık bir projeye bağlı olması ZORUNLU değil (genel işletme gideri de girilebilir)
ALTER TABLE expenses ALTER COLUMN project_id DROP NOT NULL;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS expense_date TIMESTAMPTZ NOT NULL DEFAULT now();

-- Proje görev listesi (yapılacak/yapılan işler, madde madde)
CREATE TABLE IF NOT EXISTS project_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'bekliyor', -- bekliyor | devam_ediyor | tamamlandi
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_project_tasks_project ON project_tasks(project_id);

-- Proje teslim öncesi çıkan ilave işler (anlaşılan fiyata ek maliyet)
CREATE TABLE IF NOT EXISTS project_extras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_project_extras_project ON project_extras(project_id);
