-- X Control Yapı — Şema Güncellemesi v13
-- "Ortak" rolü (ayrı firma gibi çalışan, izole edilmiş kullanıcı) için
-- manuel eklenen müşterilerin de sahibi olsun — böylece her "ortak" sadece
-- kendi müşterilerini görür, admin/muhasebe hâlâ hepsini görür.

ALTER TABLE customers ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

-- "Ortak" rolünün kendi malzeme stoğunu ve kendi oluşturduğu kullanıcıları
-- ayrı yönetebilmesi için (tam panel paritesi, sıfır eksik özellik).
ALTER TABLE materials ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);
