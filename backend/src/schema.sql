-- X Control Yapı — Veritabanı Şeması
-- PostgreSQL 14+

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Yönetici kullanıcıları (admin panel girişi)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin', -- admin | saha | muhasebe
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Hizmet kalemleri (site içeriği + SEO meta yönetimi için)
CREATE TABLE services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT,
  seo_title TEXT,
  seo_description TEXT,
  image_url TEXT,
  sort_order INT DEFAULT 0
);

-- Teklif talepleri (web sitesinden veya panelden manuel)
CREATE TABLE offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,              -- örn. OFR-1001 (görüntüleme için)
  tracking_code TEXT UNIQUE NOT NULL,     -- örn. XCY-4F2A9 (müşteri takip linki)
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  service TEXT NOT NULL,
  region TEXT,
  message TEXT,
  photo_urls TEXT[],                      -- müşterinin yüklediği fotoğraflar
  status TEXT NOT NULL DEFAULT 'Yeni',
    -- Yeni | İncelendi | Keşif Planlandı | Teklif Verildi | Kabul Edildi | Reddedildi
  source TEXT DEFAULT 'website',          -- website | admin | whatsapp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_offers_status ON offers(status);
CREATE INDEX idx_offers_tracking_code ON offers(tracking_code);

-- Hazırlanan teklifler (kalemli, PDF üretilen)
CREATE TABLE quotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  items JSONB NOT NULL,                   -- [{desc, qty, price}]
  subtotal NUMERIC(12,2) NOT NULL,
  tax NUMERIC(12,2) NOT NULL,
  total NUMERIC(12,2) NOT NULL,
  pdf_url TEXT,
  sent_via_whatsapp_at TIMESTAMPTZ,
  sent_via_email_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Kabul edilen tekliflerden dönüşen projeler
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,              -- örn. PRJ-501
  offer_id UUID REFERENCES offers(id),
  customer_name TEXT NOT NULL,
  service TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'Malzeme Temini',
    -- Malzeme Temini | Üretim | Montaj | Teslim | Tamamlandı
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  assigned_team TEXT[],
  start_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  end_date TIMESTAMPTZ,
  notes TEXT
);

-- Ödemeler
CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  method TEXT NOT NULL,                   -- Havale | Nakit | Kredi Kartı
  note TEXT,
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Giderler (malzeme/işçilik/nakliye) — proje kârlılığı için
CREATE TABLE expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Proje/tamamlanan iş galerisi (öncesi/sonrası)
CREATE TABLE gallery (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id),
  image_url TEXT NOT NULL,
  category TEXT,
  before_after TEXT, -- 'before' | 'after' | null
  published BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Keşif / montaj randevuları
CREATE TABLE appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID REFERENCES offers(id),
  project_id UUID REFERENCES projects(id),
  type TEXT NOT NULL, -- 'kesif' | 'montaj'
  scheduled_at TIMESTAMPTZ NOT NULL,
  assigned_user_id UUID REFERENCES users(id),
  notes TEXT,
  status TEXT DEFAULT 'planlandi' -- planlandi | tamamlandi | iptal
);

-- WhatsApp gelen/giden mesaj logu (destek/tarih takibi için)
CREATE TABLE whatsapp_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID REFERENCES offers(id),
  direction TEXT NOT NULL, -- 'in' | 'out'
  phone TEXT NOT NULL,
  message_type TEXT,       -- 'text' | 'document' | 'template'
  content TEXT,
  wa_message_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Admin panelin "Ana Ekrana Ekle" bildirim aboneliği (Web Push)
CREATE TABLE push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint TEXT UNIQUE NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  user_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
