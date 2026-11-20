-- X Control Yapı — Şema Güncellemesi v18 (Görev paketi B): fatura TAKİBİ, KDV, vergi takvimi, tahsilat planı, WhatsApp şablonları
-- IDEMPOTENT (tekrar çalıştırılabilir). Önceki migrasyonlara dokunmaz. migrate.js kendi transaction'ında uygular. Önkoşul: v17 (organizations, set_default_org()).
--
-- KURALLAR
--  * Uygulama fatura KESMEZ; faturayı TAKİP eder. Tüm para alanları KURUŞ TAMSAYISI (BIGINT, *_kurus).
--    Mevcut payments/expenses/projects NUMERIC TL kalır (src/assistant/tax/money.js ile çevrilir).
--  * KDV oranları, tevkifat türleri, vergi takvimi ve tatiller VERİDİR (seed_org_tax_data() tohumu, kuruluş başına); koda gömülü sabit yoktur.
--    HEPSİ doğrulanmadı (verified = false) olarak tohumlanır (yalnız sabit tarihli ulusal bayramlar true): kullanıcı/mali müşavir düzenler ve
--    "doğrulandı" işaretler. Kaynaklar: research-tax-legal.md (§1.1, §1.2, §1.4, §2.2, §3.3). Hukuki/mali tavsiye DEĞİLDİR.
--  * owner_id = defter sahibi (mevcut model: admin/muhasebe → ilk admin; ortak → kendisi). org_id (v17): NOT NULL, set_default_org() tetikleyicisi.
--    Kuruluş verisi (oranlar/takvim/tatil/vergi ayarı) org_id'ye bağlıdır; YENİ kuruluş eklenince tohum otomatik (organizations AFTER INSERT tetikleyicisi).

------------------------------------------------------------------------------------------------
-- 1) Referans verisi: KDV oranları, tevkifat türleri, vergi ayarları (kuruluş başına; düzenlenebilir)
------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vat_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code TEXT NOT NULL,                                -- tohum anahtarı (kdv_genel …); kullanıcı eklerse serbest
  rate NUMERIC(5,2) NOT NULL CHECK (rate >= 0 AND rate <= 100),
  label TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,         -- fatura oluştururken kdv_oran verilmezse kullanılır
  enabled BOOLEAN NOT NULL DEFAULT true,
  valid_from DATE, valid_to DATE,                    -- KDV oranı fatura tarihindeki orana göre belirlenir (araştırma §1.1)
  verified BOOLEAN NOT NULL DEFAULT false,           -- false → "mali müşavire teyit" bayrağı API cevabında görünür
  source TEXT, note TEXT,
  verified_by UUID REFERENCES users(id) ON DELETE SET NULL, verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (org_id, code)
);

CREATE TABLE IF NOT EXISTS vat_withholding_types (   -- kısmi tevkifat türleri (pay/payda)
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  label TEXT NOT NULL,
  pay SMALLINT NOT NULL CHECK (pay >= 1), payda SMALLINT NOT NULL CHECK (payda >= pay AND payda <= 100),
  enabled BOOLEAN NOT NULL DEFAULT true,
  verified BOOLEAN NOT NULL DEFAULT false,
  source TEXT, note TEXT,
  verified_by UUID REFERENCES users(id) ON DELETE SET NULL, verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (org_id, code)
);

CREATE TABLE IF NOT EXISTS org_tax_settings (        -- statü / KDV dönemi: takvim filtresi ve /vat varsayılanı (araştırma §1.5, §6 madde 1)
  org_id UUID PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
  tax_status TEXT CHECK (tax_status IS NULL OR tax_status IN ('sahis','limited')),   -- NULL = belirtilmedi → yalnız herkesi ilgilendiren takvim kalemleri
  vat_period_type TEXT NOT NULL DEFAULT 'aylik' CHECK (vat_period_type IN ('aylik','uc_aylik')),
  note TEXT CHECK (note IS NULL OR length(note) <= 2000),
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

------------------------------------------------------------------------------------------------
-- 2) Faturalar (takip) + ekler
------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id),        -- defter sahibi (kullanıcı silinirken users.js kayıtları devreder)
  org_id UUID NOT NULL REFERENCES organizations(id),
  direction TEXT NOT NULL CHECK (direction IN ('giden','gelen')),
  invoice_type TEXT NOT NULL DEFAULT 'diger'
    CHECK (invoice_type IN ('e-fatura','e-arsiv','kagit','gider-pusulasi','serbest-meslek','mustahsil','diger')),
  invoice_no TEXT CHECK (invoice_no IS NULL OR length(invoice_no) <= 64),
  ettn TEXT CHECK (ettn IS NULL OR length(ettn) <= 64),   -- e-Fatura/e-Arşiv belge kimliği (varsa)
  issue_date DATE NOT NULL,                           -- KDV dönemi bu tarihten belirlenir
  due_date DATE,
  counterparty TEXT CHECK (counterparty IS NULL OR length(counterparty) <= 200),
  counterparty_tax_id TEXT CHECK (counterparty_tax_id IS NULL OR counterparty_tax_id ~ '^[0-9]{10}$|^[0-9]{11}$'),  -- VKN 10 / TCKN 11
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  offer_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  expense_id UUID REFERENCES expenses(id) ON DELETE SET NULL,
  matrah_kurus BIGINT NOT NULL CHECK (matrah_kurus >= 0 AND matrah_kurus <= 1000000000000),
  kdv_oran NUMERIC(5,2) NOT NULL CHECK (kdv_oran >= 0 AND kdv_oran <= 100),
  kdv_istisna_nedeni TEXT CHECK (kdv_istisna_nedeni IS NULL OR length(kdv_istisna_nedeni) <= 200),
  kdv_kurus BIGINT NOT NULL CHECK (kdv_kurus >= 0),
  tevkifat_pay SMALLINT, tevkifat_payda SMALLINT,     -- kısmi tevkifat oranı pay/payda (ör. 4/10); ikisi de NULL = tevkifat yok
  tevkifat_kurus BIGINT NOT NULL DEFAULT 0 CHECK (tevkifat_kurus >= 0),
  tutar_kurus BIGINT NOT NULL CHECK (tutar_kurus >= 0),   -- genel toplam (KDV dahil, tevkifat DÜŞÜLMEMİŞ)
  odenecek_kurus BIGINT GENERATED ALWAYS AS (tutar_kurus - tevkifat_kurus) STORED,  -- tahsil edilecek/ödenecek
  kdv_indirilebilir BOOLEAN NOT NULL DEFAULT true,    -- gelen fatura: indirilecek KDV'ye girer mi (kullanıcı/mali müşavir onaylı)
  status TEXT NOT NULL DEFAULT 'kesildi' CHECK (status IN ('taslak','kesildi','gonderildi','odendi','iptal')),
  paid_at DATE,
  note TEXT CHECK (note IS NULL OR length(note) <= 2000),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT invoices_total_chk CHECK (tutar_kurus = matrah_kurus + kdv_kurus),
  CONSTRAINT invoices_wh_chk CHECK (
    (tevkifat_pay IS NULL AND tevkifat_payda IS NULL AND tevkifat_kurus = 0)
    OR (tevkifat_pay >= 1 AND tevkifat_payda >= tevkifat_pay AND tevkifat_payda <= 100 AND tevkifat_kurus <= kdv_kurus))
);
CREATE INDEX IF NOT EXISTS idx_invoices_owner_date   ON invoices (owner_id, issue_date DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_owner_dir    ON invoices (owner_id, direction, status);
CREATE INDEX IF NOT EXISTS idx_invoices_due_open     ON invoices (owner_id, due_date) WHERE status IN ('kesildi','gonderildi');
CREATE INDEX IF NOT EXISTS idx_invoices_project      ON invoices (project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_no           ON invoices (owner_id, direction, lower(invoice_no)) WHERE invoice_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_org          ON invoices (org_id);

CREATE TABLE IF NOT EXISTS invoice_files (          -- fatura fotoğrafı/PDF ekleri (uploads/invoices/…)
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  file_url TEXT NOT NULL, file_name TEXT NOT NULL,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_invoice_files_invoice ON invoice_files (invoice_id);
CREATE INDEX IF NOT EXISTS invoice_files_name_idx    ON invoice_files ((substring(file_url from '[^/?]+$')));  -- /uploads yetki denetimi (v16 kalıbı)

------------------------------------------------------------------------------------------------
-- 3) KDV dönemleri (hesaplanmış anlık görüntü + kilit)
------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vat_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- türetilmiş veri: kullanıcıyla birlikte silinir
  org_id UUID NOT NULL REFERENCES organizations(id),
  period_key TEXT NOT NULL,                           -- 'YYYY-MM' (aylık) | 'YYYY-Qn' (3 aylık)
  period_type TEXT NOT NULL CHECK (period_type IN ('aylik','uc_aylik')),
  year SMALLINT NOT NULL, month SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),   -- dönemin ilk ayı
  starts_on DATE NOT NULL, ends_on DATE NOT NULL,
  hesaplanan_kurus BIGINT NOT NULL DEFAULT 0,
  indirilecek_kurus BIGINT NOT NULL DEFAULT 0,
  onceki_devreden_kurus BIGINT NOT NULL DEFAULT 0,    -- bu dönemde kullanılan önceki devreden
  manual_carry_in_kurus BIGINT CHECK (manual_carry_in_kurus IS NULL OR manual_carry_in_kurus >= 0),  -- elle girilmiş açılış devredeni (uygulama öncesi dönemlerden)
  odenecek_kurus BIGINT NOT NULL DEFAULT 0,
  devreden_kurus BIGINT NOT NULL DEFAULT 0,           -- sonraki döneme devreden
  kdv2_kurus BIGINT NOT NULL DEFAULT 0,               -- bilgi: gelen faturalardaki tevkifat (KDV-2 ile ayrıca beyan/ödenir)
  indirilemeyen_kurus BIGINT NOT NULL DEFAULT 0,      -- bilgi: indirilemez işaretli gelen KDV
  due_date DATE,                                      -- tahmini son gün (vergi takvimi kuralından; kaydırmalı)
  status TEXT NOT NULL DEFAULT 'acik' CHECK (status IN ('acik','kilitli')),
  locked_at TIMESTAMPTZ, locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
  note TEXT CHECK (note IS NULL OR length(note) <= 2000),
  computed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, period_key)
);
CREATE INDEX IF NOT EXISTS idx_vat_periods_locked ON vat_periods (owner_id, starts_on, ends_on) WHERE status = 'kilitli';

------------------------------------------------------------------------------------------------
-- 4) Tahsilat planı (taksit / vade / çek-senet)
------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id),
  org_id UUID NOT NULL REFERENCES organizations(id),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  offer_id UUID REFERENCES offers(id) ON DELETE CASCADE,
  invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
  kind TEXT NOT NULL DEFAULT 'taksit' CHECK (kind IN ('avans','ara','bakiye','taksit','cek','senet')),
  amount_kurus BIGINT NOT NULL CHECK (amount_kurus > 0 AND amount_kurus <= 1000000000000),
  due_date DATE NOT NULL,
  method TEXT CHECK (method IS NULL OR method IN ('Havale','Nakit','Kredi Kartı','Çek','Senet')),
  status TEXT NOT NULL DEFAULT 'bekliyor' CHECK (status IN ('bekliyor','odendi','iptal')),   -- 'gecikti' türetilir (bekliyor + vade geçmiş)
  paid_at DATE,
  paid_payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  instrument_no TEXT CHECK (instrument_no IS NULL OR length(instrument_no) <= 64),   -- çek/senet no
  bank TEXT CHECK (bank IS NULL OR length(bank) <= 100),
  installment_no SMALLINT, group_id UUID,             -- "taksit üret" ile oluşan planın üyeleri
  note TEXT CHECK (note IS NULL OR length(note) <= 1000),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payment_schedule_target_chk CHECK (project_id IS NOT NULL OR offer_id IS NOT NULL OR invoice_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_payment_schedule_owner_due ON payment_schedule (owner_id, due_date) WHERE status = 'bekliyor';
CREATE INDEX IF NOT EXISTS idx_payment_schedule_project   ON payment_schedule (project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_schedule_offer     ON payment_schedule (offer_id) WHERE offer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_schedule_invoice   ON payment_schedule (invoice_id) WHERE invoice_id IS NOT NULL;

------------------------------------------------------------------------------------------------
-- 5) Vergi takvimi + resmî tatiller (veri; kuruluş başına; yıllık güncellenir)
------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tax_calendar_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  key TEXT NOT NULL,                                  -- kararlı kod (kdv1_aylik …)
  title TEXT NOT NULL CHECK (length(title) <= 200),
  kind TEXT CHECK (kind IS NULL OR kind IN ('kdv','kdv2','muhtasar','gecici_vergi','yillik_beyan','ba_bs','e_defter','sgk','bilgi','diger')),
  rule JSONB,                                         -- tekrar kuralı (bkz. assistant/tax/taxCalendar.js) — NULL ise due_date tek seferlik
  due_date DATE,
  period_label TEXT,
  applies_to TEXT NOT NULL DEFAULT 'hepsi' CHECK (applies_to IN ('hepsi','sahis','limited')),
  enabled BOOLEAN NOT NULL DEFAULT true,
  verified BOOLEAN NOT NULL DEFAULT false,            -- "doğrulandı mı"; false → mali müşavire teyit bayrağı
  confidence TEXT NOT NULL DEFAULT 'belirsiz' CHECK (confidence IN ('birincil','ikincil','belirsiz')),
  source TEXT, note TEXT,
  verified_by UUID REFERENCES users(id) ON DELETE SET NULL, verified_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tax_calendar_when_chk CHECK (rule IS NOT NULL OR due_date IS NOT NULL),
  UNIQUE (org_id, key)
);

CREATE TABLE IF NOT EXISTS holidays_tr (
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'resmi' CHECK (kind IN ('resmi','dini','idari')),
  half_day BOOLEAN NOT NULL DEFAULT false,            -- arife yarım günü: iş günü sayılır
  verified BOOLEAN NOT NULL DEFAULT false,
  source TEXT, note TEXT,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, day)
);

-- set_default_org(): INSERT'te org_id verilmezse varsayılan kuruluş atanır (v17 kalıbı)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['invoices','vat_periods','payment_schedule','tax_calendar_items','holidays_tr','vat_rates','vat_withholding_types'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_default_org ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_default_org BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_default_org()', t);
  END LOOP;
END $$;

-- Tohum işlevi: bir kuruluş için KDV oranları, tevkifat türleri, vergi takvimi ve tatilleri ekler (idempotent; mevcut/düzenlenmiş kayıtlara dokunmaz).
-- Hepsi verified=false (sabit tarihli ulusal bayramlar hariç): birincil kaynakla (GİB PDF, Resmî Gazete) çapraz kontrol EDİLMEDİ.
-- confidence: ikincil = araştırmada ikincil kaynakla (2026 takvimiyle birebir örtüşen) bulunan; belirsiz = araştırmada [?] ya da kaynak çelişkisi olan.
CREATE OR REPLACE FUNCTION seed_org_tax_data(p_org UUID) RETURNS void AS $fn$
BEGIN
INSERT INTO vat_rates (org_id, code, rate, label, is_default, verified, source, note) VALUES
 (p_org, 'kdv_genel', 20, 'Genel oran', true, false,
  'research-tax-legal.md §1.1 (CK 2007/13033; ikincil kaynak, birincil metin okunamadı)',
  'Tadilat, demir doğrama imalat+montaj, otomatik kapı ve pergola işleri için indirimli oran dayanağı bulunamadı; konut tadilatına özel oran var mı sorusu yanıtsız [?]. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'kdv_ii_liste', 10, 'II sayılı liste oranı', false, false,
  'research-tax-legal.md §1.1 (ikincil kaynak)',
  'Hangi işlemlerin kapsandığı (ör. net 150 m² konut teslimi) mali müşavire teyit edilmeli.'),
 (p_org, 'kdv_i_liste', 1, 'I sayılı liste oranı', false, false,
  'research-tax-legal.md §1.1 (ikincil kaynak)',
  'Kooperatif/belediye/kurum inşaat taahhüdü ve 6306 riskli yapı işleri gibi özel haller; mali müşavire teyit.'),
 (p_org, 'kdv_istisna_0', 0, 'KDV istisnası / KDV''siz', false, false,
  'Ürün kararı: istisna nedeni kdv_istisna_nedeni alanında tutulur',
  'İstisna kapsamı ve belge şekli mali müşavire teyit edilmeli.')
ON CONFLICT DO NOTHING;
INSERT INTO vat_withholding_types (org_id, code, pay, payda, label, verified, source, note) VALUES
 (p_org, 'yapim_isleri_4_10', 4, 10, 'Yapım işleri ile bu işlerle birlikte ifa edilen mühendislik-mimarlık ve etüt-proje hizmetleri', false,
  'research-tax-legal.md §1.2 (KDV GUT I/C-2.1.3.2.1; iki güncel ikincil kaynak 4/10)',
  'Tevkifatı ALICI uygular; alıcı kategorisi ve 5 milyon TL sınırı için GUT I/C-2.1.3.1 (a)/(b) listeleri okunamadı [?]. Eski bir tabloda 3/10 görünür (güncel kabul edilmedi). Pergola/doğrama imalat+montajın yapım işi sayılıp sayılmayacağı özelge konusudur. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'makine_bakim_onarim_7_10', 7, 10, 'Makine, teçhizat, demirbaş ve taşıtlara ait tadil, bakım ve onarım hizmetleri', false,
  'research-tax-legal.md §1.2 (2025 tablosu 7/10; 2020 tablosu 5/10 — çelişki)',
  'Otomatik kapı bakım/servis sözleşmeleri alıcı kategorisine göre bu kapsama girebilir. MALİ MÜŞAVİRE TEYİT.')
ON CONFLICT DO NOTHING;

-- Tohum: vergi takvimi — HEPSİ verified=false (hiçbiri birincil kaynakla (GİB PDF) çapraz kontrol edilmedi). confidence: ikincil = araştırmada
-- ikincil kaynakla (tarihler 2026 takvimiyle birebir örtüşüyor) bulunan; belirsiz = araştırmada [?] ya da kaynak çelişkisi olan.
INSERT INTO tax_calendar_items (org_id, key, title, kind, rule, due_date, applies_to, enabled, confidence, source, note) VALUES
 (p_org, 'kdv1_aylik', 'KDV-1 beyanı ve ödemesi (aylık dönem)', 'kdv', '{"freq":"monthly","day":28,"period_offset_months":1}', NULL, 'hepsi', true, 'ikincil',
  'research-tax-legal.md §1.4 (muhasebetr 2026 takvimi); design-assistant.md §3.2 [K, NTV]: dönemi izleyen ayın 28''i',
  'Hafta sonu/resmî tatilde izleyen iş gününe ertelenir. GİB PDF ile çapraz kontrol edilmedi — MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'kdv1_uc_aylik', 'KDV-1 beyanı ve ödemesi (3 aylık dönem)', 'kdv', '{"freq":"quarterly","day":28,"period_offset_months":1}', NULL, 'hepsi', false, 'belirsiz',
  'research-tax-legal.md §1.4 (28 Ocak/Nisan/Temmuz/Ekim)',
  'Yalnızca belirli mükellef grupları 3 aylık dönemde beyan verir [MM]. Varsayılan KAPALI; mükellefse açın. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'kdv2_tevkifat', 'KDV-2 (tevkifat) beyanı', 'kdv2', '{"freq":"monthly","day":25,"period_offset_months":1}', NULL, 'hepsi', false, 'belirsiz',
  'research-tax-legal.md §1.4 [?]',
  'Kaynakta Ekim dönemi için 25 Kasım yazıyor; kanundaki 24''ü/26''sı ayrımı ve tatil kaydırması teyit edilmedi. Varsayılan KAPALI (tevkifat uygulayan alıcılar için). MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'muhtasar_aylik', 'Muhtasar ve Prim Hizmet beyanı (aylık)', 'muhtasar', '{"freq":"monthly","day":26,"period_offset_months":1}', NULL, 'hepsi', true, 'ikincil',
  'research-tax-legal.md §1.4 (muhasebetr 2026 takvimi)',
  'Çalışanı/stopaj yükümlülüğü olmayanlar için geçerli olmayabilir. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'muhtasar_uc_aylik', 'Muhtasar beyanı (3 aylık, GVK 98/3)', 'muhtasar', '{"freq":"quarterly","day":26,"period_offset_months":1}', NULL, 'hepsi', false, 'ikincil',
  'research-tax-legal.md §1.4', 'Varsayılan KAPALI. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'gecici_vergi', 'Geçici vergi beyanı ve ödemesi', 'gecici_vergi',
  '{"freq":"yearly","dates":[{"month":5,"day":17,"label":"I. dönem (Ocak-Mart)"},{"month":8,"day":17,"label":"II. dönem (Nisan-Haziran)"},{"month":11,"day":17,"label":"III. dönem (Temmuz-Eylül)"}]}',
  NULL, 'hepsi', true, 'ikincil',
  'research-tax-legal.md §1.4 (2026: 18 Mayıs, 17 Ağustos, 17 Kasım)', 'IV. dönem yoktur (yıllık beyana dahil). MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'yillik_gelir_vergisi', 'Yıllık gelir vergisi beyanı / taksitleri', 'yillik_beyan',
  '{"freq":"yearly","dates":[{"month":3,"day":31,"label":"Beyan ve 1. taksit"},{"month":7,"day":31,"label":"2. taksit"}]}',
  NULL, 'sahis', true, 'ikincil', 'research-tax-legal.md §1.4 (2026: 31 Mart ve 31 Temmuz)', 'Gerçek kişi (şahıs) işletmeleri için. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'kurumlar_vergisi', 'Kurumlar vergisi beyanı (limited/anonim)', 'yillik_beyan',
  '{"freq":"yearly","dates":[{"month":4,"day":30,"label":"Yıllık beyan (nisan sonu)"}]}',
  NULL, 'limited', true, 'belirsiz', 'research-tax-legal.md §1.4 [?]', 'Kesin son gün araştırmada doğrulanamadı; 30 Nisan YER TUTUCUDUR. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'ba_bs', 'Ba-Bs formu bildirimi', 'ba_bs', '{"freq":"monthly","day":"last","period_offset_months":1}', NULL, 'hepsi', true, 'belirsiz',
  'research-tax-legal.md §1.4 [?] (genel bilgi: izleyen ayın son günü)',
  'Tarih ve bildirim sınırı (5.000 TL KDV hariç, 2026''da değişti mi?) doğrulanamadı. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'e_defter_berat_gv', 'e-Defter berat yükleme (gelir vergisi mükellefi)', 'e_defter', '{"freq":"monthly","day":10,"period_offset_months":4}', NULL, 'sahis', false, 'belirsiz',
  'research-tax-legal.md §1.4 (Temmuz için 10 Kasım, Ağustos için 10 Aralık)', 'Yalnızca e-Defter mükellefleri; varsayılan KAPALI. Aralık yapısı tek kaynakta. MALİ MÜŞAVİRE TEYİT.'),
 (p_org, 'e_defter_berat_diger', 'e-Defter berat yükleme (diğer mükellefler)', 'e_defter', '{"freq":"monthly","day":14,"period_offset_months":4}', NULL, 'limited', false, 'belirsiz',
  'research-tax-legal.md §1.4 (Temmuz için 16 Kasım, Ağustos için 14 Aralık)', 'Yalnızca e-Defter mükellefleri; varsayılan KAPALI. MALİ MÜŞAVİRE TEYİT.')
ON CONFLICT DO NOTHING;
INSERT INTO tax_calendar_items (org_id, key, title, kind, rule, due_date, applies_to, enabled, confidence, source, note) VALUES
 (p_org, 'kagit_fatura_istisna_sonu', 'Basit usul / işletme hesabı: 3.000 TL altı kâğıt fatura istisnasının son günü (01.01.2027''den itibaren tam e-belge)', 'bilgi', NULL, '2026-12-31', 'hepsi', true, 'ikincil',
  'research-tax-legal.md §2.2 (VUK Genel Tebliği Sıra No 589, RG 31.12.2025 5. Mükerrer; [B/İ])',
  'Bilgi kaydıdır; ertelenmiş tebliğ ikincil kaynaklarla okundu. MALİ MÜŞAVİRE TEYİT.')
ON CONFLICT DO NOTHING;

-- Tohum: resmî tatiller 2026-2027. Sabit tarihli ulusal bayram/genel tatiller (2429 sayılı Kanun) verified=true;
-- dini bayramlar ve arifeler Diyanet takvimine bağlıdır → verified=false ("Diyanet/Resmî Gazete ile teyit edin").
-- İdari izin/köprü günleri önceden bilinemez ve tohumlanmamıştır; yıllık elle eklenir.
INSERT INTO holidays_tr (org_id, day, name, kind, half_day, verified, source, note) VALUES
 (p_org, '2026-01-01', 'Yılbaşı', 'resmi', false, true, 'Sabit tarihli genel tatil (2429 sayılı Kanun)', NULL),
 (p_org, '2026-03-19', 'Ramazan Bayramı Arifesi (yarım gün)', 'dini', true, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-03-20', 'Ramazan Bayramı 1. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-03-21', 'Ramazan Bayramı 2. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-03-22', 'Ramazan Bayramı 3. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2026-05-01', 'Emek ve Dayanışma Günü', 'resmi', false, true, 'Sabit tarihli genel tatil (2429 sayılı Kanun)', NULL),
 (p_org, '2026-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2026-05-26', 'Kurban Bayramı Arifesi (yarım gün)', 'dini', true, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-05-27', 'Kurban Bayramı 1. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', 'research-tax-legal.md §1.4 tablosu 28 Mayıs KDV son gününün 1 Haziran''a ertelendiğini gösterir (tutarlı).'),
 (p_org, '2026-05-28', 'Kurban Bayramı 2. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-05-29', 'Kurban Bayramı 3. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-05-30', 'Kurban Bayramı 4. gün', 'dini', false, false, 'Dini bayram: Diyanet takvimiyle teyit edin', NULL),
 (p_org, '2026-07-15', 'Demokrasi ve Milli Birlik Günü', 'resmi', false, true, 'Sabit tarihli genel tatil', NULL),
 (p_org, '2026-08-30', 'Zafer Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2026-10-28', 'Cumhuriyet Bayramı Arifesi (yarım gün)', 'resmi', true, true, 'Sabit tarihli (2429 sayılı Kanun)', NULL),
 (p_org, '2026-10-29', 'Cumhuriyet Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2027-01-01', 'Yılbaşı', 'resmi', false, true, 'Sabit tarihli genel tatil (2429 sayılı Kanun)', NULL),
 (p_org, '2027-03-08', 'Ramazan Bayramı Arifesi (yarım gün)', 'dini', true, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', 'Bayram günleri ay görünümüne bağlıdır; 9-11 Mart varsayımı.'),
 (p_org, '2027-03-09', 'Ramazan Bayramı 1. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-03-10', 'Ramazan Bayramı 2. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-03-11', 'Ramazan Bayramı 3. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2027-05-01', 'Emek ve Dayanışma Günü', 'resmi', false, true, 'Sabit tarihli genel tatil (2429 sayılı Kanun)', NULL),
 (p_org, '2027-05-15', 'Kurban Bayramı Arifesi (yarım gün)', 'dini', true, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', 'Bayram günleri ay görünümüne bağlıdır; 16-19 Mayıs varsayımı.'),
 (p_org, '2027-05-16', 'Kurban Bayramı 1. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-05-17', 'Kurban Bayramı 2. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-05-18', 'Kurban Bayramı 3. gün', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', NULL),
 (p_org, '2027-05-19', 'Kurban Bayramı 4. gün / Atatürk''ü Anma, Gençlik ve Spor Bayramı', 'dini', false, false, 'TAHMİNİ: Diyanet 2027 takvimi yayımlanınca teyit edin', '19 Mayıs sabit tarihli resmî tatildir (tek kayıtta birleşti).'),
 (p_org, '2027-07-15', 'Demokrasi ve Milli Birlik Günü', 'resmi', false, true, 'Sabit tarihli genel tatil', NULL),
 (p_org, '2027-08-30', 'Zafer Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL),
 (p_org, '2027-10-28', 'Cumhuriyet Bayramı Arifesi (yarım gün)', 'resmi', true, true, 'Sabit tarihli (2429 sayılı Kanun)', NULL),
 (p_org, '2027-10-29', 'Cumhuriyet Bayramı', 'resmi', false, true, 'Sabit tarihli ulusal bayram (2429 sayılı Kanun)', NULL)
ON CONFLICT DO NOTHING;
END;
$fn$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION trg_seed_org_tax_data() RETURNS trigger AS $$
BEGIN
  PERFORM seed_org_tax_data(NEW.id);
  INSERT INTO org_tax_settings (org_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_seed_org_tax ON organizations;
CREATE TRIGGER trg_seed_org_tax AFTER INSERT ON organizations FOR EACH ROW EXECUTE FUNCTION trg_seed_org_tax_data();

-- Mevcut kuruluşlar için tohum (idempotent)
SELECT seed_org_tax_data(id) FROM organizations;
INSERT INTO org_tax_settings (org_id) SELECT id FROM organizations ON CONFLICT DO NOTHING;

------------------------------------------------------------------------------------------------
-- 6) WhatsApp mesaj şablonları (sıfır maliyet: wa.me derin bağlantısı; gönderimi kullanıcı yapar)
------------------------------------------------------------------------------------------------
-- owner_id NULL + is_system = sistem şablonu (salt okunur, tüm kuruluşlarda görünür). Dolu owner_id = o DEFTERİN özelleştirmesi (aynı anahtarı ezer):
-- admin/muhasebe ortak (işletme) defterini, ortak kendi defterini özelleştirir.
CREATE TABLE IF NOT EXISTS message_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
  org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  key TEXT NOT NULL CHECK (key ~ '^[a-z0-9_]{2,60}$'),     -- teklif_gonderimi, odeme_nazik … (özelleştirme aynı anahtarı ezer)
  title TEXT NOT NULL CHECK (length(title) <= 120),
  category TEXT NOT NULL DEFAULT 'diger' CHECK (category IN ('teklif','randevu','odeme','tesekkur','diger')),
  tone TEXT CHECK (tone IS NULL OR tone IN ('nazik','orta','kesin')),
  sector TEXT CHECK (sector IS NULL OR length(sector) <= 60),  -- sektöre özel varyant (NULL = genel)
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
  legal_note TEXT,
  is_system BOOLEAN NOT NULL DEFAULT false,
  enabled BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT message_templates_scope_chk CHECK ((is_system AND owner_id IS NULL AND org_id IS NULL) OR (NOT is_system AND owner_id IS NOT NULL AND org_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_message_templates_scope
  ON message_templates (COALESCE(owner_id, '00000000-0000-0000-0000-000000000000'::uuid), key, COALESCE(sector, ''));

-- Tohum metinleri: research-tax-legal.md §3.3 nazik şablonlarından. TANITIM/KAMPANYA YOK (Ticari İleti Yönetmeliği md. 6/2 bilgilendirme
-- istisnası yalnız tanıtımsız mesajlar içindir). {ret_notu} yalnız opt_out=true ile dolar ("DUR" cümlesi [AV] ile kesinleştirilmeli).
INSERT INTO message_templates (key, title, category, tone, body, legal_note, is_system, sort_order) VALUES
 ('teklif_gonderimi', 'Teklif gönderimi', 'teklif', NULL,
  $t$Merhaba {ad}, {firma_adi} olarak {hizmet} için hazırladığımız teklifi buradan inceleyebilirsiniz: {takip_linki}
[[Teklif tutarı: {tutar} TL (KDV dahil). ]]Sorularınız için bize [[{telefon} numarasından ]]ulaşabilirsiniz.$t$,
  NULL, true, 10),
 ('teklif_takip', 'Teklif takibi', 'teklif', 'nazik',
  $t$Merhaba {ad}, {teklif_kodu} numaralı {hizmet} teklifimizi inceleme fırsatı buldunuz mu? Teklife buradan ulaşabilirsiniz: {takip_linki} Değiştirmek istediğiniz bir kalem ya da sorunuz olursa memnuniyetle yardımcı oluruz.$t$,
  NULL, true, 20),
 ('randevu_hatirlatma', 'Randevu hatırlatma', 'randevu', NULL,
  $t$Merhaba {ad}, {tarih} {gun} günü saat {saat} için planladığımız [[{randevu_turu} ]]randevuyu hatırlatmak isteriz. [[Adres: {adres}. ]]Saat uygun değilse [[{telefon} numarasından ]]bize bildirebilirsiniz. {firma_adi}$t$,
  NULL, true, 30),
 ('odeme_nazik', 'Ödeme hatırlatma (nazik)', 'odeme', 'nazik',
  $t$Merhaba {ad}, {firma_adi|den} yazıyoruz. [[{proje_kodu} numaralı işinize ait ]]{tutar} TL tutarındaki ödemenin vadesi {vade_tarihi}. [[Ödeme bilgilerimiz: {iban_unvan}. ]]Ödemeniz yapıldıysa lütfen bu mesajı dikkate almayın, teşekkür ederiz.[[ Bilgi için: {telefon}.]][[ {ret_notu}]]$t$,
  'Vade günü / 1 gün önce. Tanıtım içermez (Ticari İleti Yönetmeliği md. 6/2 — avukata teyit).', true, 40),
 ('odeme_orta', 'Ödeme hatırlatma (orta)', 'odeme', 'orta',
  $t$Merhaba {ad}, [[{proje_kodu} işine ait ]]{tutar} TL'lik ödemenin vadesi {vade_tarihi} tarihinde dolmuştur. Unutulmuş olabileceğini düşünerek hatırlatmak istedik. Ödeme yaptıysanız dekontu bu yazışmadan iletebilirsiniz. Bir sorun varsa birlikte çözebiliriz.[[ {ret_notu}]]$t$,
  'Vade geçmiş (3-7 gün). Tehdit/icra dili yok; günde birden fazla mesaj ve gece saatleri önerilmez.', true, 50),
 ('odeme_kesin', 'Ödeme hatırlatma (kesin)', 'odeme', 'kesin',
  $t$Merhaba {ad}, {kalan_tutar} TL tutarında ödeme bakiyesi görünmektedir (vade: {vade_tarihi}).[[ İlgili iş: {proje_kodu}.]][[ Fatura no: {fatura_no}.]] Bu hafta içinde ödeme planı konusunda bize dönüş yapabilir misiniz?[[ {telefon} numarasından ulaşabilirsiniz.]][[ {ret_notu}]]$t$,
  'İkinci hatırlatma (15+ gün): sakin ama net. Borcu üçüncü kişilere bildirmeyin; tehdit/aşağılayıcı ifade yok (avukata teyit).', true, 60),
 ('tesekkur', 'Teşekkür', 'tesekkur', NULL,
  $t$Merhaba {ad}, {hizmet} işimizi tamamladık; bizi tercih ettiğiniz için teşekkür ederiz. Herhangi bir sorunuz olursa [[{telefon} numarasından ]]bize ulaşabilirsiniz. {firma_adi}$t$,
  'Tanıtım/kampanya eklemeyin (ticari ileti sayılır).', true, 70)
ON CONFLICT DO NOTHING;
