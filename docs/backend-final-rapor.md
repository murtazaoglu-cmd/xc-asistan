# Backend v20 — Birleşik Sürüm Final Raporu

Tarih: 2026-11-20 · Paket: `backend.zip` (218 dosya, `package-lock.json` dahil; `node_modules`, `.env`, `uploads`, test çıktıları hariç) · Sürüm: `1.20.0`
Ortam: Node 22.23, PostgreSQL 16, temiz çalışma kopyası, **her test seti için sıfırdan oluşturulmuş veritabanı** ve ayrı sunucu süreci. Hiçbir şey sunucuya/dış sisteme gönderilmedi.

## 1. Test sonuçları (son ağaç, hepsi ayrı ayrı)

| Küme | Geçen / Toplam | Not |
|---|---|---|
| `api_test.js` | 75 / 75 | |
| `api_test_v15.js` | 174 / 174 | 4 ardışık koşuda da 0 hata (flaky giderildi) |
| `api_test_v16.js` | 211 / 211 | 4 ardışık koşuda da 0 hata (F-25 flaky giderildi) |
| `api_test_v17.js` | 211 / 211 | |
| `api_test_v18.js` | 673 / 673 | |
| `api_test_v19.js` | 311 / 311 | sunucu `IMPORT_RATE_MAX=500` ile (bkz. 2.1) |
| `api_test_v20.js` | 295 / 295 | tanımlı 296'dan biri yalnız `invoices`/`vat_periods` tabloları YOKKEN çalışır (satır 173); birleşik ağaçta koşulsuz atlanır, beklenen |
| `api_test_v21.js` (YENİ) | 189 / 189 | birleşik sürüm yetki/izolasyon/dikiş taraması |
| `unit_importer_v19.js` | 88 / 88 | |
| `unit_v20.js` | 162 / 162 | |
| `golden_commands.js` | 279 / 279 (%100) | |
| `smoke_e2e.js` (YENİ) | 23 / 23 | `server.js` + `worker.js` ayrı süreç, sahte saat |
| **Toplam HTTP/DB testi** | **2139 / 2139** | + 250 birim + 279 komut + 23 duman |

Ek doğrulamalar: eski **v16 kodu v20 şemasında** `api_test` + v15 + v16 (460 kontrol) geçti → kod-yalnız geri alma güvenli. `npm ci --omit=dev && npm audit` → **0 açık** (üretim ve tüm ağaç). `backend.zip` boş dizine açıldı → `npm ci --omit=dev` → boş DB'de `migrate` (19 yeni dosya ✔, ikinci çalıştırma değişiklik yok) → API + worker → `/api/health` ok, `/api/health/worker` ok, anonim yeni uçlar 401.

## 2. Bulunan ve düzeltilen hatalar (kök neden)

### 2.1 v19'daki 7 başarısız kontrol — çıkıntı çakışması DEĞİL, hız sınırı/test hacmi
- **Belirti:** birleşik ağaçta 7 FAIL (rıza, grup, paylaş, yeniden içe aktarma, yeni konuşma…); A2 kendi kopyasında 0.
- **Kök neden:** `routes/assistantImports.js` içe aktarmayı kullanıcı başına **15 dk'da 20** ile sınırlar (`IMPORT_RATE_MAX`, üretim varsayılanı). v19 testi tek kullanıcıyla 20'den çok içe aktarma yapar; 21. istekten sonra `429` gelir ve ona bağlı kontroller (`{"error":"Geçersiz kimlik."}` zinciri) çöker. `IMPORT_RATE_MAX=500` ile **0 hata** (doğrulandı). Route/tablo/kolon/handler adı çakışması, mount sırası, housekeeping, rate-limit *paylaşımı* yok — sınır yalnız `/assistant/imports` limiter'ında ve kullanıcıya özel (B kullanıcısı etkilenmez; v21'de sınanır).
- **Düzeltme:** üretim kodu doğru (varsayılan korunur). Test başlığına zorunlu env notu + 429'da açıklayıcı ipucu eklendi; varsayılan limit `api_test_v21.js` bölüm 8'de ayrı süreçle (20 → 429, B etkilenmez) sınanıyor. README ve `.env.example` güncellendi.

### 2.2 v16 F-25 "yükleme" flaky — GERÇEK üretim yarışı
- **Kök neden:** reddedilen/yarım kalan yüklemelerde dosya `fs.unlink(path, () => {})` ile **eşzamansız** siliniyor, HTTP yanıtı silme bitmeden gidiyordu → istemci/test yanıttan hemen sonra klasörü saydığında dosya hâlâ duruyordu (zamanlamaya bağlı).
- **Düzeltme (üretim):** `routes/documents.js`, `routes/bookkeeping/invoices.js`, `routes/gallery.js` içindeki tüm hata/silme yollarında yanıttan **önce** `fs.unlinkSync` (sessiz). Test gevşetilmedi. 4 ardışık koşu temiz.

### 2.3 v15 "saha: no money / tracking leakage" flaky — test hatası
- **Kök neden:** ham JSON metninde `"333"`/`"777"` alt dizgesi aranıyordu; rastgele UUID/zaman damgası bu rakamları içerince yanlış alarm.
- **Düzeltme (test, gerekçeli):** yapısal denetim — yük gezilir; sayısal değer olarak 777/333/4444 (veya "777.00" gibi metin hâli) ya da `total_amount/tracking_code/quote_total` anahtarı varsa FAIL. Gerçek sızıntıyı hâlâ yakalar, UUID'ye takılmaz.

### 2.4 Temiz-oda doğrulamasında bulunan üretim hataları
- **VAPID anahtarı yoksa sunucu çöküyordu** (`web-push: No key set vapidDetails.publicKey`, `services/push.js` modül yüklenirken). `.env.example` ve dokümanlar VAPID'i isteğe bağlı gösteriyordu. → Anahtarlar yoksa web-push kapanır, uyarı yazılır, sunucu başlar; `GET /push/vapid-public-key` `null` döner. Regresyon testi v21 bölüm 10.
- **Bozuk/yarım `multipart` gövdesi `500`** (busboy düz `Error` fırlatıyor; ör. `Malformed part header`) → `server.js` hata işleyicisinde `400 "Geçersiz çok parçalı (multipart) istek."`. Regresyon: v21 (NUL'lu dosya adı + yarım gövde).
- **`ADMIN_WHATSAPP_NUMBER` boşken her yeni tekliften sonra "Bildirim hatası: Cannot read properties of undefined"** logu → `notifyAdminNewOffer` numara yoksa sessizce atlar.

### 2.5 Paket / yapılandırma tutarsızlıkları
- `form-data` kodda `require` ediliyor ama `package.json`'da yoktu (axios'un geçişli bağımlılığına dayanıyordu) → açıkça eklendi (`^4.0.6`, kilit dosyası güncellendi, audit 0). `package-lock.json` sürümü 1.16.0, `package.json` 1.17.0'dı → ikisi **1.20.0**. v17 testi sürümü `"1.17.0"` diye sabitlemişti → `package.json`'dan okuyor.
- `.env.example`: `CORS_ORIGINS` yalnız 2 köken içeriyordu; üç sitenin (controlx.com.tr, x-metal.tr, nicebodrum.com — www dahil) teklif formu + panel için tam liste; kodda kullanılan ama örnekte olmayan değişkenler eklendi (`COMPANY_*`, `ASSISTANT_INTERNAL_BASE`, `FCM_PROJECT_ID`, `JOB_*`, `PLAN_EXPIRES_AFTER_MS`).
- `ecosystem.config.js`: `cwd: __dirname` (PM2 hangi dizinden çağrılırsa çağrılsın `.env` bulunur); komut `pm2 startOrReload … --update-env`.

### 2.6 Sözleşme ↔ gerçek davranış farkları (`mobile-api-contract.md` v20'de düzeltildi)
`wa_import` bayrağı örnekte `false` iken v19 ile **true**; A2 "ai_actions bu sürümde yazılmaz" (v19 yazıyor); M7/M8 "bağımlı" (birleşik sürümde `aktif`); `X-Total-Count` yalnız `limit/offset/q` verilince döner; `invoice_type` değeri `mustahsil` (belgede `musthsil` yazım hatası); sürüm örneği `1.17.0` → `1.20.0`; para birimi çelişkisi (eski uçlar TL ondalık, yeni uçlar kuruş) ve "KDV sabit %20" ifadesi açıklandı; `Idempotency-Key`/push/worker ifadeleri güncellendi; rol matrisi gerçek davranıştan (5 rol × 30 uç) çıkarılıp eklendi. Ayrı `-A1/-B/-C/-A2` dosyaları **silinmedi** (üstlerine "birleştirildi" notu eklendi).

## 3. Yetki / güvenlik taraması (yeni uçlar) — bulgu özeti
`api_test_v21.js` tüm yeni uçları (≈130 yol, `/api` ve `/api/v1`) kapsar: oturumsuz 401; personel/saha → fatura/KDV/vergi/tahsilat/şablon 403, `insights` 403, brifing/kapanış kartında finans alanı yok; ortak A↔B kimlikle erişim (fatura, dosya, plan, şablon, not, takip, `ai_action`, içe aktarma, konuşma, rıza, bildirim, müşteri kartı) 403/404 ve listede görünmez; `owner_id/org_id/created_by/user_id/owner_user_id` gövdeden yükseltme yok sayılır (fatura, plan, şablon, not, takip, rıza, tercih); `ai_actions` confirm/reject/undo/edit/get başkasının (admin dahil) kartına uygulanamaz, DB'ye enjekte edilmiş kart sahibinin yetkisiyle REST'ten geçer; dosya adı yol geçişi/uzantı sahteciliği/HTML-içerik reddi, ZIP yol geçişi/bomba/boş/.txt'siz → 4xx, SQL enjeksiyon metni etkisiz; `Idempotency-Key` kullanıcılar arası sızmaz; içe aktarma limiti kullanıcıya özel. **Yetki atlayan yol bulunmadı** (düzeltilen güvenlik/dayanıklılık bulguları: 2.2, 2.4).

## 4. Migrasyon senaryoları
| Senaryo | Sonuç |
|---|---|
| (a) boş DB → v1…v20 | 20 dosya ✔ |
| (b) v14 kurulum + veri (kullanıcı, müşteri, teklif, teklif kalemi, proje, gider, sabit gider) → v15…v20 | 6 dosya ✔; mevcut tüm satırlar aynen korundu (yalnız yeni sütunlar eklendi); şema (a) ile **birebir aynı** |
| (c) ikinci çalıştırma | "Şema güncel", değişiklik yok; şema dökümü aynı |
| (c2) `schema_migrations` silinmiş mevcut kurulum | v11 kabul → v12…v20 yeniden uygulanır, hatasız (idempotent) |
| (d) başarısız migrasyon | hem dış-transaction'lı hem kendi `BEGIN/COMMIT`'li dosyada tablo+sütun+veri **geri sarıldı**, kayıt yazılmadı, çıkış kodu 1 |
| Numara/ad çakışması | dosya numaraları benzersiz (`schema`, v2…v20); `schema_patch_push.sql` numarasız olduğundan çalışmaz (bilinçli) |

## 5. Kalan bilinen sınırlar
- **Gerçek dış sistemlerle denenmedi:** Meta WhatsApp Cloud API, Firebase FCM, gerçek SMTP yalnız sahte sunucularla; Apache/PM2/VPS üzerinde denenmedi (dokümanlar yazıldı, komutlar bu ortamda çalıştırılamaz). Node **22** ile test edildi; `engines >=20` — Node 20 ayrıca denenmedi.
- Yalnız PostgreSQL 16 ile test edildi.
- `migrate.js` eşzamanlı iki çalıştırmaya karşı kilitsizdir (PM2 ile çalıştırılmaz; elle iki kez aynı anda başlatmayın).
- `Idempotency-Key` çok parçalı (dosya) isteklerde gövde yerine içerik uzunluğunu karşılaştırır; dosya yüklemede her denemede yeni anahtar kullanın (sözleşmede belirtildi).
- Komut çubuğu onayı API'yi kendi yuvasından `fetch` ile çağırır (döngü-içi HTTP); API `HOST=127.0.0.1` ile uyumlu, ancak API'ye erişim kapalı bir ağ yapılandırmasında `ASSISTANT_INTERNAL_BASE` verilmelidir.
- Admin, işletme veri sorumlusu olarak tüm yazışma/not kayıtlarını görür (bilinçli politika, sözleşmede yazılı); ortak/personel yalnız kendisini.
- `/api/health/worker` herkese açıktır (yalnız durum/sayaç döner); worker yokken `503` döner — dış izleme bunu "uyarı" saymalı.
- KDV oranları/tevkifat/vergi takvimi **doğrulanmamış tohumlanır** (`verified=false`); yasal doğruluk için mali müşavir teyidi şarttır, uygulama fatura kesmez/hukuki tavsiye vermez.
- Brifing/hatırlatma zamanlaması gerçek saat ve kullanıcı tercihine bağlıdır; sahte saat yalnız test (üretimde `NODE_ENV=production` iken yok sayılır).

## 6. Canlıya alırken risk notları
1. **Yedek şart** (pg_dump + `.env` + `uploads` + eski kod). Kod-yalnız geri alma doğrulandı (eski v16 kodu v20 şemasında geçti); tam geri dönüş yedek sonrası veriyi kaybettirir.
2. `JWT_SECRET` değişirse herkes (panel + mobil) bir kez yeniden giriş yapar. 32 karakterden kısaysa yenileyin.
3. **`CORS_ORIGINS` eksikse** o sitenin teklif formu tarayıcıda sessizce çalışmaz → güncellemeden sonra üç siteden birer test teklifi gönderin. (Alan adları proje notlarından alındı; siteler başka bir alt alan adından yayınlanıyorsa ekleyin.)
4. **Worker yeni bir süreçtir** (`xcontrol-worker`); çalışmazsa API çalışır ama bildirim/brifing/hatırlatma durur. `/api/health/worker` izlenmeli.
5. `TRUST_PROXY` doğru sayıda olmalı (Apache tek → `1`; Cloudflare+Apache → `2`); yanlışsa hız sınırı ya herkese birden uygulanır ya da etkisizleşir.
6. Apache `LimitRequestBody` en az 30 MB (yazışma `.zip` 25 MB sınırı), `ProxyTimeout` 120.
7. İlk çalıştırmada eski/geç saatlerde worker, süresi geçmemiş akşam kapanışı/brifing işlerini yakalar (catch-up) — ilk gün beklenmedik bir bildirim gelebilir; bu tasarım gereğidir.
8. Güncelleme sırasında `xcontrol-api` 1–2 dk durur (migrasyon sırasında eski kod yeni şemaya yazmasın diye); `xcontrol-panel-v2` etkilenmez.
9. Yeni tablolara sahip KVKK verisi (yazışma içe aktarma) için aydınlatma metni/rıza akışı açıktır; gerçek müşteri verisini yalnız gerçek kullanımda içe aktarın.
