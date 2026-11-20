-- X Control Yapı — Şema Güncellemesi v9
-- Sabit giderler (kira, maaş, sigorta gibi her ay tekrarlayan giderler) için şablon sistemi.
-- Her ay tek tıkla o ayın gerçek gider kaydına dönüştürülür (expenses tablosuna eklenir).

CREATE TABLE IF NOT EXISTS recurring_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,       -- örn. "Dükkan Kirası", "Ev Kirası", "Maaş", "Elektrik/Su/Doğalgaz"
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Bir sabit gider, belirli bir ayda uygulandığında (expense oluşturulduğunda) buraya kayıt düşer —
-- aynı ay için tekrar tekrar eklenmesini önlemek için.
CREATE TABLE IF NOT EXISTS recurring_expense_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recurring_expense_id UUID NOT NULL REFERENCES recurring_expenses(id) ON DELETE CASCADE,
  expense_id UUID REFERENCES expenses(id) ON DELETE CASCADE,
  year_month TEXT NOT NULL, -- 'YYYY-MM' formatında
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(recurring_expense_id, year_month)
);
