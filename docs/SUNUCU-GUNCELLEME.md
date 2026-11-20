# X Control Yapı — Sunucu Güncelleme Kılavuzu (backend v20, birleşik sürüm)

Bu kılavuz **bilgisayar başında**, adım adım uygulanır. Varsayımlar:

| Öğe | Değer |
|---|---|
| Sunucu (VPS) | `104.247.164.177`, kullanıcı `dogruticaret` |
| Uygulama klasörü | `/var/www/controlx/backend` |
| PM2 süreçleri | `xcontrol-api` (port 4000) · `xcontrol-panel-v2` (port 4001, **dokunulmaz**) |
| Ters proxy | Apache (`ProxyPass`) |
| Yeni paket | `backend.zip` (içinde üst klasör `backend/`) |

Bu güncelleme **yeni bir süreç ekler**: `xcontrol-worker` (bildirim/brifing/hatırlatma işleyicisi). API ve worker ayrı PM2 uygulamalarıdır.

> **Süre:** yaklaşık 30–45 dk. Kesinti: yalnız adım 7–8 arası (1–2 dk). Sabah erken ya da akşam geç saatte yapın.
> **Altın kural:** Bir adım başarısız olursa **sonrakine geçmeyin**; adımın altındaki "Başarısız olursa" bölümüne bakın. Hâlâ çözülmezse **Bölüm 12 (Geri alma)**.

---

## 0. Başlamadan önce (kendi bilgisayarınızda)

1. `backend.zip` dosyasını sunucuya kopyalayın:
   ```bash
   scp backend.zip dogruticaret@104.247.164.177:/tmp/backend.zip
   ```
2. Sunucuya bağlanın:
   ```bash
   ssh dogruticaret@104.247.164.177
   ```
3. Hazır olun: admin e-posta/şifreniz, mevcut `.env` içeriği (adım 1'de yedeklenecek).

**Başarısız olursa:** `scp`/`ssh` hata verirse anahtar/şifre ve ağ erişimini kontrol edin; sunucuya girilemiyorsa sağlayıcının konsolunu kullanın. Hiçbir şey değişmedi, devam etmeyin.

---

## 1. Mevcut durumu kaydedin (salt okunur)

```bash
cd /var/www/controlx/backend
node -v                      # 20 veya üstü olmalı (adım 4)
pm2 ls                       # xcontrol-api ve xcontrol-panel-v2 "online" olmalı
cat package.json | grep '"version"'
DBURL=$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)
psql "$DBURL" -c "SELECT name FROM schema_migrations ORDER BY applied_at DESC LIMIT 3;"
curl -s http://127.0.0.1:4000/api/health
```
Çıktıyı not alın (hangi şema sürümünde olduğunuzu gösterir; örn. `schema_v16.sql`).

**Başarısız olursa:** `schema_migrations` tablosu yok diyorsa kurulum eski/elle yapılmış demektir; sorun değil — `migrate.js` bunu algılar (adım 8). `psql` bağlanamıyorsa `.env` içindeki `DATABASE_URL`'i kontrol edin.

---

## 2. YEDEK (atlamayın)

```bash
mkdir -p ~/yedek && cd /var/www/controlx/backend
STAMP=$(date +%F_%H%M)
DBURL=$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)

# 2a) Veritabanı (özel biçim, geri yüklemeye uygun)
pg_dump "$DBURL" -Fc -f ~/yedek/xcontrol_db_$STAMP.dump
pg_restore -l ~/yedek/xcontrol_db_$STAMP.dump | head -5     # içerik okunabiliyor mu?
ls -lh ~/yedek/xcontrol_db_$STAMP.dump                       # boyut 0 olmamalı

# 2b) .env ve yüklenen dosyalar
cp .env ~/yedek/env_$STAMP.bak && chmod 600 ~/yedek/env_$STAMP.bak
tar czf ~/yedek/uploads_$STAMP.tar.gz uploads

# 2c) Eski uygulama kodu (node_modules dahil: hızlı kod geri alma için)
cd /var/www/controlx && tar czf ~/yedek/backend_eski_$STAMP.tar.gz backend
ls -lh ~/yedek/
```
Mümkünse `~/yedek` içindeki dosyaları kendi bilgisayarınıza da çekin: `scp dogruticaret@104.247.164.177:'~/yedek/*_'$STAMP'*' .`

**Başarısız olursa:**
- `pg_dump: error: connection ... failed` → `.env` içindeki `DATABASE_URL` yanlış ya da PostgreSQL kapalı (`sudo systemctl status postgresql`).
- `pg_dump` sürüm uyuşmazlığı hatası → sunucudaki `pg_dump` sürümü veritabanı sunucusundan eskiyse `sudo apt install postgresql-client-16` (ya da sunucu sürümüne eşit).
- Disk dolu (`No space left`) → `df -h`; eski yedek/log silin. **Yedek alınmadan devam etmeyin.**

---

## 3. Paketi açın (henüz canlı klasöre dokunmadan)

```bash
rm -rf /tmp/backend_yeni && mkdir /tmp/backend_yeni
cd /tmp/backend_yeni && unzip -q /tmp/backend.zip
ls /tmp/backend_yeni/backend              # package.json, src, test, ecosystem.config.js, README.md, .env.example
cat /tmp/backend_yeni/backend/package.json | grep '"version"'     # 1.20.0
ls /tmp/backend_yeni/backend/src/schema_v2*.sql                    # schema_v20.sql görünmeli
```

**Başarısız olursa:** `unzip: command not found` → `sudo apt install -y unzip`. Sürüm 1.20.0 değilse yanlış zip yüklenmiştir; adım 0'ı tekrarlayın.

---

## 4. Node 20+ kontrolü

```bash
node -v        # v20.x, v22.x ... kabul; v18 ve altı KABUL EDİLMEZ (package.json engines >=20)
```
Sürüm eskiyse (örnek: NodeSource ile Node 20):
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v
```
> Node'u değiştirdiyseniz PM2'yi de yeni Node ile yeniden başlatmanız gerekir (adım 9'daki `--update-env`; gerekirse `pm2 update`).
> `xcontrol-panel-v2` aynı Node'u kullanıyorsa onu da bir kez `pm2 restart xcontrol-panel-v2` ile yenileyin ve açıldığını doğrulayın.

**Başarısız olursa:** Kurulum betiği internete çıkamıyorsa (proxy/DNS) `nvm` ile kullanıcı bazlı kurun: `nvm install 20 && nvm alias default 20`. PM2 hangi Node'u kullanıyorsa o `node -v` çıktısını verir (`pm2 ls` → `pm2 describe xcontrol-api | grep -i interpreter`).

---

## 5. Kodu canlı klasöre kopyalayın

`.env`, `uploads/` ve `node_modules/` korunur. `src/` **birebir eşitlenir** (eski dosyalar silinir; `src/assistant/handlers/` klasörü otomatik yüklendiği için artık dosya kalmamalıdır).

```bash
cd /var/www/controlx/backend
rsync -a --delete /tmp/backend_yeni/backend/src/  ./src/
rsync -a --delete /tmp/backend_yeni/backend/test/ ./test/
cp /tmp/backend_yeni/backend/package.json /tmp/backend_yeni/backend/package-lock.json \
   /tmp/backend_yeni/backend/ecosystem.config.js /tmp/backend_yeni/backend/README.md \
   /tmp/backend_yeni/backend/.env.example ./
ls src/schema_v20.sql src/worker.js ecosystem.config.js
ls -la .env uploads | head -3           # .env ve uploads hâlâ yerinde olmalı
```

**Başarısız olursa:** `rsync: command not found` → `sudo apt install -y rsync`. `Permission denied` → klasörün sahibi `dogruticaret` olmalı: `ls -ld /var/www/controlx/backend`; değilse `sudo chown -R dogruticaret: /var/www/controlx/backend`.

---

## 6. Bağımlılıkları kurun

```bash
cd /var/www/controlx/backend
npm ci --omit=dev
npm audit --omit=dev        # "found 0 vulnerabilities" bekleniyor
npm ls --omit=dev --depth=0 | head -20
```
`npm ci` `node_modules`'u silip kilit dosyasına göre sıfırdan kurar (sürümler sabit). Yeni bağımlılık eklenmedi; `form-data` artık `package.json`'da açıkça yazılı.

**Başarısız olursa:** `EACCES` → klasör sahipliği (adım 5). `ENOTFOUND registry.npmjs.org` → sunucunun internet/DNS erişimini kontrol edin (`curl -I https://registry.npmjs.org`). `npm ci can only install with an existing package-lock.json` → `package-lock.json` kopyalanmamış; adım 5'i tekrarlayın. `npm audit` açık bildirirse **durun**, bana/geliştiriciye çıktıyı gönderin (kilit dosyası 0 açıkla teslim edildi; fark, kopyalama hatasını gösterir).

---

## 7. `.env` dosyasını güncelleyin

```bash
cd /var/www/controlx/backend
nano .env          # kaydet: Ctrl+O, Enter; çık: Ctrl+X
chmod 600 .env
```
Mevcut satırlarınızı koruyun; aşağıdakileri **ekleyin/güncelleyin**. Tüm örnekler `.env.example` dosyasındadır (`diff .env .env.example` ile de karşılaştırabilirsiniz).

### 7.1 Zorunlu / önemli

| Değişken | Açıklama | Örnek |
|---|---|---|
| `NODE_ENV` | `production` olmalı (sahte saat gibi test özellikleri üretimde kapanır) | `NODE_ENV=production` |
| `PORT` | API portu (Apache buraya yönlenir) | `PORT=4000` |
| `HOST` | **Yalnız yerel Apache erişsin**: API dışarıdan doğrudan erişilemez. Boş bırakırsanız tüm arayüzlerde dinler (güvensiz) | `HOST=127.0.0.1` |
| `TRUST_PROXY` | Önünüzdeki güvenilir proxy **sayısı**. Yalnız Apache → `1`. Cloudflare + Apache → `2`. Yanlış değer hız sınırını/IP kaydını etkisizleştirir | `TRUST_PROXY=1` |
| `CORS_ORIGINS` | Tarayıcıdan API'ye istek atan **tüm** kökenler (virgüllü, sonda `/` yok): web paneli + teklif formu olan üç site (www dahil). **Eksik köken = o sitenin teklif formu sessizce çalışmaz.** Mobil uygulama CORS kullanmaz | `CORS_ORIGINS=https://panel.controlx.com.tr,https://controlx.com.tr,https://www.controlx.com.tr,https://x-metal.tr,https://www.x-metal.tr,https://nicebodrum.com,https://www.nicebodrum.com` |
| `JWT_SECRET` | Oturum imza anahtarı, **en az 32 karakter**. Mevcut anahtar kısa/zayıfsa yenileyin: `openssl rand -hex 32`. **Değişince herkes (panel + mobil) bir kez yeniden giriş yapar.** 16 karakterden kısa ise sunucu hiç başlamaz | `JWT_SECRET=<64 karakterlik rastgele>` |
| `JWT_SECRET_STRICT` | `true` ise 32 karakterden kısa anahtarla sunucu **başlamaz** (güvenli) | `JWT_SECRET_STRICT=true` |
| `DATABASE_URL` | Mevcut değer kalır | `postgresql://xcontrol_user:SIFRE@localhost:5432/xcontrol_db` |
| `DATABASE_SSL` | PostgreSQL aynı sunucudaysa `false`; uzak/yönetilen DB'de `true` | `DATABASE_SSL=false` |
| `DB_SSL_REJECT_UNAUTHORIZED` | `DATABASE_SSL=true` iken sunucu sertifikasını doğrula (`true` önerilir; kendinden imzalıysa CA verin) | `DB_SSL_REJECT_UNAUTHORIZED=true` |
| `DB_SSL_CA` | Özel CA dosyası yolu (verilirse doğrulama varsayılan açılır) | `DB_SSL_CA=/etc/ssl/db-ca.pem` |
| `APP_URL` | API'nin dışarıdan görünen adresi (dosya bağlantıları ve e-posta/WhatsApp linkleri bundan üretilir) | `APP_URL=https://api.controlx.com.tr` |
| `SITE_URL` | Ana site adresi | `SITE_URL=https://controlx.com.tr` |
| `UPLOAD_DIR` | Yüklenen dosyalar klasörü (mevcut `./uploads` kalsın) | `UPLOAD_DIR=./uploads` |

### 7.2 İsteğe bağlı (boş bırakılabilir)

| Değişken | Açıklama | Örnek |
|---|---|---|
| `FCM_SERVICE_ACCOUNT_FILE` | Firebase servis hesabı JSON dosyası (mobil anlık bildirim). **Yoksa FCM kapalıdır**: bildirimler uygulama içi "bildirim kutusunda" görünür, hiçbir şey bozulmaz. Dosyayı repo dışında tutun, `chmod 600` | `FCM_SERVICE_ACCOUNT_FILE=/etc/xcontrol/fcm.json` |
| `FCM_SERVICE_ACCOUNT_JSON` | Alternatif: ham JSON ya da base64 (dosya yerine) | — |
| `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN`, `ADMIN_WHATSAPP_NUMBER` | Meta WhatsApp Cloud API ile **otomatik** gönderim ve "yeni teklif" bildirimi. Boşsa otomatik gönderim yok; uygulama `wa.me` bağlantısıyla kullanıcının kendi WhatsApp'ından göndermeyi önerir. *(Not: `WHATSAPP_MODE` diye bir ayar kodda yoktur; WhatsApp davranışı yalnız bu üç değişkenle belirlenir. `WHATSAPP_API_BASE` yalnız testler içindir — üretimde TANIMLAMAYIN.)* | `ADMIN_WHATSAPP_NUMBER=905xxxxxxxxx` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM`, `MAIL_TO_ADMIN` | E-posta (teklif gönderimi, yeni teklif bildirimi) | `SMTP_HOST=smtp.example.com` `SMTP_PORT=587` |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` | Web paneli tarayıcı bildirimleri (`npx web-push generate-vapid-keys`) | — |
| `APP_MIN_VERSION`, `APP_LATEST_VERSION`, `APP_STORE_URL_ANDROID`, `APP_STORE_URL_IOS` | Mobil uygulama "zorunlu güncelleme" bilgisi (`GET /api/config`) | `APP_MIN_VERSION=1.0.0` |
| `MAINTENANCE_MODE` | `true` → mobil uygulamada bakım afişi | `MAINTENANCE_MODE=false` |
| `RATE_LIMIT_API_MAX` | IP başına 15 dk genel istek sınırı (varsayılan 3000, `0` = kapalı) | `RATE_LIMIT_API_MAX=3000` |
| `IMPORT_MAX_UPLOAD_MB` / `IMPORT_RATE_MAX` | WhatsApp yazışma içe aktarma: azami dosya (25 MB) / kullanıcı başına 15 dk'da en çok içe aktarma (20) | `IMPORT_RATE_MAX=20` |
| `IMPORT_RETENTION_DAYS` / `IMPORT_RAW_TEXT_DAYS` / `ASSISTANT_RAW_TEXT_DAYS` | KVKK saklama: yazışma (730 gün), ham mesaj metni (180), komut ham metni (30) | varsayılanlar önerilir |
| `ASSISTANT_UNDO_WINDOW_SEC` | Komut çubuğu "geri al" penceresi (600 sn) | `600` |
| `WORKER_TICK_MS`, `WORKER_BATCH`, `WORKER_STALE_SECONDS` | Worker tur süresi (30 sn), tur başına iş (20), `/api/health/worker` "ölü" eşiği (120 sn) | varsayılanlar |
| `COMPANY_NAME`, `COMPANY_PHONE`, `COMPANY_IBAN_INFO` | WhatsApp mesaj şablonlarındaki `{firma_adi}`, `{telefon}`, `{iban_unvan}` değişkenleri | `COMPANY_NAME="X Control Yapı"` |
| `UPLOAD_SIGN_SECRET`, `UPLOAD_URL_TTL_SEC`, `AUTH_CACHE_TTL_MS`, `PASSWORD_MIN_LENGTH`, `BCRYPT_ROUNDS`, `PUSH_ENDPOINT_HOSTS` | v16 sertleştirme ayarları (varsayılanlar güvenlidir; `PASSWORD_MIN_LENGTH=8` önerilir) | — |

> **Üretimde ASLA tanımlamayın:** `ASSISTANT_FAKE_NOW`, `WHATSAPP_API_BASE`, `FCM_API_BASE`.

Doğrulama (şifreleri ekrana basmadan, yalnız değişken adlarını listeler):
```bash
grep -E '^[A-Z_]+=' .env | cut -d= -f1 | sort
grep -E '^(NODE_ENV|HOST|TRUST_PROXY|PORT)=' .env
grep -c '^JWT_SECRET=.\{32,\}' .env        # 1 çıkmalı
```

**Başarısız olursa:** `.env`'i bozduysanız yedekten dönün: `cp ~/yedek/env_$STAMP.bak /var/www/controlx/backend/.env` (adım 2'deki `STAMP`; değişkeni kaybettiyseniz `ls ~/yedek`). `.env`'de değer içinde boşluk/özel karakter varsa tırnak içine alın: `MAIL_FROM="X Control Yapı <info@controlx.com.tr>"`.

---

## 8. Veritabanı güncellemesi (migrasyon)

**Önce API'yi durdurun** (eski kod yeni şemayla yazmasın diye 1–2 dk'lık kesinti; yedek zaten alındı):
```bash
pm2 stop xcontrol-api
cd /var/www/controlx/backend
node src/migrate.js
echo "çıkış kodu: $?"
```
**Beklenen çıktı** (v16'dan geliyorsanız):
```
Uygulanıyor: schema_v17.sql
✔ schema_v17.sql
Uygulanıyor: schema_v18.sql
✔ schema_v18.sql
Uygulanıyor: schema_v19.sql
✔ schema_v19.sql
Uygulanıyor: schema_v20.sql
✔ schema_v20.sql
✔ Şema güncel.
çıkış kodu: 0
```
(v14/v15'ten geliyorsanız `schema_v15`/`schema_v16` satırları da görünür. `Mevcut kurulum algılandı — v11'e kadar…` mesajı yalnız `schema_migrations` tablosu hiç yoksa çıkar; sonraki dosyalar idempotent olduğu için güvenlidir.) Admin kullanıcı zaten olduğundan "Henüz admin kullanıcı yok" satırı **çıkmamalı**.

İkinci kez çalıştırınca değişiklik olmaz (kontrol):
```bash
node src/migrate.js        # beklenen: yalnız "✔ Şema güncel." ve çıkış kodu 0
psql "$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)" -c "SELECT name FROM schema_migrations ORDER BY applied_at DESC LIMIT 5;"
```
Her dosya kendi işleminde (transaction) çalışır: bir dosya hata verirse **o dosyanın değişiklikleri geri sarılır** ve kayıt tutulmaz.

**Başarısız olursa:**
- `Migration hatası: schema_vNN.sql uygulanamadı: <neden>` → o dosya geri sarıldı, veritabanı bir önceki tutarlı durumda. Mesajı kaydedin. Yaygın nedenler: yetki (`permission denied` → DB kullanıcısının tablo sahibi olması gerekir; `GRANT`/sahiplik), disk dolu, eşzamanlı başka bağlantı kilidi (`pm2 ls` ile başka süreç `migrate` çalıştırmıyor mu?). Nedeni düzeltip `node src/migrate.js`'i yeniden çalıştırın (kaldığı yerden devam eder).
- Düzeltemiyorsanız: API'yi **eski kodla** açın → Bölüm 12-A.
- `ECONNREFUSED`/`password authentication failed` → `DATABASE_URL`.
- **Bu adım başarısızken yeni kodu başlatmayın.**

---

## 9. Uygulamayı başlatın (API + worker)

```bash
cd /var/www/controlx/backend
pm2 startOrReload ecosystem.config.js --update-env
pm2 save
pm2 ls
```
Beklenen: `xcontrol-api` ve `xcontrol-worker` **online**; `xcontrol-panel-v2` değişmeden online. İlk kurulumda otomatik açılış için bir kez: `pm2 startup` (ekrana çıkan `sudo env PATH=... pm2 startup ...` komutunu aynen çalıştırın) ve ardından `pm2 save`.

Günlükleri izleyin (30 sn):
```bash
pm2 logs xcontrol-api --lines 20 --nostream
pm2 logs xcontrol-worker --lines 20 --nostream
```
Beklenen: `X Control Yapı API çalışıyor → http://127.0.0.1:4000` ve `[worker] başladı ...`. `UYARI: JWT_SECRET 32 karakterden kısa` görürseniz adım 7.1.

**Başarısız olursa:**
- `xcontrol-api` sürekli yeniden başlıyor (`errored`) → `pm2 logs xcontrol-api --err --lines 50`. `JWT_SECRET tanımlı değil...` → `.env` yolu: ecosystem `cwd` klasörüdür; `.env` `/var/www/controlx/backend/.env` olmalı. `EADDRINUSE` → eski süreç portu tutuyor: `pm2 delete xcontrol-api && pm2 start ecosystem.config.js --only xcontrol-api`.
- `pm2 startOrReload` aynı adlı eski kaydı karıştırırsa: `pm2 delete xcontrol-api` sonra `pm2 start ecosystem.config.js` (**`xcontrol-panel-v2`'yi silmeyin**).
- Worker `errored` → `pm2 logs xcontrol-worker --err`; çoğunlukla migrasyon eksikliği ya da DB bağlantısıdır (adım 8).

---

## 10. Apache ayarı

API sanal ana makinesinde (örn. `/etc/apache2/sites-available/api.controlx.com.tr-le-ssl.conf`) aşağıdakilerin bulunduğundan emin olun:

```apache
<VirtualHost *:443>
    ServerName api.controlx.com.tr
    # ... SSL satırlarınız aynen kalır ...

    ProxyPreserveHost On
    ProxyRequests Off
    # mod_proxy_http X-Forwarded-For'u KENDİLİĞİNDEN ekler (TRUST_PROXY=1 ile gerçek istemci IP'si buradan okunur).
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

    # İstek gövdesi sınırı (nginx client_max_body_size muadili): en büyük yükleme 25 MB (yazışma .zip) → 30 MB
    LimitRequestBody 31457280
    # Uzun işler (büyük içe aktarma/XLSX dışa aktarma) için
    ProxyTimeout 120

    ProxyPass        / http://127.0.0.1:4000/ retry=0
    ProxyPassReverse / http://127.0.0.1:4000/
</VirtualHost>
```
```bash
sudo a2enmod proxy proxy_http headers ssl      # zaten açıksa mesaj "already enabled"
sudo apachectl configtest                      # "Syntax OK" beklenir
sudo systemctl reload apache2
```
> Önünüzde Cloudflare varsa `.env` → `TRUST_PROXY=2` yapın ve `pm2 restart xcontrol-api --update-env`. Apache `X-Forwarded-For` göndermiyorsa tüm istekler tek IP gibi görünür ve genel hız sınırı herkesi birden kısıtlayabilir.
> Panel (`panel.controlx.com.tr` → 4001) ayarına dokunmayın. Üç sitenin statik dosyaları ayrı sanal ana makinelerdedir.

**Başarısız olursa:** `configtest` hata veriyorsa `reload` yapmayın; hatalı satırı düzeltin (`sudo nano ...`) ya da eklediğiniz satırları silin. `Invalid command 'RequestHeader'` → `a2enmod headers`. Reload sonrası site açılmıyorsa `sudo journalctl -u apache2 -n 50` ve eski yapılandırmayı geri yükleyip `reload` edin.

---

## 11. Sağlık kontrolleri ve ilk doğrulama

### 11.1 Otomatik kontroller
```bash
curl -s https://api.controlx.com.tr/api/health
# {"status":"ok","time":"..."}

curl -s https://api.controlx.com.tr/api/health/worker
# {"status":"ok","last_tick_age_seconds":<30 altı>,"overdue_jobs":0}     (worker çalışmıyorsa "down" + HTTP 503)

# Yeni uçlar CANLI mı? (404 = dağıtım eksik; 401 = uç var, oturum istiyor → DOĞRU)
for p in config mobile/home invoices vat/periods tax-calendar payment-schedule receivables/aging message-templates \
         assistant/commands assistant/imports assistant/insights assistant/briefing/today assistant/inbox; do
  printf "%-28s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' https://api.controlx.com.tr/api/$p)"
done
# hepsi 401 olmalı
```
Giriş ve birkaç yetkili çağrı (şifre komut geçmişine yazılmaz):
```bash
read -r -p "Admin e-posta: " EM; read -r -s -p "Şifre: " PW; echo
TOKEN=$(curl -s https://api.controlx.com.tr/api/auth/login -H 'Content-Type: application/json' \
        -d "{\"email\":\"$EM\",\"password\":\"$PW\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'); unset PW
for p in config mobile/home assistant/briefing/today invoices; do
  printf "%-26s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" https://api.controlx.com.tr/api/$p)"
done
# hepsi 200 olmalı;  "server.version" için:
curl -s -H "Authorization: Bearer $TOKEN" https://api.controlx.com.tr/api/config | python3 -c 'import sys,json;print(json.load(sys.stdin)["server"]["version"])'   # 1.20.0
unset TOKEN
```

### 11.2 İlk kullanım kontrol listesi (elle)
- [ ] Web paneli (`panel.controlx.com.tr`) açılıyor, giriş çalışıyor (JWT_SECRET değiştiyse yeniden giriş istenir — normal).
- [ ] **Üç sitenin her birinden** (controlx.com.tr, x-metal.tr, nicebodrum.com) test teklifi gönderin → panelde görünüyor, `source_site` doğru (CORS kontrolü). Test kaydını silin.
- [ ] Mobil uygulama giriş yapıyor; ana ekran (`/mobile/home`) geliyor.
- [ ] `pm2 ls` → `xcontrol-api`, `xcontrol-worker`, `xcontrol-panel-v2` online; `pm2 logs` temiz.
- [ ] `/api/health/worker` → `ok`. Birkaç dakika sonra tekrar bakın (`last_tick_age_seconds` küçük kalmalı).
- [ ] Bildirim kutusu: uygulamadan "test bildirimi" gönderin (`POST /api/assistant/test-notification`) → kutuda görünüyor.
- [ ] Fatura: test faturası ekleyin (örn. matrah ₺1.000, KDV %20 → KDV ₺200, toplam ₺1.200) → hesap doğru, "mali müşavire teyit" rozeti görünüyor (KDV oranları kaynaklı teyitsiz tohumlanır; **mali müşavirinizle doğrulayıp `verified` yapın**). Test faturasını silin (yalnız taslak/iptal silinir: önce durumunu `iptal` yapın).
- [ ] Komut çubuğu: "yarın saat 10'da \<müşteri\> ile keşif randevusu ekle" → onay kartı gelir; **onaylamadan** randevu oluşmaz. Reddedin.
- [ ] Yazışma içe aktarma: küçük bir WhatsApp `.txt` dışa aktarımıyla önizleme alın, aydınlatma metnini okuyun; önizlemeyi silin (KVKK: gerçek müşteri verisini yalnız gerçek kullanımda içe aktarın).
- [ ] Sabah brifingi: `GET /api/assistant/briefing/today` içerik veriyor (ertesi sabah `morning_time` saatinde otomatik bildirim de gelir).
- [ ] Dosya yükleme (belge/fatura PDF'i) çalışıyor ve bağlantı 10 dk imzalı.

**Başarısız olursa (11.1):**
- `/api/health` cevap vermiyor → `pm2 logs xcontrol-api --err`; Apache: `sudo tail -50 /var/log/apache2/error.log`. Yerelden `curl http://127.0.0.1:4000/api/health` çalışıyor ama dışarıdan çalışmıyorsa sorun Apache/DNS/SSL'dir (adım 10).
- Yeni uçlar `404` → kodun tamamı kopyalanmamıştır (adım 5) ya da eski süreç çalışıyordur: `pm2 restart xcontrol-api --update-env`, `ls src/routes/bookkeeping`.
- `/api/health/worker` → `down`/503 → `pm2 logs xcontrol-worker`; worker kapalıysa **API yine çalışır**, yalnız bildirim/brifing/hatırlatma işleri durur (`pm2 start xcontrol-worker`).
- `403`/`CORS` hatası tarayıcı konsolunda → `CORS_ORIGINS`'te o site yok (adım 7.1), `.env`'i düzeltip `pm2 restart xcontrol-api --update-env`.
- Her şey 429 → `TRUST_PROXY`/`X-Forwarded-For` (adım 10).

---

## 12. Geri alma planı

İki seviye vardır. **Her zaman önce A'yı deneyin** (veri kaybı yok).

### 12-A. Yalnız kodu geri al (veritabanı yeni şemada kalır; veri korunur)
v15–v20 migrasyonları yalnız **ekleme** yapar (yeni tablolar/sütunlar, varsayılanlı); eski v16 kodu yeni şemayla çalışır (bu birleşik sürümün test sürecinde eski v16 kodu v20 şemasında 460 kontrolü geçti).
```bash
pm2 stop xcontrol-api xcontrol-worker
cd /var/www && mv controlx/backend controlx/backend_v20_hatali
tar xzf ~/yedek/backend_eski_$STAMP.tar.gz -C /var/www/controlx      # geri açılan klasör: backend (eski kod + node_modules + .env + uploads)
cd /var/www/controlx/backend && pm2 delete xcontrol-worker 2>/dev/null
pm2 start src/server.js --name xcontrol-api --update-env || pm2 restart xcontrol-api --update-env
pm2 save
curl -s http://127.0.0.1:4000/api/health
```
(Eski kurulumunuz farklı bir başlatma biçimi kullanıyorsa onu uygulayın; adım 1'deki `pm2 ls` notuna bakın.) Yedek alındıktan sonra yüklenen yeni dosyalar için `uploads/`'ı da yeni klasörden geri taşıyın: `rsync -a /var/www/controlx/backend_v20_hatali/uploads/ /var/www/controlx/backend/uploads/`.

### 12-B. Tam geri dönüş (veritabanını yedekten geri yükle — yedek sonrası girilen veri KAYBOLUR)
```bash
pm2 stop xcontrol-api xcontrol-worker
# veritabanı adı/kullanıcısı .env'deki DATABASE_URL'de (örnek: xcontrol_db / xcontrol_user)
sudo -u postgres psql -c "DROP DATABASE xcontrol_db;"
sudo -u postgres psql -c "CREATE DATABASE xcontrol_db OWNER xcontrol_user;"
pg_restore -d "$(grep -E '^DATABASE_URL=' /var/www/controlx/backend/.env | cut -d= -f2-)" --no-owner ~/yedek/xcontrol_db_$STAMP.dump
# ardından 12-A'daki gibi eski kodu geri yükleyin ve başlatın
tar xzf ~/yedek/uploads_$STAMP.tar.gz -C /var/www/controlx/backend    # gerekirse dosyaları da geri al
cp ~/yedek/env_$STAMP.bak /var/www/controlx/backend/.env              # gerekirse
```
Doğrulama: `curl -s http://127.0.0.1:4000/api/health` ve panelde giriş. Geri dönüşten sonra Apache ayarı (adım 10) eski kodla da çalışır; geri almanıza gerek yoktur.

**Başarısız olursa:** `pg_restore` uyarıları (ör. `role ... does not exist`) `--no-owner` ile zararsızdır; `DROP DATABASE` "başka oturumlar kullanıyor" derse `pm2 stop` yapıldığından emin olun ve `sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='xcontrol_db';"` çalıştırın.

---

## 13. Güvenlik sertleştirme listesi (güncellemeden sonra, bir kez)

```bash
# 13.1 Güvenlik duvarı: yalnız SSH, HTTP, HTTPS. ÖNCE ssh'a izin verin, yoksa kendinizi dışarıda bırakırsınız.
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw enable && sudo ufw status verbose
# 4000/4001/5432 portlarına dışarıdan erişim OLMAMALI (HOST=127.0.0.1; PostgreSQL yalnız localhost):
ss -tlnp | grep -E ':(4000|4001|5432)\b'        # 127.0.0.1 üzerinde dinlemeli, 0.0.0.0 değil

# 13.2 fail2ban (SSH + Apache kaba kuvvet)
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd

# 13.3 SSH: anahtarla giriş çalıştığını DOĞRULADIKTAN sonra şifreyi kapatın (/etc/ssh/sshd_config → PasswordAuthentication no; PermitRootLogin no)
sudo sshd -t && sudo systemctl reload ssh

# 13.4 Dosya izinleri ve otomatik güvenlik güncellemeleri
chmod 600 /var/www/controlx/backend/.env
sudo apt install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades

# 13.5 PM2 günlük döndürme (disk dolmasın)
pm2 install pm2-logrotate && pm2 set pm2-logrotate:max_size 20M && pm2 set pm2-logrotate:retain 14
```
**Günlük yedek (cron)** — `~/bin/xcontrol-yedek.sh`:
```bash
mkdir -p ~/bin ~/yedek
cat > ~/bin/xcontrol-yedek.sh <<'EOF'
#!/bin/bash
set -euo pipefail
cd /var/www/controlx/backend
DBURL=$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)
STAMP=$(date +%F_%H%M)
pg_dump "$DBURL" -Fc -f ~/yedek/xcontrol_db_$STAMP.dump
[ "$(date +%u)" = "7" ] && tar czf ~/yedek/uploads_$STAMP.tar.gz uploads     # pazar: dosyalar
find ~/yedek -name 'xcontrol_db_*.dump' -mtime +14 -delete                    # 14 gün sakla
find ~/yedek -name 'uploads_*.tar.gz' -mtime +45 -delete
echo "$(date -Is) yedek tamam"
EOF
chmod 700 ~/bin/xcontrol-yedek.sh
(crontab -l 2>/dev/null; echo '10 3 * * * $HOME/bin/xcontrol-yedek.sh >> $HOME/yedek/yedek.log 2>&1') | crontab -
crontab -l
~/bin/xcontrol-yedek.sh && tail -2 ~/yedek/yedek.log      # elle bir kez deneyin
```
> Yedekleri **başka bir makineye/depoya** da kopyalayın (aynı diskte yedek, disk arızasına karşı koruma değildir). Ayda bir geri yükleme denemesi yapın (boş bir veritabanına `pg_restore`).

**Başarısız olursa:** `ufw enable` bağlantınızı keserse sağlayıcı konsolundan `sudo ufw disable` ile açıp SSH kuralını kontrol edin. Cron çalışmıyorsa `grep CRON /var/log/syslog | tail`; betikte `.env` yolu/izin hatası `~/yedek/yedek.log`'da görünür.

---

## 14. Sık karşılaşılan durumlar (özet)

| Belirti | Neden | Çözüm |
|---|---|---|
| Panelden herkes çıkış yaptı | `JWT_SECRET` değişti | Normal; yeniden giriş |
| Bir sitenin teklif formu çalışmıyor, tarayıcıda CORS hatası | `CORS_ORIGINS`'te o köken yok | Adım 7.1 |
| `/api/health/worker` 503 | Worker kapalı | `pm2 start xcontrol-worker`; API etkilenmez |
| Hız sınırı herkese uygulanıyor (429) | Apache `X-Forwarded-For` iletmiyor ya da `TRUST_PROXY` yanlış | Adım 10 |
| Brifing/bildirim gelmiyor | Worker kapalı, kullanıcı bildirimleri kapattı (`/assistant/prefs`), ya da Pazar (varsayılan kapalı) | `/api/health/worker`, tercihleri kontrol edin |
| Mobil push yok ama kutuda görünüyor | `FCM_SERVICE_ACCOUNT_*` tanımsız (beklenen) | İsterseniz Firebase servis hesabı ekleyin |
| İçe aktarmada 429 | Kullanıcı başına 15 dk'da 20 sınırı | `IMPORT_RATE_MAX` |
| Yükleme 413 | Apache `LimitRequestBody` ya da `IMPORT_MAX_UPLOAD_MB` | Adım 10 / `.env` |
