-- X Control Yapı — Şema Güncellemesi v8

ALTER TABLE offers ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE TABLE IF NOT EXISTS activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type TEXT NOT NULL, -- 'offer' | 'project'
  resource_id UUID NOT NULL,
  user_id UUID REFERENCES users(id),
  action TEXT NOT NULL,        -- örn. 'durum_degisti', 'duzenlendi', 'paylasildi', 'odeme_eklendi'
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activity_log_lookup ON activity_log(resource_type, resource_id, created_at DESC);

CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type TEXT NOT NULL, -- 'offer' | 'project'
  resource_id UUID NOT NULL,
  file_url TEXT NOT NULL,
  file_name TEXT NOT NULL,
  uploaded_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_lookup ON documents(resource_type, resource_id);
