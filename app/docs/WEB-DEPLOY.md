# XC Asistan WEB Paneli: Derleme ve Yayın Rehberi

`panel.controlx.com.tr` adresindeki eski web panelinin (v10, PM2 `xcontrol-panel-v2`, port 4001) yerine geçecek
sürümdür. **Mobil uygulamayla aynı Flutter kodudur**; geniş ekranda (>= 900 dp kenar menüsü, >= 1200 dp liste + ayrıntı
bölmesi, tablolar) farklı yerleşim kullanır. Sunucuda Node gerekmez: çıktı yalnız statik dosyalardır (Apache sunar).

> Süre: ilk kurulum ~45 dk. Kesinti: yok (önce ayrı bir adreste denenir, sonra geçiş yapılır).
> Altın kural: Eski paneli ancak yeni panel hazırlık listesini (Bölüm 7) geçtikten sonra kapatın; hiçbir adımda silme yok.

---

## 1. Hızlı özet

```bash
# 1) Derle (kendi bilgisayarınızda, proje klasöründe)
source /opt/mobile/env.sh            # (yalnız bu geliştirme ortamında)
flutter pub get
flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://api.controlx.com.tr/api
# çıktı: build/web/

# 2) Sunucuya kopyala (yeni sürüm klasörü) ve bağı çevir
REL=$(date +%Y%m%d-%H%M%S)
rsync -az build/web/ dogruticaret@104.247.164.177:/var/www/controlx/panel-web/releases/$REL/
ssh dogruticaret@104.247.164.177 "ln -sfn /var/www/controlx/panel-web/releases/$REL /var/www/controlx/panel-web/current"
```

Önemli bayraklar:

| Bayrak | Anlamı |
|---|---|
| `--no-web-resources-cdn` | CanvasKit (çizim motoru) paketin içinde gelir; **Google CDN'ine bağımlılık yoktur** (CSP ve çevrimdışı için şart). |
| `--pwa-strategy=none` | Servis çalışanı üretilmez: yönetim panelinde "eski sürüm takıldı" sorunu olmaz. |
| `--dart-define=API_BASE_URL=...` | API tabanı (sonunda `/` yok). Verilmezse varsayılan `https://api.controlx.com.tr/api`. |
| `--dart-define=WEB_SESSION_ONLY=true` | (İsteğe bağlı) Oturum jetonu `sessionStorage`'a yazılır: **sekme kapanınca oturum biter** (F5 oturumu korur). Ortak bilgisayarlar için önerilir. |
| `--dart-define=WEB_WRAP_KEY=... --dart-define=WEB_WRAP_IV=...` | (İsteğe bağlı) Şifreleme anahtarını sarmak için base64 AES anahtarı/IV. Kaynak koda gömülü olduğu için küçük bir ek katmandır (Bölüm 8). |
| `--base-href /panel/` | Panel bir alt yolda sunulacaksa (kök yol varsayılan: `/`). Yol `/` ile başlayıp biter. Apache `RewriteRule`'ında `/index.html` yerine `/panel/index.html` yazın. |
| `--dart-define=DEMO=true` | Backend'siz DEMO (sahte veri). **Canlıya konmaz**; yalnız gösterim içindir. |

Kök yol (`/`) ve `--base-href` desteği `web/index.html` içinde `<base href="$FLUTTER_BASE_HREF">` ile hazırdır.
Adresler `#` içermez (`usePathUrlStrategy`): `https://panel.controlx.com.tr/customers/05321112233`.

---

## 2. Sunucu klasörü ve ilk kurulum

```bash
ssh dogruticaret@104.247.164.177
sudo mkdir -p /var/www/controlx/panel-web/releases
sudo chown -R dogruticaret: /var/www/controlx/panel-web
# İlk sürümü (adım 1) kopyaladıktan sonra:
ls -l /var/www/controlx/panel-web/current          # releases/<tarih> bağı
```

Beklenen yapı:

```
/var/www/controlx/panel-web/
  releases/20261120-2130/   index.html, main.dart.js, flutter_bootstrap.js, canvaskit/, assets/, icons/ ...
  releases/20261121-0900/   (daha yeni sürüm)
  current -> releases/20261121-0900
```

Eski sürümler `releases/` altında kalır: **geri alma = bağı eski klasöre çevirmek** (Bölüm 9).

**Başarısız olursa:** `rsync: command not found` → `sudo apt install -y rsync`. İzin hatası → klasör sahibi `dogruticaret` olmalı.

---

## 3. DNS ve Let's Encrypt (önce ayrı adreste deneme)

Eski panel `panel.controlx.com.tr` adresini kullanıyor. Kesinti olmaması için yeni paneli **önce `panel-yeni.controlx.com.tr`**
adresinde yayınlayıp deneyin, sonra asıl adrese geçin.

1. **DNS:** alan adı sağlayıcınızda `panel-yeni` için `A` kaydı → `104.247.164.177` (TTL 300). Doğrulama: `dig +short panel-yeni.controlx.com.tr`.
2. **Apache sanal ana makinesi:** `deploy/apache/panel.controlx.com.tr.conf` dosyasını sunucuya kopyalayın, `ALAN_ADI` yerine
   `panel-yeni.controlx.com.tr` yazın. Sertifika henüz yoksa önce yalnız 80 numaralı bloğu açın (aşağıdaki 3. madde):
   ```bash
   sudo cp panel.controlx.com.tr.conf /etc/apache2/sites-available/panel-yeni.controlx.com.tr.conf
   sudo sed -i 's/ALAN_ADI/panel-yeni.controlx.com.tr/g' /etc/apache2/sites-available/panel-yeni.controlx.com.tr.conf
   sudo a2enmod ssl rewrite headers deflate mime
   ```
3. **Sertifika (Let's Encrypt):** 443 bloğu sertifika dosyası olmadan açılmaz, bu yüzden önce sertifikayı alın:
   ```bash
   sudo apt install -y certbot
   sudo certbot certonly --webroot -w /var/www/controlx/panel-web/current -d panel-yeni.controlx.com.tr
   ```
   Not: 80 numaralı blok `/.well-known/acme-challenge/` yolunu yönlendirmeden bırakır. Blokları ayırmak için önce yalnız
   `<VirtualHost *:80>` bölümünü içeren geçici bir dosya kullanabilirsiniz (`a2ensite`, `apachectl configtest`, `reload`).
   Yenileme otomatiktir: `sudo certbot renew --dry-run` ile deneyin.
4. **Etkinleştir:**
   ```bash
   sudo a2ensite panel-yeni.controlx.com.tr
   sudo apachectl configtest            # "Syntax OK" beklenir
   sudo systemctl reload apache2
   ```
5. **API tarafı (CORS):** tarayıcı API'ye `Origin: https://panel-yeni.controlx.com.tr` ile gelir. `SUNUCU-GUNCELLEME.md` adım 7.1'deki
   `CORS_ORIGINS` listesinde **`https://panel.controlx.com.tr` zaten vardır**; deneme adresi için **geçici** olarak ekleyin:
   ```bash
   cd /var/www/controlx/backend && nano .env
   # CORS_ORIGINS=https://panel.controlx.com.tr,https://panel-yeni.controlx.com.tr,https://controlx.com.tr,...
   pm2 restart xcontrol-api --update-env
   ```
   Geçiş bittikten sonra `panel-yeni` kaydını listeden çıkarıp yine `--update-env` ile yeniden başlatın.
   Sunucu `exposedHeaders: X-Total-Count` gönderdiği için sayfalama tarayıcıda da çalışır; mobil uygulama CORS kullanmaz.

**Başarısız olursa:** `certbot` doğrulaması başarısızsa DNS yayılmamıştır (`dig`), 80 numaralı port güvenlik duvarında kapalıdır
(`sudo ufw status`) ya da `DocumentRoot` yoludur. `Syntax OK` yoksa `reload` yapmayın; hatalı satırı düzeltin.

---

## 4. Denetim listesi (yeni adreste)

Tarayıcıda `https://panel-yeni.controlx.com.tr` açın:

- [ ] Açılışta "XC Asistan yükleniyor" sonra giriş ekranı gelir; sekme başlığı "Giriş · XC Asistan".
- [ ] Yönetici hesabıyla giriş çalışır. **F5** sonrası oturum ve adres korunur (`/customers/...` gibi derin bağlantı açılır).
- [ ] Müşteriler / İşler: liste solda, ayrıntı sağda (>= 1200 px genişlikte). Tarayıcı geri/ileri düğmeleri çalışır.
- [ ] Para → Ödemeler / Giderler ve Fatura/KDV → Faturalar tablo olarak görünür; sütun başlığına tıklayınca sıralanır; "CSV indir" dosya indirir.
- [ ] `Ctrl+K` ya da `/` "Hızlı git" penceresini açar.
- [ ] Tarayıcı konsolunda (F12) **kırmızı hata yok**; Network sekmesinde `gstatic.com`/`googleapis.com` gibi **harici istek yok**.
- [ ] `curl -sI https://panel-yeni.controlx.com.tr | grep -iE 'content-security|x-frame|referrer|permissions|strict'` başlıkları gösterir.
- [ ] Panelden yapılan bir kayıt (ör. test müşterisi) mobil uygulamada da görünür (aynı API).
- [ ] Telefonda/dar pencerede (390 px) alt çubuklu mobil düzen çalışır.

---

## 5. Asıl adrese geçiş (`panel.controlx.com.tr`)

Eski panel şu an `panel.controlx.com.tr` → `127.0.0.1:4001` (Apache `ProxyPass`) olarak sunuluyor. Geçiş = o sanal ana makinenin
içeriğini değiştirmek. **Önce eski dosyayı yedekleyin:**

```bash
sudo cp /etc/apache2/sites-available/panel.controlx.com.tr-le-ssl.conf ~/yedek/panel_eski_vhost_$(date +%F).conf   # gerçek dosya adı farklı olabilir
ls /etc/apache2/sites-enabled | grep panel
```

Yöntem A (önerilen, geri alması kolay): yeni sanal ana makineyi `panel.controlx.com.tr` için ayrı dosyaya yazıp eskisini devre dışı bırakın:

```bash
sudo cp panel.controlx.com.tr.conf /etc/apache2/sites-available/panel-web.controlx.com.tr.conf
sudo sed -i 's/ALAN_ADI/panel.controlx.com.tr/g' /etc/apache2/sites-available/panel-web.controlx.com.tr.conf
sudo a2dissite <eski-panel-site-dosyasi>        # örn. panel.controlx.com.tr-le-ssl
sudo a2ensite panel-web.controlx.com.tr
sudo apachectl configtest && sudo systemctl reload apache2
```

Sertifika: mevcut `panel.controlx.com.tr` sertifikasını yeniden kullanabilirsiniz (`SSLCertificateFile` yollarını eski dosyadan alın);
yoksa `certbot certonly --webroot ... -d panel.controlx.com.tr` ile yenisini alın.

Doğrulama: `curl -sI https://panel.controlx.com.tr | head -5` (200, `Content-Security-Policy` var) ve tarayıcıda Bölüm 4 listesi.

---

## 6. Güncelleme (her yeni sürümde)

```bash
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=API_BASE_URL=https://api.controlx.com.tr/api
REL=$(date +%Y%m%d-%H%M%S)
rsync -az build/web/ dogruticaret@104.247.164.177:/var/www/controlx/panel-web/releases/$REL/
ssh dogruticaret@104.247.164.177 "ln -sfn /var/www/controlx/panel-web/releases/$REL /var/www/controlx/panel-web/current && ls -1dt /var/www/controlx/panel-web/releases/* | tail -n +6 | xargs -r rm -rf"
```
(Son komut yalnız en yeni 5 sürümü tutar.) Önbellek başlıkları (`no-cache`) sayesinde kullanıcılar bir sonraki yenilemede yeni sürümü alır.
Otomatik derleme için `.github/workflows/web.yml` (taslak; dağıtım adımı varsayılan kapalı).

---

## 7. Eski paneli (`xcontrol-panel-v2`:4001) devreden çıkarma planı

| Aşama | Ne yapılır | Koşul / süre |
|---|---|---|
| 1. Paralel | Yeni panel `panel-yeni` adresinde; eski panel aynen çalışır. Ekip yeni paneli günlük işte dener. | 1-2 hafta; Bölüm 4 listesi tamam |
| 2. Geçiş | `panel.controlx.com.tr` yeni statik panele çevrilir (Bölüm 5). PM2 süreci **çalışır halde bırakılır** (127.0.0.1:4001, dışarıya kapalı). | Sabah erken saatte, ekibe haber verilerek |
| 3. İzleme | Hata/şikâyet izlenir (`/var/log/apache2/panel-web-error.log`, `pm2 logs xcontrol-api`). Eski panel 4001'de bekler, gerekirse hemen geri dönülür. | 2 hafta |
| 4. Durdurma | `pm2 stop xcontrol-panel-v2 && pm2 save` (silme YOK). Eski dosyalar yerinde. | 2 haftada sorun yoksa |
| 5. Arşiv | 30 gün sonra: `pm2 delete xcontrol-panel-v2 && pm2 save`; eski panel klasörünü `tar czf ~/yedek/panel_v2_arsiv.tar.gz` ile arşivleyip kaldırın. `CORS_ORIGINS`'ten `panel-yeni` satırını silin. | Onay sonrası |

Eski panelin yaptığı ama yenisinde olmayan bir işlev bulursanız `docs/CORE-REQUESTS.md` içine yazın; `eski-panel-karsilastirma.md`
(çıktılar klasörü) karşılaştırma listesi içindir. Bu rehber backend'e (`xcontrol-api`, `xcontrol-worker`) **dokunmaz**.

---

## 8. Güvenlik notları

- **Oturum jetonu (JWT) tarayıcıda nasıl saklanır?** `flutter_secure_storage` web uygulaması jetonu **WebCrypto AES-GCM** ile
  şifreleyip `localStorage`'a yazar (`WEB_SESSION_ONLY=true` ise `sessionStorage`). Şifreleme anahtarı da aynı tarayıcı deposundadır;
  yani bu, mobildeki Keychain/Keystore gibi donanım koruması **değildir**: düz metin saklanmaz ve başka siteler okuyamaz, ancak
  panelin kendi sayfasına betik sokabilen bir saldırgan (XSS) jetonu çalabilir. Savunma katmanları:
  1. **Sıkı CSP** (`script-src 'self' 'wasm-unsafe-eval'`, satır içi betik yok, `connect-src` yalnız `api.controlx.com.tr`): harici betik yüklenemez.
  2. Web jetonu kısa ömürlüdür (`JWT_EXPIRES_IN`, varsayılan 7 gün; mobil `30d` alır). Web istemcisi `client: "web"` ile giriş yapar.
  3. Kullanıcı "Tüm cihazlardan çıkış" ile jetonları iptal edebilir (`token_version`).
  4. HTTPS + HSTS; `X-Frame-Options: DENY` ve `frame-ancestors 'none'` (tıklama hırsızlığı yok); `Referrer-Policy`, `Permissions-Policy`.
  5. Ortak/kafe bilgisayarlarında `WEB_SESSION_ONLY=true` derlemesi ya da çıkış yapmak.
- Panel yalnızca `https://api.controlx.com.tr` ile konuşur; API'nin kendi yetki denetimi (rol) her istekte geçerlidir. Arayüzde gizlenen menü güvenlik sınırı DEĞİLDİR.
- Paketlenmiş uygulamada sır yoktur (`API_BASE_URL` herkese açık adrestir). Sır/anahtarı `--dart-define` ile gömmeyin.
- Dosya yükleme/indirme tarayıcı üzerinden çalışır (15 MB sınırı sunucuda). Yazdır: tablo ayrı bir sayfa olarak yazdırılır.

---

## 9. Geri alma

| Durum | Komut |
|---|---|
| Yeni sürümde hata (kod) | `ls -1dt /var/www/controlx/panel-web/releases/*` ile bir önceki klasörü bulun, sonra `ln -sfn <önceki klasör> /var/www/controlx/panel-web/current`. Anında geçerlidir. |
| Yeni panel tamamen çalışmıyor | Bölüm 5'te eski sanal ana makineyi geri açın: `sudo a2dissite panel-web.controlx.com.tr && sudo a2ensite <eski-panel-site-dosyasi> && sudo apachectl configtest && sudo systemctl reload apache2`. Eski panel (4001) çalıştığı sürece 1 dakikada döner. |
| Eski panel durdurulmuşsa (4. aşama sonrası) | `pm2 start xcontrol-panel-v2 && pm2 save`, ardından yukarıdaki satır. |
| API/CORS sorunu | `.env`'deki `CORS_ORIGINS`'i yedekten (`~/yedek/env_*.bak`) geri yükleyip `pm2 restart xcontrol-api --update-env`. |

DNS ve sertifika geri alma sırasında DEĞİŞMEZ.

---

## 10. Sorun giderme

| Belirti | Neden | Çözüm |
|---|---|---|
| Beyaz ekran, konsolda `wasm` / MIME hatası | `.wasm` yanlış `Content-Type` ile sunuluyor | `AddType application/wasm .wasm` (örnek dosyada var), `a2enmod mime` |
| Beyaz ekran, konsolda "Refused to load ... CSP" | CSP başka alan adını engelliyor | Yeni API adresi kullanıyorsanız CSP `connect-src`'ye ekleyin |
| `/customers/123` F5'te 404 | SPA yönlendirmesi yok | `RewriteRule` bloğunu ve `a2enmod rewrite` kontrol edin |
| Girişte "Sunucuya ulaşılamıyor", konsolda CORS hatası | `CORS_ORIGINS`'te panel adresi yok | Bölüm 3, madde 5 |
| Eski sürüm görünüyor | Tarayıcı/ara önbellek | `Ctrl+Shift+R`; başlıkları `curl -sI .../main.dart.js` ile kontrol edin (`no-cache`) |
| Harf bozuk / kutucuk (Türkçe) | Inter yazı tipi paketten yüklenmedi | `assets/fonts` klasörünün kopyalandığını ve `AssetManifest` isteğinin 200 döndüğünü kontrol edin |
| Yükleme (fatura eki) "Dosya okunamadı" | Tarayıcı dosya seçimi iptal/bellek | Dosyayı yeniden seçin (15 MB altı, pdf/jpg/png/webp/heic) |

---

## 11. DEMO sürümü (gösterim)

```bash
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=DEMO=true
```
Giriş: e-postada `admin` / `personel` / `muhasebe` / `saha` geçen herhangi bir adres + herhangi bir şifre. Veriler tarayıcı
belleğindedir (sayfa yenilenince sıfırlanır; oturum açık kalır). **API'ye hiç istek atılmaz.** Statik klasör herhangi bir statik
sunucuda açılır (`python3 -m http.server`); derin bağlantılar için SPA yönlendirmesi gerekir (kök adresten gezinin).
