-- Eksik kalan push_subscriptions tablosu (ana schema.sql'de vardı ama
-- IF NOT EXISTS olmadığı için tekrar çalıştırılamıyordu). Güvenle çalıştırılabilir.

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint TEXT UNIQUE NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  user_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
