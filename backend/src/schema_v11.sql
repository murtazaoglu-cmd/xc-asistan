-- X Control Yapı — Şema Güncellemesi v11
-- Üç kardeş site (controlx.com.tr / X Metal / nicebodrum.com) aynı admin paneli paylaştığı için,
-- bir teklifin hangi siteden geldiğini ayırt edebilmek amacıyla.

ALTER TABLE offers ADD COLUMN IF NOT EXISTS source_site TEXT; -- 'controlx' | 'xmetal' | 'nicebodrum'
