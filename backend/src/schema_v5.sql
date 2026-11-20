-- X Control Yapı — Şema Güncellemesi v5

CREATE TABLE IF NOT EXISTS materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'adet', -- adet, metre, kg, litre vb.
  stock_quantity NUMERIC(12,2) NOT NULL DEFAULT 0,
  low_stock_threshold NUMERIC(12,2) NOT NULL DEFAULT 5,
  note TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
