# X Control Yapı — Backend Kurulum Rehberi

Bu klasör, admin panelin gerçek verilerle çalışması için gereken API sunucusunu içerir:
teklif alma, teklif hazırlama + otomatik WhatsApp/e-posta ile PDF gönderimi, proje/ödeme
takibi ve raporlama.

## 1. Gereksinimler

- Bir VPS (örn. Hetzner CX22, DigitalOcean Droplet) — Ubuntu 22.04 önerilir
- Node.js **20+** (v16: nodemailer 10 ve multer 2 için; Node 18 artık yeterli değildir)
- PostgreSQL 14+
- Bir alan adı (controlx.com.tr zaten mevcut — `api.controlx.com.tr` alt alan adını buna yönlendireceğiz)
- Meta (Facebook) Business hesabı → WhatsApp Cloud API için
- SMTP e-posta hesabı (mevcut info@controlx.com.tr kutunuzun SMTP bilgileri)

## 2. Sunucu Kurulumu (VPS üzerinde, tek seferlik)

```bash
# Sistemi güncelle
sudo apt update && sudo apt upgrade -y

# Node.js 20 kur
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# PostgreSQL kur
sudo apt install -y postgresql postgresql-contrib

# PM2 (Node.js için process manager — sunucu yeniden başlasa da API ayakta kalır)
sudo npm install -g pm2

# Nginx (reverse proxy + SSL için)
sudo apt install -y nginx certbot python3-certbot-nginx
```

## 3. Veritabanı Oluşturma

```bash
sudo -u postgres psql

CREATE DATABASE xcontrol_db;
CREATE USER xcontrol_user WITH ENCRYPTED PASSWORD 'GUCLU_BIR_SIFRE';
GRANT ALL PRIVILEGES ON DATABASE xcontrol_db TO xcontrol_user;
\q
```

## 4. Proje Dosyalarını Sunucuya Yükleme

```bash
# Yerel makinenizden sunucuya kopyalayın (klasörün tamamını)
scp -r backend kullanici@sunucu_ip:/var/www/xcontrol

# Sunucuda
cd /var/www/xcontrol
npm install
cp .env.example .env
nano .env   # gerçek bilgilerinizi girin (aşağıdaki bölümlere bakın)
```

## 5. .env Dosyasını Doldurma

`.env.example` dosyasındaki her değeri gerçek bilgilerinizle değiştirin:

- **DATABASE_URL** — 3. adımda oluşturduğunuz kullanıcı/şifre
- **JWT_SECRET** — rastgele, **en az 32 karakter** (`openssl rand -hex 32`; 16–31 karakter uyarı verir, `JWT_SECRET_STRICT=true` ile reddedilir)
- **SMTP_*** — e-posta sağlayıcınızın SMTP bilgileri
- **WHATSAPP_*** — aşağıdaki adımda anlatılan Meta kurulumundan gelen değerler

## 6. WhatsApp Business API (Meta Cloud API) Kurulumu

1. [business.facebook.com](https://business.facebook.com) üzerinde bir Meta Business hesabı oluşturun (firma bilgileriyle).
2. [developers.facebook.com](https://developers.facebook.com) → "Uygulama Oluştur" → **WhatsApp** ürününü ekleyin.
3. Test numarası yerine firmanızın gerçek WhatsApp numarasını (0530 393 18 40) doğrulayın.
4. **Phone Number ID** ve **Access Token** değerlerini `.env` dosyasına yazın.
5. Kalıcı (süresiz) token için "System User" oluşturup ona kalıcı token atamanız gerekir — geçici token'lar 24 saatte sona erer.
6. **Önemli kısıtlama:** WhatsApp, işletmenin müşteriye 24 saatlik pencere dışında serbest metin göndermesine izin vermez. Bu nedenle teklif gönderimi gibi mesajlar için Meta'ya "mesaj şablonu" (message template) başvurusu yapmanız ve onaylatmanız gerekir. Bu, kurulumda genelde 1-2 gün sürer.

## 7. Veritabanı Şemasını Yükleme ve İlk Admin Kullanıcı

```bash
cd /var/www/xcontrol
node src/migrate.js   # şema dosyalarını (schema.sql, v2…v15) sırayla ve yalnızca bir kez uygular; tekrar çalıştırmak güvenlidir
```

Bu komut şemayı oluşturur ve sizden ilk admin kullanıcının bilgilerini (ad, e-posta, şifre) sorar.

## 8. Uygulamayı PM2 ile Başlatma

```bash
pm2 start src/server.js --name xcontrol-api
pm2 save
pm2 startup   # sunucu yeniden başlasa da otomatik ayağa kalkması için verilen komutu çalıştırın
```

## 9. Nginx Reverse Proxy + SSL

`/etc/nginx/sites-available/xcontrol-api` dosyası oluşturun:

```nginx
server {
    listen 80;
    server_name api.controlx.com.tr;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # ŞART (v16): hız sınırı gerçek istemci IP'sine göre çalışır; bu başlık olmadan herkes 127.0.0.1 görünür ve tek kovayı paylaşır
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 20m;   # mobil/panel dosya-fotoğraf yükleme (API sınırı 15 MB; nginx varsayılanı 1 MB'dır)
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/xcontrol-api /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# SSL sertifikası (ücretsiz, Let's Encrypt)
sudo certbot --nginx -d api.controlx.com.tr
```

DNS ayarlarınızda (alan adı sağlayıcınızda) `api.controlx.com.tr` için bir **A kaydı** oluşturup VPS'in IP adresini girmeniz gerekir.

## 10. Public Web Sitesini Bu API'ye Bağlama

`index.html` içindeki teklif formu şu an WhatsApp/mailto linklerine yönlendiriyor (geçici çözüm).
Gerçek entegrasyon için form gönderim kodu şu şekilde değişecek:

```javascript
fetch('https://api.controlx.com.tr/api/offers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name, phone, email, service, region, message })
})
.then(res => res.json())
.then(data => {
  // data.trackingUrl → müşteriye "teklifinizi buradan takip edebilirsiniz" gösterilir
});
```

## 11. Admin Panelini Bu API'ye Bağlama

Şu anki admin panel prototipi tarayıcı içi `window.storage` kullanıyor (demo amaçlı).
Gerçek kuruluma geçişte, panel `fetch()` çağrılarıyla `https://api.controlx.com.tr/api/...`
uçlarını kullanacak şekilde güncellenecek — bu, bir sonraki adımda yapılacak.

## 12. Test Etme

```bash
curl https://api.controlx.com.tr/api/health
# {"status":"ok","time":"..."}

curl -X POST https://api.controlx.com.tr/api/offers \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Müşteri","phone":"05321234567","service":"Demir Doğrama"}'
```

---

## 13. v15 / mobil uygulama hazırlığı

Flutter mobil uygulaması için API'ye eklenenler. **Mevcut migrasyonlar (schema.sql, v2…v14) değişmedi**; yenilikler
`src/schema_v15.sql` içindedir (idempotent, `node src/migrate.js` otomatik uygular). Mevcut web paneli istekleri bozulmaz
(yeni alanlar eklemelidir). Ayrıntılı uç nokta sözleşmesi: `mobile-api-contract.md`.

**Şema (v15):** `offers/customers/projects/appointments` → `address`, `lat`, `lng` (NUMERIC(9,6), ikisi birlikte);
`appointments` → `customer_name`, `customer_phone`; `users.token_version`; `quotes.last_send_status|last_send_at|last_send_error`;
`device_tokens` tablosu; ana ekran sorguları için indeksler. (Düşük stok için `materials.low_stock_threshold` zaten vardı; API'de `min_stock` takma adıyla döner.)

**Yeni / değişen uçlar**
- `GET /api/mobile/home` — tek istekte, role göre kapsamlı ana ekran (bugün/yarın randevu, yeni teklifler, teklif sayıları, geciken projeler, tahsilat/alacak, hatırlatmalar, düşük stok).
- `GET /api/dashboard-init` artık `saha` rolüne de açık: yalnız atanmış/paylaşılmış randevu-proje ve ilgili müşteri adı/telefonu/adresi döner; **finans verisi (ödeme, gider, sabit gider, sözleşme tutarı, finans özeti) hiçbir zaman gitmez**. Tüm roller için yanıta `financeSummary` eklendi (saha: null).
- Randevular: yanıtta `customer_name`, `customer_phone`, `address/lat/lng`, `assigned_user_name` hazır gelir; `POST/PATCH` tür, atanan kişi, teklif/proje bağlantısı, adres alır; `GET /appointments?from=&to=&assigned_user_id=me&status=`, `GET /appointments/:id`. Atama yalnız kendi ekibine yapılabilir (ortak A, ortak B'nin ekibine atayamaz).
- Adres: teklif, müşteri (manuel), proje, randevu `POST/PATCH` uçlarında `address` (≤500 karakter), `lat`(-90..90), `lng`(-180..180); lat/lng birlikte gönderilir. Teklif kabul edilince proje adresi tekliften kopyalanır.
- Teklif gönderimi `POST /api/quotes/:offerId/send`: artık gerçek sonuç döner — `{sent, channel, channels:{whatsapp,email}, status, error, pdfUrl, whatsappUrl}`; tam başarısızlıkta **HTTP 502**, kısmi başarıda **207**, tamda 200. Gönderim durumu `quotes.last_send_status` (`gonderildi|kismen|basarisiz`) alanındadır ve teklif listesinde `quote.last_send_status` olarak görünür; teklifin `status` alanı gönderim sonucuna göre DEĞİŞMEZ. Eski `results` metin alanı korunur.
- Raporlar: `ev` (kişisel) giderler işletme net kârına dahil değildir. `GET /reports/summary` yeni alanlar: `businessExpenses, homeExpenses, expensesByScope, netProfit, netProfitInclHome`; yeni `GET /reports/profit?range=monthly|yearly`. Mevcut alanlar/`/reports/revenue` şekli aynı.
- Oturum: `GET /auth/me`, `POST /auth/refresh`, `POST /auth/logout-all`. Login yanıtı `{token, tokenType, expiresAt, expiresIn, user:{id,name,email,role}}`.
  Mobil istemci `client:"mobile"` (ya da `X-Client: mobile`) ile giriş yapınca jeton ömrü **30 gün** (`JWT_EXPIRES_IN_MOBILE`), web 7 gün (`JWT_EXPIRES_IN`).
  Uygulama her açılışta `/auth/refresh` ile jetonu yeniler (kayan oturum). Her istekte kullanıcının varlığı ve `token_version` kontrol edilir (10 sn bellek önbelleği):
  silinen kullanıcı ya da `logout-all` yapan kullanıcının tüm jetonları geçersiz olur; rol değişikliği de anında yansır.
- Push: `POST /api/push/device {token, platform}` / `DELETE /api/push/device` ile FCM token kaydı (`device_tokens`). Gönderim kancası `src/services/fcm.js` içinde **boş**; `push.notifyUser` / `notifyNewOffer` bu kancayı zaten çağırır.
- Arama/sayfalama (teklifler, müşteriler, projeler): `?q=`, `?limit=1..200`, `?offset=`. Parametre yoksa eski davranış (tüm kayıtlar). Yanıt gövdesi **her zaman düz dizi**; toplam kayıt sayısı `X-Total-Count` başlığındadır.

**Canlıya alırken**
1. `node src/migrate.js` (v15'i uygular) → ardından `pm2 restart xcontrol-api`. Mevcut oturumlar geçerli kalır.
2. Nginx'te `client_max_body_size 20m;` (yukarıdaki örneğe eklendi) — yoksa 1 MB üstü fotoğraf/belge yüklemeleri nginx'te 413 alır.
3. İsteğe bağlı `.env`: `JWT_EXPIRES_IN_MOBILE=30d` (varsayılan zaten 30d). `.env.example` dosyası eklendi (README bu dosyaya atıf yapıyordu ama pakette yoktu).
4. Web paneli: gönderim hatası artık HTTP 502 döner (panel `error` metnini gösterir); kısmi gönderim 207 döner ve panel yine "gönderildi" yazar — `channels` okunacak şekilde panel güncellenmelidir.
5. FCM henüz bağlı değil: bağlanırken `src/services/fcm.js` içindeki `sendToUsers` doldurulur (ek paket: `firebase-admin`).

**Test:** `test/` klasöründe `api_test.js` (75 kontrol), `api_test_v15.js` (v15, 174 kontrol) ve `api_test_v16.js` (v16 güvenlik, 211 kontrol) vardır. Sahte WhatsApp/SMTP sunucusunu testin kendisi açar; çalıştırma:
```bash
# boş test veritabanı + migrate + tohum kullanıcılar (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234)
node src/migrate.js && node test/seed.js "$PWD"
PORT=4100 WHATSAPP_API_BASE=http://localhost:4101 WHATSAPP_PHONE_NUMBER_ID=1 WHATSAPP_ACCESS_TOKEN=t \
  SMTP_HOST=localhost SMTP_PORT=4102 SMTP_SECURE=false MAIL_FROM=x@x.com node src/server.js &
node test/api_test_v15.js      # api_test.js, api_test_v15.js ve api_test_v16.js ayrı ayrı, her biri TEMİZ veritabanında çalıştırılmalıdır
# (v15 testindeki "saha: no money / tracking leakage" kontrolü rastgele UUID/zaman damgasında "333"/"777" geçerse arada bir (~5 çalıştırmada 1) yanlış alarm verir; yeniden çalıştırın)
```

---

## 14. Güvenlik sertleştirme (v16)

Bağımsız güvenlik denetiminin (`audit-security.md`) bulguları düzeltildi; ayrıntılı durum tablosu `audit-security-fixes.md` içindedir. Mevcut migrasyonlar değişmedi; yenilikler `src/schema_v16.sql` (idempotent, `node src/migrate.js` uygular). Mobil sözleşme (`mobile-api-contract.md`) v16'ya güncellendi.

**Başlıca değişiklikler:** teklif e-postası doğrulaması + nodemailer 10 (uzaktan çökertme kapatıldı) · paylaşımlı projede başkasının defterine kayıt yazılamaz · jeton iptali her istekte (10 sn önbellek) · push abonelik SSRF kapatıldı (yalnız https + bilinen push alan adları) · `/uploads` kimlik ister (10 dk imzalı bağlantı ya da Authorization başlığı) · belge yükleme allowlist + içerik doğrulaması + yetki önce · multer 2 · görev atama doğrulaması · `paid_amount` defter filtresi · kabul edilmiş teklif geri alınamaz · şifre değiştirme/sıfırlama uçları · hata/log sızıntıları kapatıldı · CORS/helmet/trust proxy ayarları ortam değişkenine bağlandı.

### Canlıya alma adımları (sırayla)

1. **Node 20'ye geç** (nodemailer 10 gereği): `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs && node -v`
2. Yeni sürümü yükle, bağımlılıkları **kilit dosyasından** kur (paket içinde `package-lock.json` vardır): `npm ci --omit=dev` (geliştirme makinesinde `npm ci`). Ardından `npm audit --omit=dev` → `found 0 vulnerabilities` olmalı.
3. `.env` dosyasını güncelle (aşağıdaki tablo). **En az:** `JWT_SECRET` (32+ karakter; değiştirmek tüm açık oturumları sonlandırır — kabul edilebilirse yapın), `CORS_ORIGINS`, `TRUST_PROXY`, `HOST=127.0.0.1`.
4. `node src/migrate.js` (v16'yı uygular: geçersiz eski e-postaları/fotoğraf bağlantılarını ve güvenilmeyen push aboneliklerini temizler, CHECK kısıtları ve dizinler ekler).
5. Nginx'e `X-Forwarded-For`/`X-Forwarded-Proto` başlıklarını ekle (bölüm 9'daki güncel örnek) → `sudo nginx -t && sudo systemctl reload nginx`.
6. `pm2 restart xcontrol-api --update-env` (veya ilk kez: `pm2 start src/server.js --name xcontrol-api --max-memory-restart 400M && pm2 save && pm2 startup`).
7. Doğrula: `curl -s https://api.controlx.com.tr/api/health`; `curl -sI https://api.controlx.com.tr/uploads/documents/x.pdf` → `401` olmalı (kimliksiz dosya erişimi kapalı); bir belge yükleyip listede dönen imzalı `file_url`'nin tarayıcıda açıldığını, 10 dk sonra `401` verdiğini kontrol et.
8. **Web paneli (v10) notu:** panel `file_url`/`image_url`/`pdfUrl` değerlerini API yanıtından olduğu gibi kullandığı sürece çalışmaya devam eder (artık imzalı); kullanıcı sayfayı 10 dakikadan uzun açık tutup eski bağlantıya tıklarsa `401` JSON görür — listeyi yenilemek yeterlidir. Paylaşılan projede "başkası adına ödeme/gider" seçimi artık yalnız proje sahibi/admin/muhasebe için etkilidir (işbirlikçinin kaydı kendi defterine düşer).

### Yeni / değişen ortam değişkenleri

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `CORS_ORIGINS` | (boş = tüm kökenler, eski davranış) | Virgüllü izinli kökenler: `https://panel.controlx.com.tr,https://controlx.com.tr`. **Üretimde mutlaka tanımlayın.** Mobil uygulama Origin göndermediği için etkilenmez |
| `TRUST_PROXY` | `1` | Önündeki güvenilir proxy sayısı: yalnız nginx/Apache → `1`; Cloudflare + nginx → `2`; proxy yok → `false`. Yanlış değer hız sınırını atlatılabilir/yanlış hale getirir |
| `HOST` | (tüm arayüzler) | `127.0.0.1` önerilir: API yalnız yerel proxy'den erişilir (4000 portu dışarı açık kalmaz) |
| `DB_SSL_REJECT_UNAUTHORIZED` | `false` (eski davranış) | `DATABASE_SSL=true` iken sunucu sertifikasını doğrula (`true`). Yönetilen DB için `true` + gerekirse `DB_SSL_CA=/yol/ca.pem` (verilince doğrulama varsayılan açılır). Aynı makinedeki yerel PostgreSQL için `DATABASE_SSL=false` kalır. **Not:** `NODE_ENV=production` iken `DATABASE_SSL` verilmezse TLS açılır (eski davranış) |
| `UPLOAD_SIGN_SECRET` | `JWT_SECRET`'ten türetilir | Dosya bağlantı imzası anahtarı (isteğe bağlı, ayrı tutmak için) |
| `UPLOAD_URL_TTL_SEC` | `600` | İmzalı dosya bağlantısı ömrü (30–86400 sn) |
| `JWT_SECRET_STRICT` | `false` | `true` → 32 karakterden kısa `JWT_SECRET` ile sunucu başlamaz |
| `AUTH_CACHE_TTL_MS` | `10000` | Kullanıcı durumu önbelleği (en çok 30000). Silme/rol/şifre değişikliği tek süreçte anında, çok süreçli (PM2 cluster) kurulumda en geç bu sürede yansır |
| `PASSWORD_MIN_LENGTH` | `6` | Yeni şifre alt sınırı (en az 6). **8 öneriyoruz** (mobil/panel formlarını da güncelledikten sonra) |
| `BCRYPT_ROUNDS` | `12` | Şifre özet maliyeti (10–14). Eski özetler girişte aynen geçerlidir |
| `PUSH_ENDPOINT_HOSTS` | (boş) | Ek izinli push alan adları (`push.ornek.com,*.ornek.net`) |
| `RATE_LIMIT_API_MAX` | `3000` | IP başına 15 dk genel API sınırı (`0` = kapalı) |

`.env.example` bu değişkenlerle güncellendi.

### Nginx / Apache notları
- **Nginx:** bölüm 9'daki örnek `X-Forwarded-For` ve `X-Forwarded-Proto` ekler; ek olarak `/uploads` için önbelleği kapatmayın (imzalı bağlantılar kısa ömürlüdür). `server_tokens off;` (nginx.conf) önerilir. Erişim logunda imza sorgu dizeleri (`?exp=…&sig=…`) 10 dk sonra işe yaramaz hale gelir; yine de `access_log`'u herkese açmayın.
- **Apache (reverse proxy kullanıyorsanız):** `ProxyPass / http://127.0.0.1:4000/`, `ProxyPassReverse`, `ProxyPreserveHost On`, `RequestHeader set X-Forwarded-Proto "https"`; `mod_proxy` `X-Forwarded-For`'u kendiliğinden ekler. `LimitRequestBody 20971520`, `ServerTokens Prod`, `ServerSignature Off`.
- Cloudflare önündeyse `TRUST_PROXY=2` ve (daha doğrusu) nginx'te `set_real_ip_from` (Cloudflare IP aralıkları) + `real_ip_header CF-Connecting-IP;` kullanın; aksi halde tüm kullanıcılar Cloudflare IP'si görünür ve hız sınırı yanlış çalışır.

### Güvenlik duvarı ve fail2ban (kısa özet)
```bash
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow 22/tcp          # mümkünse: sudo ufw allow from <ofis_ip> to any port 22
sudo ufw allow 80,443/tcp
sudo ufw deny 4000/tcp && sudo ufw deny 5432/tcp     # API ve PostgreSQL dışarıya kapalı (HOST=127.0.0.1 ile birlikte)
sudo ufw enable

sudo apt install -y fail2ban
printf '[sshd]\nenabled = true\nmaxretry = 4\nbantime = 1h\n' | sudo tee /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban
```
PostgreSQL kullanıcısı SUPERUSER olmamalı (`ALTER USER xcontrol_user NOSUPERUSER NOCREATEDB NOCREATEROLE;`). Şifreli otomatik yedek (DB + `uploads/`) ve aylık geri yükleme denemesi önerilir. PM2 log döndürme: `pm2 install pm2-logrotate`.

### Bağımlılıklar
`nodemailer@10.6.1` (adres ayrıştırıcı DoS/SSRF GHSA'ları yamalı; Node 20+), `multer@2.5.0`, `minimatch` geliştirme bağımlılığı `overrides` ile yükseltildi → `npm audit` **0 açık**. Periyodik olarak `npm audit` çalıştırın (CI/Dependabot önerilir). Express 4 kullanımı sürüyor (5'e geçiş ayrı bir iş kalemi).

---

## 15. Asistan altyapısı (v17)

Sekreter+Müdür asistanının (sektörden bağımsız, ücretsiz, kural tabanlı) ALTYAPISI: iş kuyruğu + ayrı worker süreci, bildirim kutusu/FCM, kuruluş
ayarları (marka, sektör sözlüğü, listeler), sektör şablonları, özellik bayrakları, `/api/v1` takma yolu, `Idempotency-Key`. **Mevcut migrasyonlar değişmedi**;
yenilikler `src/schema_v17.sql` (idempotent) ve `src/assistant/` içindedir. Yeni uç sözleşmesi: `mobile-api-contract.md` §16 (birleşik sözleşme).

**Şema (v17):** `organizations` (varsayılan tek kuruluş; kullanıcı varsa "X Control Yapı" + `demir_dograma` profili, boş kurulumda "İşletmem" + `genel`), ana tablolara
**NULLABLE** `org_id` + backfill + indeks + "yeni satıra varsayılan kuruluşu ata" tetikleyicisi (NOT NULL ve RLS yok — Faz 4; mevcut `owner_id` izolasyonu aynen çalışır),
`org_counters`, `org_settings`, `sector_templates` (genel, tadilat_insaat, demir_dograma, klima_teknik_servis, kuafor_berber, nakliye, temizlik), `jobs`, `notification_outbox`,
`notification_prefs`, `worker_heartbeats`, `audit_log`, `idempotency_keys`, `feature_flags`; `device_tokens`'a `disabled_at/last_seen_at/os_version/locale`.

**Modüller (`src/assistant/`, imzalar sabit):** `clock.js` (`now, istanbulDay, istanbulDateStr, setFake, reset`), `queue.js` (`enqueue, registerHandler, runDue`), `notify.js` (`notifyUser`),
`sender.js` (outbox → FCM HTTP v1), `audit.js` (`logAction`), `handlers/*.js` (her biri `module.exports.register = (registerHandler) => {}`; otomatik yüklenir).
`src/middleware/idempotency.js`. Yeni işleyici eklemek = `handlers/` altına dosya koymak; `briefing.morning` ve `closure.evening` için yer tutucu işleyiciler vardır, aynı adı kaydeden gerçek işleyici onları ezer.

**Canlıya alma (sırayla)**
1. `node src/migrate.js` (v17'yi uygular; mevcut verilerin `org_id`'si varsayılan kuruluşa yazılır).
2. API ve worker artık AYRI PM2 uygulamalarıdır: `pm2 delete xcontrol-api && pm2 start ecosystem.config.js && pm2 save` (`xcontrol-api` + `xcontrol-worker`). Worker tek komutla da çalışır: `node src/worker.js`.
3. İzleme: `GET /api/health/worker` (herkese açık; ok → 200, worker durmuşsa 503) adresini UptimeRobot/benzeri bir ücretsiz izleyiciye ekleyin.
4. İsteğe bağlı: FCM (aşağıda). Anahtar yoksa hiçbir şey bozulmaz: bildirimler `beklemede` kalır ve uygulama içi bildirim kutusundan okunur.

**FCM anahtarı (opsiyonel, ücretsiz):** Firebase Console → Proje ayarları → Hizmet hesapları → "Yeni özel anahtar oluştur" → JSON'u sunucuya koyun (`chmod 600`), `.env`:
`FCM_SERVICE_ACCOUNT_FILE=/etc/xcontrol/fcm.json` (ya da `FCM_SERVICE_ACCOUNT_JSON`) ve worker'ı yeniden başlatın. iOS için APNs .p8 anahtarı Firebase'e yüklenir. Ek paket gerekmez.

**Ortam değişkenleri (hepsi opsiyonel)**
| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `WORKER_TICK_MS` | 30000 | worker tick aralığı |
| `WORKER_BATCH` | 20 | tick başına en çok iş |
| `JOB_LOCK_TIMEOUT_MS` / `JOB_TIMEOUT_MS` | 300000 / 60000 | çöken worker'ın kilidi / tek iş zaman aşımı |
| `PLAN_EXPIRES_AFTER_MS` | 12600000 (3,5 sa) | brifing/kapanış işinin geçerlilik süresi (sonrası "kaçırıldı") |
| `WORKER_STALE_SECONDS` | 120 | `/health/worker` bu süreden eski kalp atışını `stale` (503) sayar |
| `FCM_SERVICE_ACCOUNT_FILE` / `_JSON`, `FCM_PROJECT_ID` | yok | FCM HTTP v1 (yoksa devre dışı) |
| `APP_MIN_VERSION`, `APP_LATEST_VERSION`, `APP_STORE_URL_ANDROID/IOS` | yok | `/config` → `server.*` (zorunlu güncelleme bilgisi) |
| `MAINTENANCE_MODE=true`, `MAINTENANCE_MESSAGE` | kapalı | `/config` → `server.maintenance` |
| `ASSISTANT_FAKE_NOW` | yok | YALNIZ test: süreç saatini sabitler (`NODE_ENV=production`'da yok sayılır) |

**Test:** `test/api_test_v17.js` (211 kontrol: çift/eşzamanlı worker, catch-up, dedupe, sahte saat, outbox idempotency, FCM dry-run + sahte FCM, bildirim kutusu, config yetkileri, ortak izolasyonu, sektör şablonu, Idempotency-Key, `/api/v1`).
Temiz veritabanı + migrate + seed sonrası sunucu **4101**'de çalışırken: `PORT=4101 node src/server.js & node test/api_test_v17.js` (worker süreçlerini test kendisi başlatır; sunucuda `FCM_*` tanımsız olmalı).

---

## Fatura/KDV/vergi takvimi (v18)

Fatura **kesmez**; gelen/giden faturayı takip eder, KDV'yi kodla (tamsayı kuruş, yarım yukarı) hesaplar, muhasebeciye CSV/XLSX aktarır. Mobil uçlar: `mobile-api-contract.md` §17.

- Şema: `src/schema_v18.sql` (idempotent; `npm run migrate`). Yeni kuruluşa oran/takvim/tatil/şablon tohumu tetikleyiciyle eklenir.
- **Oranlar ve tarihler koda gömülü değildir.** KDV oranları, tevkifat türleri, vergi takvimi kalemleri ve resmî tatiller veri olarak tohumlanır, `verified=false` (doğrulanmadı) doğar; kullanıcı/mali müşavir düzenler ve doğrular. Her uçta "mali müşavire teyit" bayrağı döner. Hukuki/mali tavsiye değildir.
- Zamanlı hatırlatma: `tax.plan` / `tax.remind` / `receivable.remind` işleyicileri (`src/assistant/handlers/tax.js`) A1 kuyruğunu kullanır; `worker.js` değişmez. Plan, takvim uçları çağrılınca ya da `reminderPlanner.bootstrap()` ile başlar ve her gün 03:45'te kendini yeniler.
- XLSX: bağımlılıksız küçük yazıcı (`src/assistant/tax/xlsxWriter.js`) — yeni paket/`npm audit` yüzeyi yok; CSV de her zaman desteklenir.
- Test: `node test/api_test_v18.js` (temiz DB + seed + sunucu :4102; `TEST_PORT`). XLSX doğrulaması için python3+openpyxl varsa kullanılır.

## Komut çubuğu ve yazışma içe aktarma (v19)

Kural tabanlı (LLM'siz, ücretsiz) Türkçe komut çubuğu ve WhatsApp yazışması içe aktarma. Uç sözleşmesi: `mobile-api-contract.md` §18.

- Şema: `src/schema_v19.sql` (idempotent; `npm run migrate`): `ai_actions`, `conversations`, `conversation_messages`, `conversation_imports`, `ai_notes`, `ai_suggestions`, `consents`; müşteri silinince yazışma da silinir (tetikleyici).
- Komut çubuğu: `src/assistant/command/` (ayrıştırıcı, sahiplik/rol kapsamı, okuma yanıtları, kart üreticileri). Yazma komutları asla doğrudan uygulanmaz: `ai_actions` kartı -> onay -> mevcut REST iş mantığı (`src/assistant/exec.js`, kısa ömürlü iç JWT). Silme, rol değişikliği ve mesaj gönderme komutları yasaktır.
- İçe aktarma: `src/assistant/importer/` (WhatsApp .txt/.zip ayrıştırıcı, güvenli zip okuyucu, öneri çıkarıcı, saklama/imha). Veri yalnız kendi sunucunuzda işlenir; yükleme öncesi aydınlatma/rıza zorunludur.
- Testler (temiz DB + seed + sunucu :4103, `ASSISTANT_FAKE_NOW="2026-11-20T10:00:00+03:00"` **ve `IMPORT_RATE_MAX=500`** — test tek kullanıcıyla 20'den çok içe aktarma yapar, üretim varsayılanı 429 verir): `node test/api_test_v19.js`; birim/doğruluk: `node test/golden_commands.js` (komut, >=90% hedef), `node test/unit_importer_v19.js` (ayrıştırıcı).

## Müdür, brifing, kapanış (v20)

Sekreter+Müdür asistanının içeriği (ücretsiz, kural tabanlı, LLM'siz; para kuruş tamsayısı, gün İstanbul takvimi, metinler `org_settings` sektör sözlüğünden). Uç sözleşmesi: `mobile-api-contract.md` §19.

- Şema: `src/schema_v20.sql` (idempotent; `npm run migrate`): `briefings`, `insights`, `insight_rule_config`, `insight_runs`, `daily_logs`, `followups`; `reminders`a tekrar/erteleme/kaynak sütunları; `projects.cost_confirmed_at`, `projects.stage_changed_at`, `offers.status_changed_at` (tetikleyiciyle). Yeni tablolar `org_id` + `set_default_org()` taşır; eski migrasyonlar değişmedi.
- `src/assistant/facts/`: kapsam farkındalıklı (rol/ortak) gerçek sorgular (gün gündemi, açık takipler, alacak yaşlandırma, ay P&L [kişisel `scope='ev'` hariç], teklif hunisi, doluluk, düşük stok). `src/assistant/manager/`: M1–M13 kural kataloğu (kural başına `collect` + saf `evaluate`), Türkçe şablonlar, insight yaşam döngüsü (dedupe, ertele/kapat/geri bildirim, sayısal "Neden?" dayanağı), önerilen aksiyon metadatası (hatırlatma, ara, WhatsApp şablon kodu, randevu ekle).
- **Bağımlı kurallar:** M7 (`invoices`) ve M8 (`vat_periods`, yalnız işletme kapsamı) v18 tablolarını çalışma anında yoklar; v18 kuruluysa (birleşik sürümde her zaman) `aktif`, tablo/sütun yoksa `bagimli` görünür ve çalışmaz. Birleşik sürümde M7/M8 gerçek tablolarla `api_test_v21.js` bölüm 9'da sınanır. Kural eşikleri `GET|PUT /api/assistant/insight-rules` (admin) ile ayarlanır; `holidays_tr` varsa brifing resmî tatili tanır.
- İşleyiciler (`src/assistant/handlers/`): `briefing.morning|weekly|monthly`, `closure.evening` + tek `closure.nudge` (20:30), `reminder.fire` (hatırlatma + randevu öncesi akşam 18:00 / 1 saat önce), `plan_day` (A1 planlayıcısını sarar, haftalık/aylık/randevu işlerini ekler). A1'in yer tutucu işleyicilerini ezer; hepsi idempotent (bildirim `dedupeKey`i kullanıcıyı içerir). Varsayılan saatler A1'inkiyle aynıdır (07:30 / 18:30; kullanıcı tercihiyle değişir).
- Mevcut `/api/reminders` sözleşmesi aynen çalışır; `recurrence` opsiyonel eklenir. Kapanış yanıtları asistanın kendi alanına (randevu durumu, takip, maliyet onayı, yarın hatırlatması) doğrudan, başka alanlara (tahsilat/gider, aşama, teklif durumu) yalnız `closure_proposals` olarak (onayla uygulanır) yazar.
- Testler (temiz DB + seed): `node test/unit_v20.js` (veritabansız, 162 kontrol); `node test/api_test_v20.js` — sunucu `TEST_PORT`'ta (varsayılan 4104) **`ASSISTANT_FAKE_NOW=2026-11-25T07:00:00Z`** ile çalışmalı (birleşik ağaçta 295 kontrol — 296'daki bir kontrol yalnız `invoices`/`vat_periods` tabloları YOKKEN çalışır: her M kuralı tetiklenen/tetiklenmeyen, kuruş doğruluğu, sahte saatle sabah/akşam/20:30 tek hatırlatma/Pazar/tatil, dedupe, rol kapsamı ortak A≠B/saha/personel, brifing boş/dolu, kapanış akışı, hatırlatma erteleme/tekrar, işleyici idempotency).

## 16. Birleşik sürüm (v20) — doğrulama kılavuzu

Kod tabanı v17 (altyapı) + v18 (fatura/KDV/vergi) + v19 (komut çubuğu/içe aktarma) + v20 (müdür/brifing/kapanış) parçalarının **tek, temiz birleşimidir**. Tek mobil sözleşme: `mobile-api-contract.md` (v20). Canlıya alma: `SUNUCU-GUNCELLEME.md`. Sonuç ve riskler: `backend-final-rapor.md`.

**Test kümeleri** — her biri **TEMİZ veritabanında** (`DROP/CREATE DATABASE` → `node src/migrate.js` → seed: admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / `pass1234`) ve ayrı sunucu sürecinde çalıştırılır:

| Küme | Kontrol | Sunucu |
|---|---|---|
| `api_test.js` | 75 | `PORT=4100` + sahte WhatsApp/SMTP ortam değişkenleri (bölüm 13) |
| `api_test_v15.js` | 174 | aynı |
| `api_test_v16.js` | 211 | aynı |
| `api_test_v17.js` | 211 | `PORT=4101` |
| `api_test_v18.js` | 673 | `PORT=4102` |
| `api_test_v19.js` | 311 | `PORT=4103 ASSISTANT_FAKE_NOW=2026-11-20T10:00:00+03:00 IMPORT_RATE_MAX=500` |
| `api_test_v20.js` | 295 | `PORT=4104 ASSISTANT_FAKE_NOW=2026-11-25T07:00:00Z` |
| `api_test_v21.js` | 189 | `PORT=4105 ASSISTANT_FAKE_NOW=2026-11-20T10:00:00+03:00` (IMPORT_RATE_MAX tanımsız; hız sınırı bloğu kendi sunucusunu açar) |
| `unit_importer_v19.js`, `unit_v20.js` | 88 / 162 | sunucusuz |
| `golden_commands.js` | 279 komut (%100) | sunucusuz |
| `smoke_e2e.js` | 23 | sunucu + worker'ı kendisi başlatır (`TEST_PORT`, varsayılan 4106) |

`api_test_v21.js` (birleşik sürüm): tüm yeni uçlarda oturumsuz 401 (`/api` ve `/api/v1`), personel/saha finans kapalı, ortak A↔B kimlikle erişim (IDOR) taraması, `owner_id/org_id/user_id` gövdeden yükseltme (mass-assignment), `ai_actions` onay/ret/geri alma/düzenleme başkasına uygulanamaz, fatura dosyası ve ZIP saldırıları, `Idempotency-Key` kullanıcılar arası sızıntı, içe aktarma hız sınırı, M7/M8 gerçek tablo dikişi.

## Özet — Sırada Ne Var?

1. ✅ Veritabanı şeması, API, PDF/WhatsApp/e-posta servisleri hazır (bu klasör)
2. ⬜ VPS kiralama + yukarıdaki adımların uygulanması
3. ⬜ Meta Business hesabı başvurusu (1-2 gün onay süresi olabilir)
4. ⬜ Admin panelin bu API'ye bağlanması (fetch entegrasyonu)
5. ⬜ Public sitenin teklif formunun bu API'ye bağlanması
6. ⬜ Domain DNS ayarları ve SSL kurulumu
