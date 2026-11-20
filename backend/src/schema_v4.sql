-- X Control Yapı — Şema Güncellemesi v4
-- Not: 'gallery' tablosu zaten ilk schema.sql'de mevcut, tekrar oluşturmaya gerek yok.

CREATE TABLE IF NOT EXISTS quote_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  items JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
