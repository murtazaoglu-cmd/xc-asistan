-- X Control Yapı — Şema Güncellemesi v10
-- Giderleri "Ev" / "Dükkan" / "Genel İşletme" olarak ayırt etmek için.

ALTER TABLE expenses ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'genel'; -- 'ev' | 'dukkan' | 'genel'
ALTER TABLE recurring_expenses ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'genel';
