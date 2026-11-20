# X Control Yapı — Mobil (Flutter) API Sözleşmesi

Sürüm: backend **v20** (v16 güvenlik sertleştirme + v17 asistan altyapısı + v18 fatura/KDV/vergi + v19 komut çubuğu/içe aktarma + v20 müdür/brifing/kapanış) · Tarih: 2026-11-20 · Kaynak: `backend/src/**` (gerçek koddan çıkarıldı; test edilen davranış).

> **v17–v20 ile değişenler (özet):** yeni bölümler §15 (ortak kurallar + rol matrisi), §16 (yapılandırma, bildirim kutusu, worker), §17 (fatura, KDV, vergi takvimi, tahsilat planı, mesaj şablonları), §18 (komut çubuğu, yazışma içe aktarma), §19 (brifing, akşam kapanışı, müdür önerileri, hatırlatma uzantısı, takipler). §0–§14 aynıdır; tek açıklama farkı: push gönderimi artık worker ile çalışır (§13, §16.4) ve `Idempotency-Key` desteklenir (§14, §15). Eski v16 özeti aşağıdadır.

> **v16 ile değişenler (mobil geliştirici özeti):** (1) `/uploads` dosyaları artık kimlik ister — `file_url`/`image_url`/`pdfUrl` **10 dk geçerli imzalı bağlantı** olarak döner (§12.1); (2) e-posta alanları sıkı doğrulanır, geçersiz → `400` (§3); (3) kabul edilmiş teklifin durumu ortak/personel tarafından geri alınamaz → `409` (§3); (4) şifre değiştirme/sıfırlama uçları eklendi (§1, §12); (5) `paid_amount` artık yalnız çağıranın defterini toplar (§4); (6) paylaşılan projede başkası adına finans kaydı yazılamaz (§5); (7) belge türleri allowlist (§12). Diğer her şey v15 ile aynıdır.
Panelin (v10) gönderdiği değerler "Panel değeri" olarak ayrıca belirtildi.

---

## 0. Genel kurallar

| Konu | Kural |
|---|---|
| Taban adres | `https://api.controlx.com.tr/api` (tüm yollar `/api` ile başlar) |
| İçerik | İstek/yanıt `application/json; charset=utf-8` (dosya yüklemede `multipart/form-data`). JSON gövde sınırı 5 MB |
| Kimlik | `Authorization: Bearer <token>` (herkese açık uçlar ayrıca işaretli) |
| Kimlikler | Hepsi UUID (metin). Geçersiz UUID → `400 {"error":"Geçersiz veya eksik değer girildi."}` |
| Hata biçimi | Her hata: `{"error":"Türkçe mesaj"}` (panel `body.message \|\| body.error` okur). Ek alan olabilir (ör. gönderimde `sent:false`) |
| Durum kodları | `200` ok · `201` oluştu · `207` kısmi başarı (yalnız teklif gönderimi) · `400` doğrulama · `401` oturum yok/geçersiz/iptal · `403` yetki/sahiplik · `404` yok · `409` çakışma (aynı kayıt, ilişkili kayıt var, "bu ay zaten eklenmiş") · `413` büyük istek · `429` hız sınırı · `502` teklif hiçbir kanaldan gidemedi · `500` `"Sunucu hatası."` |
| Hız sınırı | Giriş: başarısız denemeler IP başına 15 dk'da 10 (aşınca 429). Anonim `POST /offers`: 15 dk'da 20 (**geçerli** jetonlu istek sınırsız; silinmiş/iptal jeton sayılmaz). Şifre değiştirme: kullanıcı başına 15 dk'da 10. Dosya yükleme: kullanıcı başına 15 dk'da 120. Genel: IP başına 15 dk'da 3000 (aşınca 429) |
| Dosya erişimi | `/uploads/...` adresleri kimlik ister: **imzalı bağlantı** (`?exp=&sig=`, 10 dk) ya da `Authorization: Bearer` başlığı (kayda erişimi olan kullanıcı). Yalnız yayınlanmış galeri görselleri herkese açıktır. Ayrıntı §12.1 |
| Gövde sınırı | JSON 5 MB; `/offers` (herkese açık form) **100 KB**, `/auth` ve `/track` 20 KB (aşınca `413`) |
| Tarih/saat | Yanıtta ISO-8601 UTC: `"2026-11-20T16:11:10.577Z"` (`timestamptz`). Gönderirken **offset'li ISO** kullanın (`2026-11-21T09:00:00+03:00` ya da `...Z`). Panel öğlen 12:00 yerel saatle ISO gönderir (ödeme/gider/proje tarihleri). Gün sınırları (bugün/yarın/hafta/ay) **İstanbul saatine** göredir. Saat dilimi `Europe/Istanbul` (UTC+3, yaz saati yok) |
| Para | **TL, ondalıklı** (kuruş DEĞİL). `NUMERIC(12,2)` → JSON'da sayı: `1250.5`. Gönderirken sayı ya da noktalı metin (`"1250.50"`; virgül kabul edilmez). KDV oranı eski teklif hesabında sabit **%20** (v18 fatura/KDV uçları kuruş kullanır ve oranı tablodan okur; §15) |
| Telefon | Serbest metin (`"0532 111 22 33"`). Eşleştirme için rakamlar kullanılır (`phone_key` = yalnız rakamlar, ör. `05321112233`). WhatsApp/arama için `0532…` → `90532…` çevirin |
| Boş değer | Alanlar `null` döner; PATCH'te `null`/`""` ile temizlenebilen alanlar ilgili bölümde belirtildi |
| Sayfalama | Yalnız **teklifler, müşteriler, projeler** listelerinde (bkz. §6). Diğer listeler tam döner |
| Sürüm/sağlık | `GET /health` (herkese açık) → `{"status":"ok","time":"..."}` · `GET /health/worker` (§16.6) · sürüm/bayraklar: `GET /config` (§16.1) |

### Roller
`admin` (yönetici) · `muhasebe` · `ortak` (ayrı firma, izole veri) · `personel` · `saha`.
Veri kapsamı: admin/muhasebe her şeyi görür; **ortak A, ortak B'nin verisini hiçbir uçta göremez** (teklif, proje, müşteri, randevu, ödeme, gider, stok, hatırlatıcı). personel/ortak yalnız kendi oluşturduğu ya da kendisiyle **paylaşılan** teklif/projeleri görür; saha yalnız kendisine atanan/paylaşılan kayıtları. Finans kayıtları (ödeme/gider) "defter"e göre görünür: admin+muhasebe işletme defterini (ilk admin), diğer roller yalnız kendi defterini görür. **saha hiçbir finans verisi görmez.**

Rol kısaltmaları tablolarda: **A**=admin **M**=muhasebe **O**=ortak **P**=personel **S**=saha · "hepsi" = beşi de · "oturum" = geçerli jetonu olan herkes (kayıt erişimi ayrıca denetlenir).

### Sabit değerler (enum)
| Alan | Değerler |
|---|---|
| `role` | `admin` `muhasebe` `ortak` `personel` `saha` |
| `offers.status` | `Yeni` · `İncelendi` · `Keşif Planlandı` · `Teklif Verildi` · `Kabul Edildi` · `Reddedildi` (Türkçe karakterli, tam bu yazım) |
| `projects.stage` | `Malzeme Temini` · `Üretim` · `Montaj` · `Teslim` · `Tamamlandı` |
| `project_tasks.status` | `bekliyor` · `devam_ediyor` · `tamamlandi` |
| `reminders.status` | `bekliyor` · `tamamlandi` |
| `payments.method` | `Havale` · `Nakit` · `Kredi Kartı` |
| `expenses.scope` | `ev` (kişisel) · `dukkan` · `genel` (varsayılan; panelde "İşletme") |
| `quotes.last_send_status` | `gonderildi` · `kismen` · `basarisiz` · `null` (hiç gönderilmedi) |
| `appointments.type` | **Serbest metin ≤40 karakter.** Panel değeri: `Keşif` `Montaj` `Teslim` `Bakım` `Diğer`. Sistem otomatik üretir: `baslama`, `teslim` (proje tarihlerinden), eski kayıtlarda `kesif`, `montaj`. Mobil: bilinmeyen değeri olduğu gibi göstermeli; yeni kayıtta panelin değerlerini gönderin |
| `appointments.status` | **Serbest metin ≤40.** Panel değeri: `beklemede` `onaylandı` `tamamlandı` `iptal`. Eski/otomatik kayıtlarda `planlandi`, `tamamlandi`. Ana ekran `iptal…` ile başlayanları gizler |
| `expenses.category` | Serbest metin. Panel önerileri: `Dükkan Kirası, Ev Kirası, Elektrik/Su/Doğalgaz, Maaş, Sigorta/SGK, Malzeme, Yakıt, Araç Bakım, Vergi, Telefon/İnternet, Diğer`; proje giderinde `Malzeme, İşçilik, Nakliye, Taşeron, Yakıt, Diğer` |
| `materials.unit` | Serbest metin, varsayılan `adet` |
| `device.platform` | `android` · `ios` · `web` |

---

## 1. Kimlik doğrulama (`/auth`)

| Yöntem + yol | Roller | Açıklama |
|---|---|---|
| `POST /auth/login` | herkese açık | Giriş |
| `GET /auth/me` | oturum | Kullanıcı + rol + ekip + yetenekler (oturum doğrulama) |
| `POST /auth/refresh` | oturum | Jetonu yenile (süre uzar) |
| `POST /auth/logout-all` | oturum | Tüm cihazlardaki oturumları iptal et |
| `PATCH /users/me/password` | oturum | **(v16)** Kendi şifreni değiştir (bkz. §12 Kullanıcılar) — yanıtla yeni jeton gelir |

**Login isteği:** `{ "email": "…", "password": "…", "client": "mobile" }` — `email`, `password` zorunlu; `client:"mobile"` (ya da `X-Client: mobile` başlığı) jeton ömrünü **30 gün** yapar (web: 7 gün). E-posta büyük/küçük harf duyarsız.
```json
{ "token":"eyJ…", "tokenType":"Bearer", "expiresAt":"2026-12-20T16:11:11.000Z", "expiresIn":2592000,
  "user":{ "id":"2f52…","name":"Admin","email":"admin@x.com","role":"admin" } }
```
Hatalar: `400` eksik alan · `401 {"error":"E-posta veya şifre hatalı."}` · `429` çok deneme.

**Oturum yönetimi (mobil için önerilen akış)**
1. Jetonu güvenli depoda (Keychain/Keystore, `flutter_secure_storage`) saklayın.
2. Uygulama her açılışta `GET /auth/me`: `200` → oturum geçerli; `401` → giriş ekranı. Ardından `POST /auth/refresh` ile yeni jeton alıp depolayın (kayan 30 günlük oturum; yenilenmezse 30. günde düşer).
3. Herhangi bir istekte `401` → jetonu silin, giriş ekranına dönün. Sunucu her istekte kullanıcının varlığını, rolünü ve `token_version`'ını denetler: kullanıcı silinirse/`logout-all` yapılırsa tüm jetonlar anında (en geç 10 sn) geçersizdir; rol değişikliği de yansır.
4. Çıkış: önce `DELETE /push/device`, sonra yerel jetonu silin. "Tüm cihazlardan çıkış" / telefon kaybı: `POST /auth/logout-all` (cihaz token'larını da siler). Şifre değiştirme: `PATCH /users/me/password` (başarıda **tüm eski jetonlar iptal olur**; yanıttaki yeni jetonu depolayın).

`GET /auth/me` yanıtı:
```json
{ "user":{"id":"…","name":"OrtakA","email":"oa@x.com","role":"ortak"},
  "leader":{"id":"…","name":"Admin","role":"admin"},            // kullanıcıyı oluşturan; yoksa null
  "team":[{"id":"…","name":"PersA","role":"personel"}],         // admin/muhasebe: diğer herkes; ortak: oluşturdukları; personel/saha: lider + aynı liderin ekibi
  "capabilities":{"offers":true,"quotes":true,"projects":true,"customers":true,"finance":true,
                  "homeFinance":true,"materials":true,"manageUsers":true,"appointmentsCreate":true},
  "session":{"client":"mobile","expiresAt":"2026-12-20T16:11:11.000Z"} }
```
`capabilities` yalnız menü göstermek içindir; yetki her uçta sunucuda denetlenir. Rol bazlı değerler: saha → hepsi `false`; personel → `offers, projects, finance, appointmentsCreate` true.

---

## 2. Ana ekran — `GET /mobile/home` (hepsi)

Tek istek, role göre kapsamlı. Uygulanamayan bölümler `null`: **saha** için `newOffers`, `offerStats`, `finance` = `null`; **personel** için `finance` = `null`; `finance` yalnız **A/M/O** (kendi defteri).
```json
{
 "generatedAt":"2026-11-20T16:11:11.781Z",
 "user":{"id":"…","name":"Admin","role":"admin"},
 "appointments":{
   "today":[ { "id":"…","type":"Keşif","scheduled_at":"2026-11-20T16:41:10.435Z","status":"beklemede",
               "customer_name":"Ayşe Yılmaz","customer_phone":"0532 111 22 33",
               "address":"Konacık Mah. 12 Sok.","lat":37.0344,"lng":27.4305,
               "service":"Pergola","assigned_user_id":"…","assigned_user_name":"Saha1","notes":null,
               "offer_id":"…","project_id":null,"offer_code":"OFR-1001","project_code":null, "owner_id":"…",
               "offer_name":"…","offer_phone":"…","offer_service":"…","project_customer":null } ],
   "tomorrow":[ … ] },
 "newOffers":{ "count":6, "latest":[ {"id":"…","code":"OFR-1013","name":"…","phone":"…","service":"Cam","region":"…","address":null,"status":"Yeni","created_at":"…"} ] },
 "offerStats":{ "awaitingQuote":6, "awaitingResponse":5, "accepted":2, "rejected":0,
                "byStatus":{"Yeni":6,"Teklif Verildi":5,"Kabul Edildi":2} },
 "overdueProjects":{ "count":1, "items":[ {"id":"…","code":"PRJ-503","customer_name":"…","service":"Kapı","stage":"Üretim","end_date":"…","address":null,"days_overdue":3} ] },
 "finance":{ "collectedThisWeek":1177, "collectedThisMonth":1177, "receivableTotal":7123, "receivableProjectCount":4,
             "topReceivables":[ {"id":"…","code":"PRJ-501","customer_name":"…","balance":5100} ] },
 "reminders":{ "today":[ {"id":"…","title":"…","remind_at":"…","note":null,"status":"bekliyor","project_id":null,"customer_name":null,"project_code":null,"overdue":false} ],
               "overdue":[ … "overdue":true ] },
 "lowStock":{ "count":2, "items":[ {"id":"…","name":"Profil 40x40","unit":"adet","stock_quantity":2,"min_stock":5,"low_stock_threshold":5} ] }
}
```
Tanımlar:
- `appointments.today/tomorrow`: İstanbul takvim gününe göre, saate göre artan, **iptal edilenler hariç**, en çok 100 kayıt. Telefon/adres hazırdır (aşağıdaki §9 çözümleme sırası).
- `newOffers`: durumu `Yeni` olan teklifler (sayı + son 5). `awaitingQuote` = Yeni+İncelendi+Keşif Planlandı; `awaitingResponse` = Teklif Verildi; `accepted` = Kabul Edildi.
- `overdueProjects`: `end_date` bugünden önce **ve** aşama `Tamamlandı` değil; en eski 10; `count` toplam.
- `finance` (TL): `collectedThisWeek/Month` = kendi defterindeki tahsilat (hafta Pazartesi başlar). `receivableTotal` = Σ max(sözleşme + ilave işler − tahsilat, 0). admin/muhasebe: admin/muhasebe sahipli ve sahipsiz projeler (ortakların projeleri hariç); ortak: yalnız kendi sahibi olduğu projeler.
- `reminders`: yalnız `bekliyor`; bugün + gecikmiş (toplam en çok 50). `lowStock`: `stock_quantity ≤ min_stock`, en çok 20 (`min_stock` = `low_stock_threshold` takma adı).

---

## 3. Teklifler (`/offers`) ve teklif hazırlama/gönderme (`/quotes`)

| Yöntem + yol | Roller | Not |
|---|---|---|
| `POST /offers` | **herkese açık** (jeton varsa teklif o kullanıcıya ait olur) | Yeni teklif talebi |
| `GET /offers` | A M O P | Liste; `?status=` `?q=` `?limit=` `?offset=` (§6) |
| `GET /offers/:id` | A M O P | Tek teklif + `quote` (son teklif) |
| `PATCH /offers/:id` | A M O P | Temel bilgi düzenle |
| `PATCH /offers/:id/status` | A M O P | Durum değiştir (Kabul → proje otomatik oluşur) |
| `PATCH /offers/bulk-status` | A M O P | Toplu durum `{ids:[…], status}` → `{message, updated}` |
| `DELETE /offers/:id` | A O P | admin hepsini; diğerleri yalnız KENDİ oluşturduğunu |
| `DELETE /offers/bulk` | A M O P | Gövde `{ids:[…]}` → `{message, deleted}`; admin hepsi, diğerleri kendi oluşturdukları |
| `POST /quotes/:offerId` | A M O | Teklif (kalemler) kaydet |
| `POST /quotes/:offerId/send` | A M O | PDF üret + WhatsApp + e-posta gönder |

**POST /offers** gövdesi: `name`*, `phone`*, `service`* (metin), `email`, `region` (≤200, fazlası kırpılır), `message` (**≤2000 karakter**, aşarsa `400`), `photo_urls` (≤10 URL dizisi; **yalnız genel `https://` adresleri saklanır**, `javascript:`/`http:`/IP/`localhost`/iç alan adları sessizce atılır), `source_site` (`controlx`/`xmetal`/`nicebodrum`; başka değer `controlx` olur), `address` (≤500), `lat`+`lng` (birlikte). **`email` (v16):** tek, geçerli bir adres olmalı (≤254 karakter; virgül/boşluk/`<>`/çoklu adres/"Ad <adres>" biçimi **kabul edilmez** → `400 {"error":"Geçerli bir e-posta adresi girin."}`); `""`/`null` → e-posta yok. Takip kodu artık `XCY-` + 8 karakter (eski 5 karakterlik kodlar geçerli). Yanıt `201`:
`{"message":"Teklif talebiniz alındı.","id":"…","code":"OFR-1013","trackingCode":"XCY-5DBRS","trackingUrl":"https://…/teklif-takip/XCY-5DBRS"}` (tam kayıt DEĞİL; ayrıntı için `GET /offers/:id`).

**PATCH /offers/:id** gövdesi (hepsi opsiyonel, en az biri): `name, phone, email, service, region, message, notes, address, lat, lng` (`address`/`lat`/`lng` `null` ile temizlenir; lat/lng birlikte). Yanıt: güncel kayıt.

**Teklif kaydı (liste satırı):**
```json
{ "id":"…","code":"OFR-1001","tracking_code":"XCY-4F2A9","name":"…","phone":"…","email":null,"service":"Pergola","region":"Bodrum",
  "message":null,"notes":null,"photo_urls":[],"status":"Teklif Verildi","source":"website|admin","source_site":"controlx",
  "owner_id":null,"address":"…","lat":37.03,"lng":27.43,"created_at":"…","updated_at":"…",
  "quote":{ "items":[{"desc":"Pergola","qty":1,"price":1000,"vatIncluded":false}],"subtotal":1000,"tax":200,"total":1200,
            "created_at":"…","sent_via_whatsapp_at":null,"sent_via_email_at":"…",
            "last_send_status":"kismen","last_send_at":"…","last_send_error":"WhatsApp: …" },
  "quote_items":…,"quote_total":1200 }
```
(`quote` yoksa `null`; düz `quote_*` alanları geriye dönük uyumluluk içindir, `quote` nesnesini kullanın. `GET /offers/:id` yanıtında `quote` tam satırdır: `id, offer_id, items, subtotal, tax, total, sent_via_*_at, last_send_*`.)

**POST /quotes/:offerId** gövdesi: `{ "items":[ { "desc":"Metin", "qty":1, "price":1000, "vatIncluded":false } ] }` — en az 1 kalem; `qty > 0`, `price ≥ 0` (TL); `vatIncluded:true` → fiyata %20 KDV dahildir, `false` (varsayılan) → KDV üstüne eklenir. Toplamlar sunucuda hesaplanır. `201` yanıt: kayıt `{id, offer_id, items, subtotal, tax, total, …}`. Yan etki: teklif durumu Yeni/İncelendi/Keşif Planlandı ise `Teklif Verildi` olur (Kabul/Red geriye düşmez).

**POST /quotes/:offerId/send** (gövde yok). Gerçek sonuç döner; `sent:true` yalnız en az bir kanal sağlayıcıya kabul ettirdiyse:
```json
{ "sent":true, "channel":"email", "status":"kismen", "error":"WhatsApp: WhatsApp 24 saat kuralı: …",
  "channels":{ "whatsapp":{"sent":false,"error":"WhatsApp 24 saat kuralı: …"},
               "email":{"sent":true,"skipped":false,"error":null} },
  "message":"Teklif kısmen gönderildi.",
  "results":{"whatsapp":"hata: …","email":"gönderildi"},
  "pdfUrl":"https://api…/uploads/teklif-OFR-1001-….pdf?exp=1795000000&sig=…",
  "whatsappUrl":"https://wa.me/905321112233?text=…" }
```
| HTTP | `status` | Anlamı |
|---|---|---|
| `200` | `gonderildi` | Denenen tüm kanallar gitti (`channel`: `"whatsapp,email"` ya da müşterinin e-postası yoksa `"whatsapp"`) |
| `207` | `kismen` | En az biri gitti, denenen başka kanal hata verdi → `channels.*.error` gösterin; "WhatsApp'ta kendim gönder" için `whatsappUrl`'yi açın |
| `502` | `basarisiz` | Hiçbiri gitmedi (`sent:false`, `channel:null`, `error` dolu) |

**(v16)** `pdfUrl` **10 dk geçerli imzalı bağlantıdır** (tarayıcıda/PDF görüntüleyicide Authorization başlığı olmadan açılır; süresi dolarsa teklifi yeniden gönderin ya da `Authorization` başlığıyla çekin). `whatsappUrl` içindeki metin artık PDF bağlantısı yerine müşterinin **teklif takip sayfasını** (`SITE_URL/teklif-takip/<takip_kodu>`) içerir — imzalı bağlantılar süresi dolduğu ve sızabildiği için müşteriye gönderilmez; otomatik gönderimde PDF zaten ek olarak gider. Müşterinin kayıtlı e-postası geçersizse (eski kayıt) e-posta kanalı `error: "Müşterinin e-posta adresi geçersiz; gönderilmedi."` ile başarısız sayılır. Hata metinleri iç ayrıntı (IP/sunucu adı) içermez.
`channels.email.skipped:true` → müşterinin e-postası yok (hata sayılmaz). Teklifin `status` alanı gönderime göre DEĞİŞMEZ; gönderim durumu teklifin `quote.last_send_status` alanındadır. `400` → önce teklif hazırlanmalı. Meta kuralı: müşteri son 24 saatte yazmadıysa serbest doküman reddedilir (sık hata).

`PATCH /offers/:id/status` gövdesi `{"status":"Kabul Edildi"}` → güncel teklif. **(v16)** Kabul edilmiş (projesi oluşmuş) teklifi başka bir duruma almak yalnız **admin** içindir; diğer roller `409 {"error":"Kabul edilmiş teklifin durumu değiştirilemez…"}` alır (aynı durumu yeniden göndermek zararsızdır; `bulk-status` bu teklifleri sessizce atlar, `updated` sayısına katmaz). Diğer geçişler (ör. `Reddedildi → Yeni`) serbesttir. `PATCH /offers/:id` `email` için aynı doğrulamayı yapar; `message ≤ 2000`, `notes ≤ 4000`, `name/service/region ≤ 200`, `phone ≤ 40` (aşarsa `400`).

---

## 4. Projeler, görevler, ilave işler (`/projects`)

| Yöntem + yol | Roller | Not |
|---|---|---|
| `GET /projects` | A M O P | Liste (`?q ?limit ?offset`); satırda `paid_amount` = **yalnız çağıranın defterindeki** tahsilat toplamı (v16; bkz. §5) |
| `POST /projects` | A M O P | Manuel proje |
| `GET /projects/:id/full` | A M O P | `{project, tasks, extras, payments, expenses}` (ödeme/gider yalnız kendi defteri) |
| `PATCH /projects/:id` | A M O P | `customer_name, service, notes, address, lat, lng` |
| `PATCH /projects/:id/stage` | oturum (erişimi olan; saha dahil) | `{stage}` — `Tamamlandı` olunca `end_date=şimdi` |
| `PATCH /projects/:id/amount` | A M O P | `{total_amount}` ≥ 0 |
| `PATCH /projects/:id/dates` | A M O P | `{start_date?, end_date?}` ISO; `end_date:null` temizler; **yan etki:** `baslama`/`teslim` randevuları otomatik oluşur/güncellenir |
| `DELETE /projects/:id` | A | Geri alınamaz |
| `GET /projects/:id/collaborators` | A M O P | Projeye erişen kullanıcılar (atama seçici) → `[{id,name,role}]` |
| `GET/POST /projects/:id/tasks` | oturum (erişimi olan) | Görev listesi / `{title*, assigned_user_id?}` |
| `PATCH/DELETE /projects/tasks/:taskId` | oturum (erişimi olan) | `{status?, title?, assigned_user_id?}` — **(v16)** `assigned_user_id` yalnız proje sahibi/projeyle paylaşılmış kişi (ya da kendin) olabilir, aksi `400 "Görev yalnızca projedeki kişilere atanabilir."` (POST ile aynı kural); `null` atamayı kaldırır; başkasına atanınca ona push gider |
| `GET /projects/tasks/pending` | A M O P | Tüm projelerde tamamlanmamış görevler |
| `GET/POST /projects/:id/extras` | A M O P | İlave iş: `{description*, amount*}` (negatif olabilir) |
| `DELETE /projects/extras/:extraId` | A M O P | |

`POST /projects` gövdesi: `customer_name`*, `service`*, `total_amount` (≥0, varsayılan 0), `stage` (enum; geçersizse `Malzeme Temini`), `address`, `lat`, `lng`. Yanıt `201`: proje satırı:
```json
{ "id":"…","code":"PRJ-508","offer_id":null,"customer_name":"…","service":"Merdiven","stage":"Malzeme Temini",
  "total_amount":10,"assigned_team":null,"start_date":"…","end_date":null,"notes":null,"owner_id":"…",
  "address":null,"lat":null,"lng":null,"paid_amount":0 }
```
(`paid_amount` yalnız liste yanıtındadır ve çağıranın defterini toplar: admin/muhasebe → işletme defteri (ilk admin), diğerleri → kendi kayıtları. `GET /customers/:phoneKey` içindeki `projects[].paid_amount` için de aynı kural geçerlidir.) Teklif **Kabul Edildi** olunca proje otomatik oluşur: sahip teklifle aynı, tutar son teklif toplamı, görevler teklif kalemlerinden, adres tekliften kopyalanır.

---

## 5. Ödemeler, giderler, sabit giderler (finans) — **saha: tümü 403**

| Yöntem + yol | Roller | Gövde / not |
|---|---|---|
| `POST /projects/:id/payments` | A M O P | `{amount*>0, method*(enum), note?, paid_at?(ISO), owner_id?}` → `201` ödeme |
| `GET /projects/:id/payments` | A M O P | Yalnız kendi defteri |
| `GET /projects/payments/all` | A M O P | Tüm ödemeler (+ `customer_name, project_code`) |
| `PATCH /projects/payments/:paymentId` | A M O P | `amount, method, note, paid_at, owner_id` (yalnız kendi defterindeki; admin hepsi) |
| `DELETE /projects/payments/:paymentId` | A M O P | `{message}` |
| `GET /expenses` | A M O P | Kendi defteri (+ `customer_name, project_code`) |
| `POST /expenses` | A M O P | `{category*, amount*>0, note?, project_id?, expense_date?(ISO), scope?(ev/dukkan/genel), owner_id?}`; `project_id` yoksa genel gider — **personel genel gider giremez (403)** |
| `PATCH /expenses/:id` | A M O P | `category, amount, note, scope, expense_date, owner_id` |
| `DELETE /expenses/:id` | A M O P | |
| `GET/POST /projects/:id/expenses` | A M O P | Proje gideri: `{category*, amount*, note?, owner_id?}` |
| `GET/POST/PATCH/DELETE /recurring-expenses` | A M O | `{category*, amount*, note?, scope?}`; PATCH ayrıca `active` |
| `POST /recurring-expenses/:id/apply` | A M O | Bu ayın gider kaydını oluşturur (`201` gider); aynı ay tekrar → `409` |

`owner_id` (başkasının defterine atama) **v16 kuralı:** admin → var olan her kullanıcıya; muhasebe ya da **projenin sahibi** → proje sahibine/projeyle paylaşılmış kişiye; **projeyle yalnızca paylaşılmış (işbirlikçi) bir kullanıcı asla başkasının defterine yazamaz** — `owner_id` verse bile kayıt sessizce kendi defterine düşer (hata dönmez). `project_id` olmayan genel giderde yalnız admin atayabilir. Atama yapılan kişiye push bildirimi gider. Ödeme satırı: `{id, project_id, amount, method, note, paid_at, owner_id}`; gider satırı: `{id, project_id, category, amount, note, created_at, expense_date, scope, owner_id}`.

---

## 6. Arama ve sayfalama (teklifler, müşteriler, projeler)

`GET /offers`, `GET /customers`, `GET /projects` için opsiyonel:
- `?q=metin` — büyük/küçük harf duyarsız "içerir" araması (≤100 karakter). Teklif: ad, telefon, e-posta, kod, hizmet, bölge, adres. Müşteri: ad, telefon, e-posta, bölge, adres. Proje: müşteri, kod, hizmet, adres, not. Telefon aramasında ≥3 rakam girilirse boşluk/tire fark etmez.
- `?limit=1..200` ve `?offset=0..` — `offset` limitsiz gelirse limit=50. Geçersiz değer → `400`.
- Hiçbiri yoksa **eski davranış**: tüm kayıtlar.
- Yanıt gövdesi **her zaman düz dizi**; `q` ya da `limit` varsa toplam eşleşme sayısı **`X-Total-Count`** yanıt başlığındadır.
- Sıralama sabit: teklif `created_at DESC`, proje `start_date DESC`, müşteri `last_contact DESC`.
- Kapsam (ortak yalıtımı vb.) arama/sayfalamada da aynen uygulanır.

---

## 7. Müşteriler (`/customers`) — A M O (personel/saha yok)

Liste telefon numarasına göre birleştirilmiş müşterilerdir (tekliflerden türeyenler + elle eklenenler).

| Yöntem + yol | Not |
|---|---|
| `GET /customers` | `?q ?limit ?offset` |
| `POST /customers` | `{name*, phone*, email?, region?, note?, address?, lat?, lng?}` → `201` (sahibi = oluşturan) |
| `GET /customers/:phoneKey` | `{offers:[…], projects:[…]}` (`phoneKey` yalnız rakamlar) |
| `PATCH /customers/:phoneKey` | `name, email, region, note, address, lat, lng` — **yalnız elle eklenen** müşteri; tekliften türeyen müşteri için `404` (ilgili **teklifi** PATCH'leyin) |
| `DELETE /customers/:phoneKey` | Elle eklenen müşteriyi siler (`200 {message}`; kapsam dışıysa sessizce hiçbir şey silmez) |

Liste satırı: `{phone_key, name, email, phone, region, address, lat, lng, offer_count, first_contact, last_contact, project_count, total_contracted, total_paid}` (para alanları kendi defterine göre).

---

## 8. Hatırlatıcılar (`/reminders`) — oturum (saha dahil)

| Yöntem + yol | Gövde |
|---|---|
| `GET /reminders` | Tüm hatırlatıcılar (admin/muhasebe hepsi; diğerleri kendi + erişebildiği projeninkiler), `remind_at` artan |
| `POST /reminders` | `{title*, remind_at*(ISO), project_id?, note?}` → `201` |
| `PATCH /reminders/:id` | `{status: "bekliyor"\|"tamamlandi"}` (yalnız kendi oluşturduğu; admin/muhasebe hepsi) |
| `DELETE /reminders/:id` | `{message}` |

Satır: `{id, project_id, title, remind_at, note, status, created_at, owner_id, customer_name, project_service, project_code}`.

---

## 9. Randevular (`/appointments`)

| Yöntem + yol | Roller | Not |
|---|---|---|
| `GET /appointments` | hepsi | Role göre kapsam. Filtre: `?from=ISO` (dahil) `&to=ISO` (hariç) `&assigned_user_id=<uuid\|me>` `&status=` |
| `GET /appointments/:id` | hepsi (erişimi olan) | Tek randevu |
| `POST /appointments` | A M O P | Oluştur |
| `PATCH /appointments/:id` | hepsi (erişimi olan) | Düzenle. **saha** yalnız `status`, `notes`, `scheduled_at` değiştirebilir (diğerleri 403) |
| `DELETE /appointments/:id` | A M O P | `{message}` |

Kapsam: admin/muhasebe hepsi; diğerleri kendi oluşturdukları, kendilerine atananlar, kendi/paylaşılan teklif ve projelere bağlı olanlar. **Ortak başka bir ortağın randevusunu görmez/değiştiremez.**

**POST gövdesi:** `type`* (metin ≤40), `scheduled_at`* (ISO), `notes?`, `offer_id?`, `project_id?`, `assigned_user_id?` (varsayılan: oluşturan), `customer_name?`, `customer_phone?` (teklif/projeye bağlı olmayan doğrudan müşteri için), `address?` (≤500), `lat?`+`lng?`. Bağlanan teklif/projeye erişim şart (`403/404`). Atama yalnız **kendi ekibine** yapılabilir (admin/muhasebe herkese; ortak kendisine ve oluşturduğu kullanıcılara; personel kendisine/liderine/aynı lider altındakilere) → aksi `403`. Yanıt `201`: çözümlenmiş randevu.

**PATCH gövdesi** (hepsi opsiyonel): `status, scheduled_at, notes, type, offer_id, project_id, assigned_user_id, customer_name, customer_phone, address, lat, lng`. `offer_id/project_id/assigned_user_id: null` bağlantıyı/atamayı kaldırır. Yanıt: çözümlenmiş randevu.

**Yanıt (çözümlenmiş randevu):**
```json
{ "id":"…","offer_id":"…","project_id":null,"type":"Keşif","scheduled_at":"2026-11-20T16:41:10.435Z",
  "assigned_user_id":"…","assigned_user_name":"Saha1","notes":null,"status":"beklemede","owner_id":"…",
  "customer_name":"Ayşe Yılmaz","customer_phone":"0532 111 22 33",
  "address":"Konacık Mah. 12 Sok.","lat":37.0344,"lng":27.4305,"service":"Pergola",
  "offer_code":"OFR-1001","project_code":null,
  "offer_name":"…","offer_phone":"…","offer_service":"…","project_customer":null }
```
Çözümleme sırası (önce dolu olan kazanır): `customer_name` = randevunun kendi adı → teklif adı → proje müşterisi → projenin teklifi; `customer_phone` = kendi → teklif → projenin teklifi; `address/lat/lng` = ilk kaynağın üçü birlikte: randevu → teklif → proje → projenin teklifi. `offer_*`/`project_*` alanları panel uyumluluğu içindir.
Proje tarihleri kaydedilince `type:"baslama"`/`"teslim"` randevuları otomatik oluşur (bunlar normal randevu gibi listelenir; `status:"planlandi"`).

---

## 10. Saha rolü (S) — özet

- `GET /dashboard-init` **çalışır** (saha dahil tüm roller): saha için `appointments` (kendine atanan/paylaşılan, müşteri adı/telefon/adres hazır), `projects` (paylaşılan; **`total_amount` yok**, `customer_phone` var), `offers` (paylaşılan; yalnız güvenli sütunlar: izleme kodu/e-posta yok), `customers` (ad/telefon/bölge/adres), `reminders`, `users` (ekip), `materials`. `payments`, `expenses`, `recurringExpenses`, `quoteTemplates` = `[]`; `financeSummary` = `null`.
- Saha için açık uçlar: `/auth/*`, `/mobile/home`, `/dashboard-init`, `/appointments` (GET + kısıtlı PATCH), `/reminders`, `/projects/:id/tasks` + `/projects/tasks/:id`, `PATCH /projects/:id/stage`, `/documents/*`, `/shares` (GET), `/activity/*`, `/push/device`. Diğerleri `403` (teklif, proje listesi/`full`, müşteri, finans, rapor, stok, galeri).
- Dashboard-init yanıt anahtarları: `offers, projects, payments, appointments, expenses, customers, reminders, users, quoteTemplates, materials, recurringExpenses, financeSummary`.

---

## 11. Stok (`/materials`) — A M O

`GET /materials` · `POST /materials` `{name*, unit?, stock_quantity?, low_stock_threshold?(varsayılan 5), note?}` (negatif olmayan sayılar) · `PATCH /materials/:id` (aynı alanlar; panel stok ± için `{stock_quantity}` gönderir) · `DELETE /materials/:id`. Satır: `{id,name,unit,stock_quantity,low_stock_threshold,note,updated_at,owner_id}`. Düşük stok: `stock_quantity ≤ low_stock_threshold` (ana ekranda `min_stock` adıyla). Ortak yalnız kendi stoğunu görür/değiştirir.

## 12. Belgeler, galeri, paylaşım, aktivite, kullanıcılar, şablonlar

**Belgeler (`/documents`) — oturum, kayda erişimi olan** (saha dahil; teklif/proje paylaşıldıysa)
- `GET /documents/:resourceType/:resourceId` (`resourceType` = `offer` | `project`) → `[{id, resource_type, resource_id, file_url, file_name, uploaded_by, uploaded_by_name, created_at}]` — `file_url` **imzalı, 10 dk geçerli** (§12.1).
- `POST /documents/:resourceType/:resourceId` — **`multipart/form-data`, tek alan `file`** (en çok 1 dosya, **15 MB**). **(v16) Yalnız şu uzantılar kabul edilir (allowlist):** `.pdf .png .jpg .jpeg .webp .gif .heic .heif .mp4 .mov .doc .docx .xls .xlsx .ppt .pptx .odt .ods .rtf .txt .csv .dwg .dxf .zip`; başka uzantı → `400 "Bu dosya türü yüklenemez."`. Dosyanın **ilk baytları da uzantıyla uyuşmalıdır** (ör. `.pdf` adlı HTML → `400 "Dosya içeriği uzantısıyla uyuşmuyor; yüklenemez."`). Yetki/kaynak denetimi dosya diske yazılmadan önce yapılır (`403`/`404` dosya yazmaz). `201` kayıt döner; `file_name` orijinal addır (kontrol karakterleri temizlenir, ≤200), `file_url` imzalı mutlak adrestir.
- `DELETE /documents/:id` → `{message}` — kayıtla birlikte **dosya diskten de silinir**; eski bağlantılar `404` döner.
- `GET /documents/file/:id` — **(v16)** dosyayı `Authorization` başlığıyla akıtır (kayda erişimi olan kullanıcı); imzalı bağlantı yerine kullanılabilir. `Content-Disposition`: görsel/PDF `inline`, diğerleri `attachment`.
- Flutter/Dio: `FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)})` — `Content-Type`'ı elle `application/json` yapmayın; `Authorization` başlığı yeterli. Sunucu önünde nginx `client_max_body_size ≥ 16m` gerekir.

### 12.1 Dosya erişimi (`/uploads`) — v16

`/uploads/...` altındaki dosyalar (belgeler, teklif PDF'leri, yayınlanmamış galeri görselleri) **artık herkese açık değildir**. İki yol vardır:

1. **İmzalı bağlantı (önerilen, `<img>`/`Image.network`/`url_launcher`/WebView uyumlu):** API'nin döndürdüğü `file_url` (belgeler), `image_url` (galeri yönetimi), `pdfUrl` (teklif gönderimi) zaten `…/uploads/<yol>?exp=<unix>&sig=<HMAC>` biçimindedir; **Authorization başlığı gerekmez**, **10 dakika** geçerlidir (`UPLOAD_URL_TTL_SEC` ile sunucuda değişir). İmza yola ve süreye bağlıdır: sorgu dizesini değiştirmek, başka dosyada kullanmak ya da süresi geçmiş bağlantı `401` verir. Bağlantıyı **saklamayın/paylaşmayın**; her ekran açılışında listeyi yeniden çekip güncel bağlantıyı kullanın (liste her çağrıda yeni imza üretir). Süresi dolmuş bağlantıda `401` alırsanız listeyi yenileyin.
2. **`Authorization: Bearer <jeton>` başlığı** ile doğrudan `GET /uploads/<yol>` (örn. `Image.network(url, headers: {'Authorization': 'Bearer $token'})`): kayıt sahibi/paylaşılan kişi/admin-muhasebe erişir; başkasının kaydı `403`, geçersiz jeton `401`.

Yanıt kodları: imza/oturum yok → `401`; yetkisiz kayıt → `403`; dosya yok/silinmiş → `404`. Yayınlanmış galeri görselleri (`GET /gallery/published`) imzasız herkese açıktır (web sitesi). Dosyalar `X-Content-Type-Options: nosniff` ile servis edilir; görsel/PDF dışındaki türler tarayıcıda açılmaz, **indirilir** (`attachment`).

**Galeri (`/gallery`)** — **yalnız A M**. `GET /gallery/project/:projectId` · `POST /gallery/project/:projectId` (`multipart`, dosya alanı **`photo`**, yalnız `.jpg .jpeg .png .webp .gif .heic .heif` (içerik doğrulanır; **svg kabul edilmez**), **8 MB**; olmayan proje `404`, dosya diske yazılmaz; metin alanları `category?`, `before_after?` = `before`\|`after`, `published?` = `"true"`\|`"false"` metin) → `201 {id, project_id, image_url, category, before_after, published, created_at}` (`image_url` imzalı, 10 dk; yayınlanınca imzasız adres de herkese açık olur) · `PATCH /gallery/:id` `{published:boolean}` · `DELETE /gallery/:id`. Herkese açık: `GET /gallery/published` (site için). Saha/personel/ortak galeri yükleyemez (fotoğraf için `/documents` kullanın).

**Paylaşım (`/shares`) — oturum**
- `GET /shares/:resourceType/:resourceId` → `[{id, resource_type, resource_id, shared_with_user_id, shared_by_user_id, created_at, user_name, user_email}]`
- `POST /shares` `{resource_type:"offer"|"project", resource_id, user_id}` → `201` paylaşım (zaten varsa `{message}`). Yalnızca kaydın sahibi ya da admin/muhasebe paylaşabilir; ortak yalnız kendi ekibiyle. Alıcıya push gider.
- `DELETE /shares/:id` → `{message}`.

**Aktivite:** `GET /activity/:resourceType/:resourceId` → son 100 `[{id, resource_type, resource_id, user_id, action, details, created_at, user_name}]` (`action`: `durum_degisti, duzenlendi, paylasildi, odeme_eklendi, dosya_eklendi, asama_degisti`).

**Kullanıcılar (`/users`) — A, O**
- `GET /users` → `[{id,name,email,role,created_at}]` (ortak: yalnız oluşturdukları)
- `POST /users` `{name*(≤100), email*, password*, role*}` → `201` kullanıcı. admin: tüm roller; **ortak yalnız `saha`/`personel`** oluşturabilir. Aynı e-posta → `409`. **(v16)** `email` geçerli biçimde olmalı (`400`); alanların tipi doğrulanır (sayı/dizi/nesne → `400`, artık `500` değil). **Şifre kuralı:** metin, en az 6 karakter (`PASSWORD_MIN_LENGTH` ile sunucuda artırılabilir — mobil formda en az 8 öneriniz), en çok 72 bayt, yaygın şifreler (`123456`, `password`, `qwerty`…) reddedilir.
- `PATCH /users/me/password` `{current_password*, new_password*}` → `200 {message, token, tokenType, expiresAt, expiresIn, user}` — **(v16)** mevcut şifre yanlışsa `400`; başarıda kullanıcının **tüm eski jetonları ve cihaz push kayıtları iptal olur**, yanıttaki yeni jetonu depolayın (ve FCM token'ı yeniden `POST /push/device` edin). Kullanıcı başına 15 dk'da 10 deneme.
- `PATCH /users/:id/password` `{new_password*}` — **(v16) A, O**: admin herkesin, ortak yalnız kendi oluşturduğunun şifresini sıfırlar (`403` başkası); hedefin tüm oturumları iptal olur.
- `DELETE /users/:id` — kendini silemezsin (`400`); ortak yalnız kendi oluşturduğunu. Silinen kullanıcının finans kayıtları silene devredilir.
- (Kullanıcı düzenleme / pasifleştirme ucu hâlâ **yok**; şifre uçları yukarıdadır.)

**Teklif şablonları (`/quote-templates`) — A M:** `GET`, `POST {name*, items*[…]}`, `DELETE /:id`.

**Takip (herkese açık):** `GET /track/:trackingCode` (durum + teklif özeti), `POST /track/:trackingCode/decision {decision:"Kabul Edildi"|"Reddedildi"}` — müşteri sayfası içindir; mobilde gerekmez.

---

## 13. Raporlar (`/reports`) ve push cihaz kaydı

**Raporlar — A M O P** (hepsi yalnız kendi defteri/kapsamı)
| Uç | Yanıt |
|---|---|
| `GET /reports/summary` | `{totalOffers, statusCounts, conversionRate, totalRevenue, activeProjects, businessExpenses, homeExpenses, expensesByScope:{dukkan,genel,ev}, netProfit, netProfitInclHome}` |
| `GET /reports/profit?range=monthly\|yearly` | `[{period:"2026-11", revenue, businessExpenses, homeExpenses, netProfit, netProfitInclHome}]` (yearly: `"2026"`) |
| `GET /reports/revenue?range=monthly\|yearly` | `[{period, total}]` (yalnız tahsilat) |
| `GET /reports/service-distribution` | `[{service, count}]` |

**Kâr tanımı:** `netProfit = totalRevenue − businessExpenses` — `businessExpenses` yalnız `scope` = `dukkan` + `genel`. **`ev` (kişisel) giderler işletme net kârına dahil değildir**; `homeExpenses` ayrı alandır. Eski "hepsi dahil" görünüm: `netProfitInclHome`. `GET /dashboard-init` yanıtındaki `financeSummary` da aynı alanları verir (`totalRevenue, businessExpenses, homeExpenses, expensesByScope, netProfit, netProfitInclHome`).

**Push cihaz kaydı (FCM) — oturum** (v17: gönderim `worker` süreciyle bağlıdır; FCM anahtarı yoksa bildirimler yalnız uygulama içi kutuda — §16.4)
- `POST /push/device` `{token*(10–4096 karakter), platform*(android|ios|web), app_version?}` → `201 {id, platform, app_version, created_at, updated_at}`. Aynı token'la tekrar çağrı güvenlidir (güncelleme); token başka kullanıcıdaysa bu kullanıcıya devredilir (aynı telefonda hesap değişimi).
- `DELETE /push/device` gövde `{token}` ya da `?token=` → `{message, removed: 0|1}` (yalnız kendi token'ı). Çıkışta çağırın.
- Girişte ve FCM token yenilendiğinde `POST` edin. (Eski web-push uçları `/push/vapid-public-key`, `/push/subscribe`, `/push/unsubscribe` yalnız web paneli içindir.) **(v16)** `POST /push/subscribe` yalnız **https** ve bilinen tarayıcı push servisi alan adlarını (`fcm.googleapis.com`, `*.push.services.mozilla.com`, `*.notify.windows.com`, `*.push.apple.com`) kabul eder, aksi `400 "Desteklenmeyen bildirim uç noktası."`; kullanıcı başına en çok 20 abonelik (`429`); `unsubscribe` yalnız kendi aboneliğini siler. Mobil uygulama bu uçları kullanmaz (`/push/device`).

---

## 14. Bilinen sınırlar / mobil geliştirici için notlar

- `GET /dashboard-init`, `/appointments`, `/reminders`, `/materials` sayfalamasızdır (tam liste). Büyük veri için ana ekranda `/mobile/home`, listelerde `?from/&to` ve §6 kullanın.
- `GET /projects` satırındaki `paid_amount` (v16) yalnız **çağıranın defterindeki** ödemelerin toplamıdır; `/projects/:id/full` içindeki `payments` ile tutarlıdır. (v15'te tüm defterleri topluyordu — bu davranış değişti: admin artık ortakların defterlerindeki tahsilatı bu alanda görmez.)
- Kullanıcı güncelleme / pasifleştirme uçları yok; kullanıcı silinince oturumu anında düşer (en geç 10 sn; çok süreçli kurulumda).
- Çöp kutusu/geri alma yok: silmeler kalıcıdır.
- Offline: sunucu tarafında senkronizasyon/`updated_since` yok; ağ yokken yazma kuyruğu istemcide tutulmalıdır. İstekler varsayılan olarak idempotent değildir (çift `POST` çift kayıt üretir; `POST /recurring-expenses/:id/apply` hariç); **v17'den itibaren** POST'lara opsiyonel `Idempotency-Key` başlığı gönderilerek güvenli yeniden deneme sağlanır (§15).
- Dosya adresleri (`/uploads/...`) **v16'dan itibaren kimlik ister** (imzalı 10 dk bağlantı ya da Authorization başlığı; §12.1). Eski kalıcı bağlantıları saklamayın.
- Hata mesajlarında iç ayrıntı (SQL, IP, yığın izi) bulunmaz; bozuk JSON gövdesi `400 "Geçersiz JSON gövdesi."` döner. Çoğu `500` yanıtı yalnız `"Sunucu hatası."` içerir.
- WhatsApp otomatik gönderimi Meta'nın 24 saat kuralına tabidir; başarısızlıkta `whatsappUrl` ile kullanıcının kendi WhatsApp'ından gönderim önerilir.

---

## 15. v17–v20 ortak kurallar (yeni uçlar)

Aşağıdaki §15–§19 bölümleri v17–v20'de eklendi; **yalnız-ekleme** kuralıyla, §0–§14'teki hiçbir uç/alan/doğrulama değişmedi. Yeni uçlar hem `/api/...` hem `/api/v1/...` altında aynen çalışır (**yeni istemci `/api/v1` kullanır**). Hata biçimi aynı: `{"error":"Türkçe mesaj"}` (bazı uçlarda ek `code`/`extra` alanları). Yeni alanlar `snake_case`; sürüm bilgisi bloğu (`server`) `camelCase`. Zamanlar ISO-8601 UTC; günler İstanbul takvim günü `YYYY-MM-DD`.

| Konu | Kural |
|---|---|
| Para | **Eski uçlar (§3–§5, §13): TL ondalık. Yeni uçlar (§17, §18 okuma yanıtları, §19): tamsayı KURUŞ (`*_kurus`)**; gösterim metni (`display`, `text`) sunucuda biçimlenir (`₺12.450,00`, `%39,8`, `20 Kas 2026`). Komut kartından uygulanan yazma gövdeleri mevcut REST uçlarındaki gibi ondalık TL kullanır. Oran: yüzde sayısı (20 = %20); metrik oranları baz puan (`bp`, 10000 = %100) |
| KDV | §0'daki "KDV oranı sabit %20" yalnız eski teklif/PDF hesabı için geçerlidir. Fatura/KDV (§17) oranları `GET /vat/rates` tablosundan gelir (doğrulanmamış oran → teyit bayrağı) |
| `Idempotency-Key` | **POST'larda opsiyonel** başlık (8–128 karakter: harf/rakam/`_-:.`). Oturumlu istekte aynı anahtar + aynı istek → ilk **2xx JSON** yanıt aynen döner (`Idempotent-Replay: true`), işlem tekrarlanmaz. Aynı anahtar + farklı yol/gövde → `422`. İşlem sürerken aynı anahtar → `409`. Anahtar **kullanıcı başınadır** (başka kullanıcının anahtarı yanıt sızdırmaz), 48 saat saklanır. Hata (4xx/5xx) yanıtları saklanmaz. Çevrimdışı yazma kuyruğu her kayıt için UUID üretip bunu göndermelidir |
| `/api/v1` | Eski `/api` ile birebir aynı router'lar |
| Hız sınırı | Yeni uçlar genel IP sınırına (15 dk'da 3000) tabidir. Ek: fatura dosyası yükleme kullanıcı başına 15 dk'da 120; yazışma içe aktarma kullanıcı başına 15 dk'da 20 (`IMPORT_RATE_MAX`) |
| Bozuk çok parçalı gövde | Bozuk `multipart/form-data` → `400 "Geçersiz çok parçalı (multipart) istek."` (5xx değil) |
| Sağlık | `GET /health` (API) · `GET /health/worker` (arka plan işleyici; §16.6) |

**Rol matrisi (yeni uçlar; gerçek davranıştan doğrulandı)**

| Uç grubu | admin | muhasebe | ortak | personel | saha |
|---|---|---|---|---|---|
| `GET /config`, `/assistant/prefs`, `/assistant/inbox`, `/assistant/sector-templates`, `/assistant/briefing*`, `/assistant/closure*`, `/assistant/followups`, `/assistant/commands`, `/assistant/actions` | evet | evet | evet | evet | evet (komut/brifing içeriği kısıtlı; §18.1, §19.1) |
| `PATCH /config`, `POST /assistant/sector-templates/apply`, `PUT /assistant/insight-rules` | evet | 403 | 403 | 403 | 403 |
| `/invoices`, `/vat/*` (okuma), `/tax-calendar` (okuma), `/payment-schedule`, `/receivables`, `/message-templates` | evet | evet (admin defteri) | yalnız KENDİ defteri | 403 | 403 |
| `/vat/rates` ve `/vat/withholding-types` yazma, `PUT /tax-calendar/settings`, `/tax-calendar/items|holidays` yazma | evet | evet | 403 | 403 | 403 |
| `/assistant/imports*`, `/conversations`, `/notes`, `/suggestions`, `/consents`, `/customers/:key/*` | evet | evet | evet (yalnız kendi müşterileri) | evet (kendi + paylaşılan) | 403 |
| `/assistant/insights*` | işletme | işletme | yalnız kendi | 403 | 403 |

Başkasının kaydı (ortak A ↔ ortak B) listede görünmez; kimlikle erişim `404`/`403` döner. Kimlik gövdesinden `owner_id`/`org_id`/`user_id`/`created_by` gönderilse bile yok sayılır (sahip her zaman isteği yapan kullanıcı/defterdir).


---

## 16. Yapılandırma, bildirimler ve worker (v17)

### 16.1 `GET /config` — oturumlu herkes (admin, muhasebe, ortak, personel, saha)
Uygulama açılışında ve ön plana dönünce çağrılır; `Cache-Control: no-store`.
```json
{
  "server": { "version": "1.20.0", "apiVersion": 1, "time": "2026-11-20T08:00:00.000Z",
              "minAppVersion": null, "latestAppVersion": null,
              "storeUrls": { "android": null, "ios": null },
              "maintenance": { "enabled": false, "message": null } },
  "org":    { "id": "uuid", "name": "X Control Yapı", "sector_key": "demir_dograma" },
  "brand":  { "name": "X Control Yapı", "logo_url": null, "primary_color": null },
  "sector_dictionary": { "terms": { "customer": "Müşteri", "customers": "Müşteriler", "job": "Proje", "jobs": "Projeler", "offer": "Teklif", "offers": "Teklifler",
                                    "appointment": "Randevu", "appointments": "Randevular", "expense": "Gider", "expenses": "Giderler",
                                    "payment": "Tahsilat", "payments": "Tahsilatlar", "staff": "Usta / ekip", "location": "Montaj adresi", "visit": "Keşif" } },
  "lists": { "service_types": ["…"], "appointment_types": ["Keşif","Montaj","Teslim","Bakım","Diğer"], "expense_categories": ["…"] },
  "settings": { "timezone": "Europe/Istanbul", "briefing_time": "07:30", "closing_time": "18:30" },
  "flags": { "assistant_inbox": true, "assistant_briefing": true, "ai_enabled": false, "ai_chat": false, "ai_notes": false,
             "briefing_ai_polish": false, "wa_import": true, "wa_notification_listener": false }
}
```
- Arayüz metinlerinde `sector_dictionary.terms` kullanılır; **anahtar yoksa istemci kendi varsayılanına düşer**. `flags` içinde olmayan anahtar = KAPALI kabul edilir (kill-switch sunucudan). `wa_import` v19 ile varsayılan **açıktır** (admin kapatabilir); v17'den yükseltilen kurulumda migrasyon bayrağı bir kez açar.
- `lists.*` yalnız **öneridir**: `appointments.type` ve `expenses.category` hâlâ serbest metindir (randevu türü ≤40 karakter doğrulaması aynen); listede olmayan değer gönderilebilir, bilinmeyen değer olduğu gibi gösterilir.
- `server.minAppVersion` doluysa ve uygulama sürümü ondan küçükse istemci "zorunlu güncelleme" ekranı gösterir (sunucu 426 DÖNMEZ; yalnız bilgi). `maintenance.enabled` ise bakım afişi.
- Hatalar: `401`.

### 16.2 `PATCH /config` — YALNIZ admin (`403` diğer roller, ortak dahil)
Kısmi güncelleme; gövde boşsa/bilinmeyen alan varsa `400`. Yanıt: güncel `GET /config` gövdesi.
| Alan | Kural |
|---|---|
| `brand` `{name, logo_url, primary_color}` | birleştirilir. `name` 1–80; `logo_url` `https://…` (≤500) veya `null`; `primary_color` `#RRGGBB` veya `null`. `brand.name` kuruluş adını da günceller |
| `sector_dictionary` `{terms:{anahtar:"Ad"}}` | birleştirilir; anahtar `^[a-z][a-z0-9_]{0,39}$`, değer 1–60 karakter (`<`,`>` yok); değer `null` → terim silinir; en çok 60 terim |
| `service_types`, `appointment_types`, `expense_categories` | bütünüyle değişir; en çok 50 öğe, her biri 1–40 karakter; kırpılır, büyük/küçük harf duyarsız tekilleştirilir |
| `timezone` | geçerli IANA adı (ör. `Europe/Istanbul`) |
| `briefing_time`, `closing_time` | `SS:DD` (kuruluş varsayılanı; kullanıcı kendi tercihini ezer) |

### 16.3 Bildirim tercihleri — `GET|PUT /assistant/prefs` (oturumlu herkes, yalnız kendi)
```json
{ "enabled": true, "tz": "Europe/Istanbul", "morning_enabled": true, "evening_enabled": true,
  "morning_time": "07:30", "evening_time": "18:30",
  "quiet_enabled": true, "quiet_start": "21:30", "quiet_end": "07:00",
  "weekdays": [1,2,3,4,5,6], "channels": { "push": true, "inbox": true },
  "categories": {}, "max_proactive_per_day": 5, "critical_in_quiet": false, "is_default": true }
```
- `PUT` **kısmi** (upsert): yalnız gönderilen alanlar değişir; yanıt güncel tercihlerdir. `morning_time/evening_time: null` → kuruluş varsayılanı. `weekdays` 1=Pzt … 7=Paz (varsayılan Pzt–Cmt, Pazar kapalı). `categories` `{tür:false}` ile o bildirim türü kapatılır. `channels` anahtarları `push|inbox|webpush|email` (bool).
- Saat/gün/`enabled` değişince bugünün bekleyen brifing/kapanış işleri hemen yeniden zamanlanır. Geçersiz değer → `400`. `401`.

### 16.4 Bildirim kutusu — `/assistant/inbox` (yerel bildirim yedeği; FCM kapalıyken de çalışır)
Yalnız çağıranın kendi bildirimleri; gönderim zamanı gelmemiş (sessiz saate ertelenmiş) ve iptal edilmiş olanlar görünmez.
| Yöntem + yol | Açıklama |
|---|---|
| `GET /assistant/inbox?unread=1&limit=30&before=<available_at>` | → `{ "items":[{id,type,title,body,data,priority,status,available_at,created_at,read_at,acked_at}], "unread_count":n, "next_before": ISO \| null }`. En yeni önce; `limit` 1–100; sonraki sayfa `before=next_before` |
| `POST /assistant/inbox/:id/read` · `…/unread` | okundu / okunmadı (idempotent) → öğe |
| `POST /assistant/inbox/read-all` | → `{marked:n}` |
| `POST /assistant/inbox/:id/ack` | istemci bildirimi aldı/açtı (idempotent; okundu da sayılır) → öğe |
| `POST /assistant/test-notification` | kendine test bildirimi (dakikada 1; ikincisi `200`, ilki `201`) → `{id, deduped, fcm_enabled}` |
- `status`: `beklemede` (FCM kapalı ya da henüz gönderilmedi) · `gonderildi` · `basarisiz`. İstemci için önemli değildir; kutu her durumda gösterilir.
- Başkasının/olmayan id → `404`; geçersiz UUID → `400`.
- Push yükü (FCM `data`, hepsi metin): `type`, `notification_id` + bildirime özel alanlar (iç içe nesneler JSON metni). Bildirime tıklayınca `ack` çağırın. Yerel bildirim yedeği aynı `id`'yi `collapse` anahtarı olarak kullanmalıdır (çift bildirim olmasın).
- Cihaz kaydı değişmedi: `POST|DELETE /push/device` (`device_tokens`). Geçersiz token (FCM `UNREGISTERED`) sunucuda pasifleştirilir; uygulama her açılışta token'ı yeniden kaydetmelidir.
- Bildirim türleri: `briefing` (sabah/haftalık/aylık; §19), `closure` (akşam kapanışı ve hatırlatma; §19), `reminder` (hatırlatma ve randevu öncesi; §19.4), `tax_reminder` ve `receivable_reminder` (§17; yalnız admin/muhasebe/ortak), `offer` (yeni teklif; admin/muhasebe), `test`. (v17'de `briefing`/`closure` yer tutucu metindi; v20'den itibaren gerçek içerik taşır, `data.placeholder` kalktı.)

### 16.5 Sektör şablonları
| Yöntem + yol | Roller | Açıklama |
|---|---|---|
| `GET /assistant/sector-templates` | oturumlu | → `[{key,name,description,dictionary,service_types,appointment_types,expense_categories,is_default}]` (genel, tadilat_insaat, demir_dograma, klima_teknik_servis, kuafor_berber, nakliye, temizlik) |
| `POST /assistant/sector-templates/apply` `{key, mode?}` | **yalnız admin** | şablonu kuruluş ayarlarına uygular. `mode`: `replace` (varsayılan; sözlük+listeler şablondakiyle değişir) · `merge` (listeler birleşir, mevcut terimler korunur). Marka korunur. **Mevcut randevu/gider/teklif kayıtlarına dokunulmaz.** → `{applied, config}` (`config` = güncel `GET /config`). `404` bilinmeyen şablon, `400` eksik/geçersiz |

### 16.6 Worker sağlığı — `GET /health/worker` (herkese açık, izleme için)
`{"status":"ok|stale|down","last_tick_age_seconds":3,"overdue_jobs":0}` — `ok` → `200`; `stale`/`down` → `503`. Oturumlu **admin** ayrıca `workers[]`, `queue{queued,running,overdue,failed_24h}`, `fcm_enabled` görür.

### 16.7 Yan etkiler / uyumluluk (v17)
- Yeni teklif geldiğinde (mevcut davranış) admin/muhasebe için bildirim kutusuna `type:"offer"` öğesi de düşer (`data:{type,id}`); aynı teklif aynı kullanıcıya tek bildirim üretir.
- Hiçbir mevcut uç/alan/doğrulama değişmedi. Eski `/api/...` yolları çalışmaya devam eder.


---

## 17. Fatura takibi, KDV, vergi takvimi, tahsilat planı, mesaj şablonları (v18)

Genel: `/api` (= `/api/v1`), `Authorization: Bearer <jwt>`, hatalar `{ "error": "Türkçe mesaj" }` (+ bazı uçlarda `code`). Tüm POST uçları `Idempotency-Key` başlığını destekler (dosya yüklemede anahtar + içerik uzunluğu eşleşmesi aranır; çoklu parça gövdelerde güvenli yeniden deneme için her yüklemede yeni anahtar kullanın).
Para: **tamsayı kuruş** (`*_kurus`). Oran: yüzde sayısı (20 = %20). Tarih: `YYYY-MM-DD`. Dönem: `YYYY-AA` (aylık) / `YYYY-Qn` (3 aylık).
Yetki: admin/muhasebe tam (muhasebe = işletme/admin defteri); ortak yalnız KENDİ defteri; personel/saha her uçta 403; anonim 401. Başkasının kaydı 404.

### 17.1 Teyit bayrağı (zorunlu gösterilecek)
Doğrulanmamış her oran/tarih/tevkifat için cevaplarda `needs_confirmation: true` ve nedenler (`confirmation.reasons[]` / `confirmation_reasons[]`) döner.
Arayüz "mali müşavire teyit edin" rozetini göstermelidir. Hiçbir oran/tarih koda gömülü değildir; veri olarak tohumlanır, `verified=false` doğar, değişince `verified=false`'a düşer.
Bu uygulama fatura KESMEZ; takip eder, KDV'yi kodla hesaplar, muhasebeciye aktarır. Hukuki/mali tavsiye değildir.

### 17.2 Faturalar `/invoices`
- `GET /invoices?direction=giden|gelen&status=a,b&period=YYYY|YYYY-AA|YYYY-Qn&from=&to=&due_from=&due_to=&overdue=1&unpaid=1&project_id=&customer_id=&offer_id=&q=&limit=&offset=` → dizi; `limit`/`offset`/`q` verilirse `X-Total-Count` başlığı da döner.
- `POST /invoices` gövde: `direction` (giden|gelen), `issue_date`, `invoice_type` (e-fatura|e-arsiv|kagit|gider-pusulasi|serbest-meslek|mustahsil|diger — kod değerleri `invoice_type_label` ile gelir), `invoice_no`, `ettn`, `counterparty`, `counterparty_tax_id` (VKN 10/TCKN 11), `matrah_kurus` (KDV HARİÇ) ya da `tutar_kurus` (KDV DAHİL), `kdv_oran` (yoksa varsayılan oran), `kdv_kurus` (belgedeki KDV; hesapla farkı >5 kuruş ise 400 `kdv_mismatch` + `expectedKdvKurus`, `accept_mismatch:true` ile kabul), `tevkifat` ("4/10" | {pay,payda} | `tevkifat_oran`), `kdv_istisna_nedeni`, `kdv_indirilebilir`, `status` (taslak|kesildi|gonderildi|odendi|iptal), `due_date`, `customer_id`, `project_id`, `payment_id`, `expense_id`, `note`.
  Cevap: `matrah_kurus, kdv_kurus, tevkifat_kurus, tevkifat_oran, tutar_kurus, odenecek_kurus, overdue, files[], warnings[{code,message}], confirmation{needed,reasons[]}`.
  409 `vat_period_locked` kilitli döneme yazılamaz.
- `GET /invoices/:id`, `PATCH /invoices/:id` (tutar alanları değişince yeniden hesaplanır), `DELETE /invoices/:id` (yalnız taslak/iptal).
- `POST /invoices/:id/mark-paid` `{paid_at?, method?: Havale|Nakit|Kredi Kartı|Çek|Senet, create_payment?: true}` → bağlı bekleyen plan satırları kapanır (`schedule_items_closed`); `create_payment` yalnız projeli giden faturada payments (TL) yazar.
- `POST /invoices/:id/files` (multipart `file`; pdf/png/jpg/jpeg/webp/gif/heic/heif, ≤15 MB, en çok 10; içerik imzası denetlenir) → `file_url` İMZALI URL. `GET/DELETE /invoices/:id/files/:fileId`.
- `GET /invoices/summary?period=` — giden/gelen KDV toplamları.
- `GET /invoices/export?period=&format=csv|xlsx[&direction=&include=all]` — muhasebeci sütunları: Tarih, Belge Türü, Belge No, ETTN, Yön, Karşı Taraf Unvan, VKN/TCKN, Matrah, KDV Oranı (%), KDV, Tevkifat Oranı, Tevkifat Tutarı, Genel Toplam, Ödenecek, Para Birimi, Proje Kodu, Açıklama, Durum, Vade, İndirilebilir KDV (E/H), Dönem, Teyit Gerekli (E/H). CSV: UTF-8 BOM, `;`, CRLF, ondalık virgül, gg.aa.yyyy; `=+-@` ile başlayan metinler `'` ile etkisizleştirilir. Başlık `X-Needs-Confirmation: true`.

### 17.3 KDV `/vat`
- `GET /vat/rates` → `{rates[], withholding_types[], disclaimer}` (hepsinde `needs_confirmation`). Düzenleme (admin/muhasebe): `POST|PATCH|DELETE /vat/rates[/:id]`, `/vat/withholding-types[/:id]`; oran/pay-payda değişirse `verified=false`; `verified:true` doğrular (kim/ne zaman kaydedilir).
- `GET /vat/periods?year=&type=aylik|uc_aylik` (devir zinciriyle), `GET /vat/periods/:ym` → `hesaplanan_toplam_kurus, tevkifat_giden_kurus, hesaplanan_kurus, indirilecek_kurus, indirilemeyen_kurus, kdv2_kurus, onceki_devreden_kurus, net_kurus, odenecek_kurus, devreden_kurus, due_date, status(acik|kilitli), tahmini:true, needs_confirmation, confirmation_reasons[], belge_sayisi, oran_kirilimi`.
- `POST /vat/periods/:ym/calculate` (anlık görüntü), `PATCH /vat/periods/:ym {manual_carry_in_kurus, note}`, `POST …/lock`, `POST …/unlock` (409 durum uyuşmazlığı). Kilitli dönemde KDV'yi etkileyen fatura değişikliği 409.
- `GET /vat/periods/:ym/export?format=csv|xlsx` (KDV dönem özeti, `;` + BOM). `GET /vat/insights` (M7 faturasız tahsilat, M8 KDV son gün uyarısı).

### 17.4 Vergi takvimi `/tax-calendar`
- `GET /tax-calendar?asOf=&days=&from=&to=&statu=sahis|limited|…` → `{items[{key,title,kind,period_label,nominal_date,due_date,shifted,shift_reasons,days_until,needs_confirmation,confirmation_reasons}], statu, statu_source, disclaimer, needs_confirmation_count}`. Son gün hafta sonu/resmî tatilde sonraki iş gününe kaydırılır (arife yarım gün iş günüdür).
- `GET|PUT /tax-calendar/settings` (`tax_status`, `vat_period_type`; PUT admin/muhasebe). `GET|POST|PATCH|DELETE /tax-calendar/items[/:id]` (kural `{freq:monthly|quarterly|yearly, day|"last", period_offset_months, dates[]}` ya da tek `due_date`; `confidence`, `source`, `verified`). `GET|POST|PATCH|DELETE /tax-calendar/holidays[/:day]`.
- Ortak okuyabilir, düzenleyemez.

### 17.5 Tahsilat planı + alacak
- `GET /payment-schedule?project_id=&status=&…`, `POST /payment-schedule {project_id|offer_id|invoice_id, kind: taksit|vade|bakiye|cek|senet, amount_kurus, due_date, method, instrument_no, bank, note}`, `POST /payment-schedule/generate {project_id, total_kurus, count≤60, first_due, kind, interval_days?}` (kuruş artığı SON taksitte), `GET|PATCH|DELETE /payment-schedule/:id`, `POST /payment-schedule/:id/mark-paid {paid_at?, create_payment?, payment_id?, method?}`. Durum: bekliyor|odendi|iptal; `effective_status: gecikti` türetilir (saklanmaz).
- `GET /receivables/aging?asOf=&project_id=` → `{buckets{notDue,"0-30","31-60","61-90","90+"}{count,totalKurus,items}, totalKurus, overdueKurus, overdueCount, overdueItems[], sources}` (planlı fatura çift sayılmaz). `GET /receivables/overdue?min_days=`.

### 17.6 Mesaj şablonları `/message-templates`
- `GET /message-templates[?category=teklif|randevu|odeme|tesekkur&tone=nazik|orta|kesin&all=1]`, `GET /variables`, `POST` (özel), `POST /:id/clone` (sistem şablonunu özelleştir), `PATCH|DELETE /:id` (sistem şablonu 403). Sözdizimi `{değişken}`, `{ad|e/i/de/den/in/ile/upper/title}`, `[[isteğe bağlı blok]]`.
- `POST /message-templates/:id/render {customer_id|offer_id|project_id|schedule_id|invoice_id|appointment_id, vars?, phone?, opt_out?}` → `{text, whatsappUrl, whatsappAppUrl, phone, missing[], complete, urlTooLong, context, variables, warnings[]}`. `whatsappUrl = https://wa.me/90532…?text=<encodeURIComponent>`; mobil `whatsapp://send?phone=…&text=…`. Gönderim kullanıcının dokunuşuyla yapılır (otomatik gönderim yok).

### 17.7 Bildirimler (A1 kuyruğu, yalnız admin/muhasebe/ortak)
- `tax_reminder`: veri `{route:"/vergi-takvimi", itemKey, dueDate, period, daysUntil, needsConfirmation, estimatedPayableKurus?}`; T−7/3/1/0, tatil/hafta sonu kayması gövdede belirtilir.
- `receivable_reminder`: veri `{daysOverdue, suggestedTemplateKey (odeme_nazik|odeme_orta|odeme_kesin), …}`; eşikler −1,0,3,7,14,30,60,90 gün.
- dedupeKey kullanıcıyı içerir. Gönderim ve yeniden deneme worker sürecindedir (§16.6). İşler: `tax.plan` (günlük 03:45 İstanbul), `tax.remind`, `receivable.remind`.


---

## 18. Komut çubuğu ve yazışma içe aktarma (v19)

Kapsam: kural tabanlı Türkçe komut çubuğu (LLM yok, ücretli servis yok) ve WhatsApp yazışması içe aktarma + not/öneri çıkarma. Tüm uçlar `Authorization: Bearer <jwt>` ister, `/api/assistant` altındadır (`/api/v1/assistant/...` de çalışır). Hata gövdesi: `{ "error": "mesaj", ... }`.

### 18.1 Temel kurallar
- **Yazma komutu doğrudan uygulanmaz.** Önce `ai_actions` kartı (`status=onerildi`) üretilir; kullanıcı onaylayınca mevcut iş mantığı (REST uçları) aynı yetki/sahiplik kurallarıyla çağrılır.
- **Yasak komutlar** (silme, rol/yetki/şifre değişikliği, müşteriye mesaj gönderme, teklif/proje tutarı değiştirme) kart üretmez: `kind:"answer"`, `refused:true`.
- Rol matrisi: `saha` finans (tahsilat, gider, ödeme, alacak), randevu oluşturma, teklif durumu ve müşteri arama komutlarını kullanamaz (403 / reddedilir); `ortak` yalnız kendi müşterilerini görür/eşleştirir; `personel` kendi + paylaşılan teklifleri; `admin`/`muhasebe` hepsini.
- Para: sunucuda kuruş (bigint) hesaplanır; yanıtta kuruş (`*_kurus`) ve biçimli metin birlikte gelir. Yazma gövdeleri mevcut REST uçlarındaki gibi ondalık TL kullanır.
- Zaman: tüm tarih mantığı Europe/Istanbul; "yarın", "haftaya salı", "15 Kasım", "öğleden sonra 3", "14.30" vb. çözülür.

### 18.2 Komut çubuğu
#### POST /assistant/commands
Gövde: `{ "text": "yarın 10'da Ahmet Yılmaz'a keşif randevusu ekle", "choices": { ... }? }` (text ≤ 500 karakter).

Yanıt `kind` alanına göre:
- `answer` — okuma sonucu ya da ret. `{ kind, intent, text, data?, refused?, reason?, chips }`. `data` kapsam içi sayı/liste (ör. `total_kurus`, `items[]`).
- `action_card` — yazma önerisi: `{ kind, action: Card }` (aşağıda).
- `clarify` — eksik/belirsiz alan; **kart oluşmaz**: `{ kind, intent, reason, message, questions:[{field, type:"choice"|"text"|"date"|"time", label, options:[{value,label}]}], chips }`. İstemci cevabı `choices` ile aynı metni yeniden gönderir: `{ text, choices:{ customer_key:"5321110000" } }`. `choices` anahtarları niyete göre beyaz listededir, biçimi doğrulanır, `customer_key` kullanıcının havuzunda olmak zorundadır.

Desteklenen niyetler: `appointment.create|reschedule|cancel`, `reminder.create`, `payment.add`, `expense.add`, `offer.status`, `note.add` (yazma); `query.agenda`, `query.appointments`, `query.collections`, `query.expenses`, `query.receivables`, `customer.search` (okuma); `forbidden`, `unknown`.

#### Card
```
{ id, origin:"command_bar"|"import"|"system", intent, risk, status, text,
  summary, fields:[{key,label,type,value,display,editable,options?}], ambiguities:[], warnings:[],
  result, error, undo:{available,until,reason},
  created_at, expires_at, decided_at, applied_at, undone_at }
```
Durumlar: `onerildi → onaylandi → uygulandi | hata`; `reddedildi`; `geri_alindi`; `suresi_doldu` (kart 24 sa). Geri alma penceresi 10 dk (`ASSISTANT_UNDO_WINDOW_SEC`), yalnız geri alınabilir niyetlerde (`undo.available`).

#### Diğer uçlar
| Uç | Açıklama |
|---|---|
| GET /commands/chips | Role uygun örnek komut önerileri `{chips:[...]}` |
| GET /actions?status=&limit= | Kullanıcının kartları |
| GET /actions/:id | Tek kart (başkasının kartı 404) |
| PATCH /actions/:id `{fields:{...}}` | Kartı düzenle (yalnız `editable` alanlar, doğrulanır; yalnız `onerildi`) |
| POST /actions/:id/confirm | Uygula. Aynı anda iki istek: biri 200, diğeri 409. `Idempotency-Key` desteklenir. 60 sn içindeki aynı parametreli kart tekilleştirilir |
| POST /actions/:id/reject | Reddet |
| POST /actions/:id/undo | Geri al (pencere içinde) |

Hata kodları: 400 geçersiz girdi, 403 rol yetkisiz, 404 yok/kapsam dışı, 409 durum çakışması/süre doldu/zaten uygulandı, 422 uygulama doğrulaması (ör. dolu saat çakışması), 429 hız sınırı.

### 18.3 Yazışma içe aktarma (KVKK)
Veri yalnız bu sunucuda işlenir; üçüncü tarafa gitmez. Rol: admin, muhasebe, ortak, personel (saha 403).

1. `GET /imports/consent-notice` → `{version, title, text[], checkbox}`. Metin kullanıcıya gösterilip onay alınır.
2. `POST /imports` — `multipart/form-data`: alan **`file`** (.txt veya .zip), `consent=true`, `consent_version=<version>`, isteğe `customer_key`, `title`, `owner_sender`. Ya da JSON `{ text, source:"share", consent, consent_version }` (paylaş/pano; tek mesaj olabilir). Yanıt 201 **önizleme**: `{id, status:"onizleme", file, stats{messages,participants..}, participants, is_group, suggested_owner_sender, candidates[], customer, already_imported, single_message, warnings[], preview_messages{first,last}, suggestion_counts, consent, expires_at}`. Henüz hiçbir mesaj kaydedilmez; önizleme 24 sa sonra silinir.
3. `POST /imports/:id/confirm` `{ owner_sender, customer_key?, offer_id?, project_id?, title?, include_group? }` → 201 `{already:false, conversation_id, inserted, duplicates, suggestions_created, import}`. Tekrar onay 200 `{already:true}`. `customer_key` verilmezse önizlemedeki en iyi eşleşme kullanılır; `null` gönderilirse müşteriye bağlanmaz. Grup sohbeti `include_group:true` olmadan 400.
4. `GET /imports`, `GET /imports/:id`, `DELETE /imports/:id?keep_notes=1` (mesajlar/öneriler silinir; kabul edilmiş notlar `keep_notes` ile kalır).

Yükleme güvenliği: uzantı + sihirli bayt kontrolü, `IMPORT_MAX_UPLOAD_MB` (25) sınırı → 413, bellekte işlenir (diske yazılmaz), zip: yol geçişi/mutlak yol/şifreli/sahte boyut/CRC/zip bombası reddi (400), kullanıcı başına hız sınırı `IMPORT_RATE_MAX` (varsayılan 20 / 15 dk → 429; biçimli yanıt `{error:"Çok fazla içe aktarma denemesi…"}`), NUL baytlı/HTML içerikli metin reddi.

Desteklenen biçimler: Android ve iOS, TR/EN, 12/24 saat, gün-ay-yıl / ay-gün-yıl, çok satırlı mesajlar, sistem/medya/silinmiş satırları, Unicode yön işaretleri. Tekilleştirme: (dakika, gönderen, tür, metin) özeti; aynı/örtüşen dışa aktarım yalnız yeni mesajları ekler.

#### Konuşmalar, notlar, öneriler
| Uç | Açıklama |
|---|---|
| GET /conversations?customer_key= | Konuşma listesi (sahibe göre; admin hepsi) |
| GET /conversations/:id, /conversations/:id/messages?limit=&offset= | Detay / mesajlar |
| PATCH /conversations/:id `{title}` · DELETE /conversations/:id | Başlık / sil |
| GET /suggestions?status=beklemede\|kabul\|red\|all&kind=not\|hatirlatma\|randevu&conversation_id=&customer_key= | Öneriler; her biri kaynak mesaja bağlı (`msg_*`) |
| PATCH /suggestions/:id `{status:"kabul"\|"red", fields?}` | Karar. `not` kabul → `ai_notes` (author=rule); `hatirlatma` kabul → uygulanır (geri alınabilir); `randevu` kabul → **onay kartı** döner, ayrıca onaylanır. Tekrar aynı karar 200 `{replayed:true}`; çelişen karar 409 |
| GET/POST /notes, PATCH/DELETE /notes/:id | Notlar (author=user/rule, etiket, bağlantı) |
| GET /customers/:key/summary, /conversations, /notes | Müşteri kartı verisi |
| DELETE /customers/:key/data | Müşterinin tüm yazışma/not verisini sil |
| GET/POST /consents, POST /consents/:id/withdraw | Aydınlatma/rıza kayıtları (`aydinlatma\|acik_riza\|veri_isleme_ack\|ticari_ileti`) |

`:key` = müşteri anahtarı (telefonun son 10 hanesi). Başka ortağın müşterisi için tüm müşteri uçları 404 döner.

#### Saklama ve silme
- Ham mesaj metni `IMPORT_RAW_TEXT_DAYS` (180) sonra silinir (kabul edilen notlar kalır); yazışma `IMPORT_RETENTION_DAYS` (730) sonra silinir; bekleyen öneriler/kartlar süre dolunca `suresi_doldu`. Günlük `housekeeping` işi çalıştırır.
- Müşteri kaydı silinince (`DELETE /customers/:id`) veritabanı tetikleyicisi o telefon anahtarına ait yazışma, içe aktarma ve notları siler.
- Denetim kaydı mesaj içeriği taşımaz.

### 18.4 Ortam değişkenleri (v19)
`IMPORT_MAX_UPLOAD_MB`, `IMPORT_MAX_MESSAGES`, `IMPORT_RATE_MAX`, `IMPORT_RETENTION_DAYS`, `IMPORT_RAW_TEXT_DAYS`, `ASSISTANT_RAW_TEXT_DAYS` (komut ham metni), `ASSISTANT_UNDO_WINDOW_SEC`, `ASSISTANT_INTERNAL_BASE` (onay için döngü-içi adres; varsayılan gelen bağlantının yerel adresi).


---

## 19. Brifing, akşam kapanışı, müdür önerileri, hatırlatma, takipler (v20)

Tüm yollar `/api/assistant/...` ve `/api/v1/assistant/...` altında aynen çalışır (yeni istemci `/api/v1`).
Hata biçimi: `{"error":"Türkçe mesaj"}`. Kimlik: `Authorization: Bearer <token>`. Alanlar `snake_case`. Zamanlar ISO-8601 UTC; günler İstanbul takvim günü `YYYY-MM-DD`.
**Para her yerde KURUŞ TAMSAYISI** (`*_kurus`); gösterim metni (`display`, `text`) sunucuda biçimlenir: `₺12.450,00`, `%39,8`, `20 Kas 2026`. Oranlar baz puan (`bp`, 10000 = %100).
Tüm metinler kural/şablon tabanlıdır (LLM yok); terimler `GET /config` → `sector_dictionary.terms` ile uyumludur (sabit sektör ifadesi yok).

### 19.1 Brifingler (oturumlu herkes; yalnız kendi)
| Yöntem + yol | Açıklama |
|---|---|
| `GET /assistant/briefing/today[?refresh=1]` | Bugünün sabah brifingi. Henüz üretilmediyse (08:00 öncesi / kaçırıldı / bildirim kapalı) **anında üretilir** (`live:true`, `generated_by:"on_demand"`). `refresh=1` yeniden üretir |
| `GET /assistant/briefings?type=morning\|weekly\|monthly\|evening&limit=20` | Geçmiş (en yeni önce; `limit` 1–100). Geçersiz `type` → `400` |
| `POST /assistant/briefings/:id/read` | Okundu işaretle (`read_at`). Başkasının/olmayan → `404`, geçersiz uuid → `400` |

Brifing nesnesi: `{id, kind, date, title, text, data, generated_by, generated_at, read_at}`. `title`/`text` doğrudan gösterilebilir; `data` yapılandırılmış karttır (`data.v = 1`; **bilinmeyen `blocks[].type` yok sayılmalı**).

#### Sabah brifingi (`kind:"morning"`) — örnek (admin)
```json
{
  "id": "uuid", "kind": "morning", "date": "2026-11-25",
  "title": "Günaydın Admin: 3 randevu, 1 geciken tahsilat, 1 takip",
  "text": "Çarşamba, 25 Kas 2026\nRandevular: 14:00 Ahmet Kaya (Montaj, Atatürk Cd. 5); …\nDikkat: 1) Son 90 günde tahsilat oranı %39,8 2) …\nDün tahsilat ₺2.000,00, gider ₺0,00; bu ay net -₺7.450,50.",
  "data": {
    "v": 1, "kind": "morning", "date": "2026-11-25", "weekday": "Çarşamba", "date_text": "25 Kas 2026", "greeting": "Günaydın Admin",
    "role": "admin", "empty": false, "day_kind": null, "holiday": null,
    "stats": { "appointments": 3, "reminders": 1, "followups": 1, "new_requests": 2, "overdue_jobs": 1, "late_collections": 1, "low_stock": 1, "attention": 3, "tomorrow_appointments": 1 },
    "blocks": [
      { "id": "appointments", "type": "appointments", "title": "Bugünün randevuları", "count": 3, "items": [
        { "id": "uuid", "time": "14:00", "scheduled_at": "2026-11-25T11:00:00.000Z", "type": "Montaj", "status": "beklemede", "customer_name": "Ahmet Kaya",
          "customer_phone": "05321234567", "service": "Mutfak", "address": "Atatürk Cd. 5", "offer_id": null, "project_id": "uuid",
          "summary": "14:00 Ahmet Kaya (Montaj, Atatürk Cd. 5)",
          "actions": { "call": "tel:+905321234567", "whatsapp": "https://wa.me/905321234567", "directions": "geo:0,0?q=Atat%C3%BCrk%20Cd.%205" } } ] },
      { "id": "reminders", "type": "reminders", "title": "Hatırlatma ve takipler", "count": 2, "reminders": [ { "id": "uuid", "title": "Ara", "time": "10:30", "overdue": false } ], "followups": [], "quote_waiting": [ { "customer_name": "Ayşe Demir", "age_days": 8 } ] },
      { "id": "attention", "type": "attention", "title": "Dikkat", "count": 3, "items": [
        { "kind": "insight", "insight_id": "uuid", "rule_key": "M2b", "severity": "critical", "title": "Son 90 günde tahsilat oranı %39,8",
          "text": "Son 90 günde başlayan 3 iş için sözleşme toplamı ₺29.000,55; tahsil edilen ₺11.550,00 (%39,8). …", "actions": [ { "type": "screen", "label": "Göster", "screen": "receivables", "params": {} } ] } ] },
      { "id": "new_requests", "type": "new_requests", "title": "Yeni teklifler", "count": 2, "oldest_age_hours": 49, "items": [ { "customer_name": "Can Öz", "summary": "Can Öz — Mutfak", "actions": { "call": "tel:+90…", "whatsapp": "https://wa.me/90…", "directions": null } } ] },
      { "id": "overdue_jobs", "type": "overdue_jobs", "title": "Geciken işler", "count": 1, "items": [ { "id": "uuid", "code": "PRJ-T3", "customer_name": "Su Yıldız", "days_overdue": 8 } ] },
      { "id": "collections", "type": "collections", "title": "Geciken tahsilatlar", "count": 1, "total_kurus": 1245055, "total_text": "₺12.450,55", "items": [ { "project_id": "uuid", "customer_name": "Ahmet Kaya", "balance_kurus": 1245055, "balance_text": "₺12.450,55", "age_days": 10, "actions": { "call": "tel:+90…", "whatsapp": "https://wa.me/90…", "directions": null } } ] },
      { "id": "low_stock", "type": "low_stock", "title": "Düşük stok", "count": 1, "items": [ { "id": "uuid", "name": "Silikon", "unit": "adet", "stock": 2, "threshold": 5 } ] },
      { "id": "money", "type": "money", "title": "Para özeti", "text": "Dün tahsilat ₺2.000,00, gider ₺0,00; bu ay net -₺7.450,50.",
        "yesterday": { "collected_kurus": 200000, "expense_kurus": 0 }, "month": { "collected_kurus": 755000, "expense_kurus": 1500050, "net_kurus": -745050 } },
      { "id": "question", "type": "question", "title": "Tek soru", "kind": "set_end_date", "project_id": "uuid", "text": "Kapı Müşteri 4 iş: teslim tarihi boş. Girelim mi?",
        "chips": [ { "label": "Bugün", "value": "2026-11-25" }, { "label": "Bu hafta", "value": "2026-11-28" }, { "label": "Sonra", "value": null } ],
        "apply": { "method": "PATCH", "path": "/api/projects/<id>/dates", "body_field": "end_date" } },
      { "id": "missed_closure", "type": "missed_closure", "title": "Dünün kapanışı", "date": "2026-11-24", "unresolved": 2, "text": "Dün kapanış yapılmadı; 2 randevu sonucu belirsiz.", "action": { "screen": "closure", "date": "2026-11-24" } }
    ]
  },
  "generated_by": "job", "generated_at": "2026-11-25T04:30:01.000Z", "read_at": null, "live": false
}
```
Blok görünürlüğü **role göre sunucuda süzülür** (istemci süzmez):
- **admin / muhasebe**: tümü (işletme kapsamı). **ortak**: yalnız kendi kayıtları ve kendi defteri; başkasının verisi yok. **personel**: finans (`money`, `collections`) ve insight (`attention` yerine basit maddeler) yok. **saha**: yalnız kendine atanan randevular (+ varsa geciken işleri); `money`, `collections`, `low_stock`, `new_requests`, `attention`, `question` YOK ve kartta hiç tutar geçmez.
- **Boş gün**: `data.empty:true`, `title` "Günaydın Ayşe: bugün sakin bir gün", `text` anlamlı bir cümle ("Sakin bir gün: 2 teklif yanıt bekliyor; birkaçını aramak için uygun bir zaman." ya da yeni müşteri için arama önerisi). Blok listesi yine `appointments` içerir (`count:0`).
- **Pazar / resmî tatil**: `day_kind:"pazar"|"tatil"`, `holiday:"<ad>"` (resmî tatil tablosu kuruluysa). Kısa form: yalnız randevular, hatırlatma/takipler ve **kritik** dikkat maddeleri; boşsa "Bugün dinlenme günü; kayıtlı iş ya da hatırlatma yok. İyi dinlenmeler."
- Bildirim (`type:"briefing"`, A1 kutusu): `title` = brifing başlığı, `body` kısa (ilk randevu / ilk dikkat maddesi), `data:{kind:"morning", date, briefing_id, stats}`. Tıklayınca `GET /assistant/briefings` ya da `briefing/today` ile kart açılır.
- Zamanlama: sabah işi kullanıcının `morning_time` (A1 varsayılan 07:30; tercihle değişir) saatinde, Pzt–Cmt (kullanıcı tercihine göre). Aynı gün iş iki kez çalışsa **tek** bildirim.

#### Haftalık / aylık müdür raporu (`kind:"weekly"|"monthly"`; yalnız admin/muhasebe/ortak)
- `weekly`: Pazartesi sabah saatinin 10 dk sonrası; kapsadığı hafta bir önceki Pzt–Paz. `period_start` = o haftanın Pazartesi'si. `monthly`: ayın 1'i; `period_start` = raporlanan ayın 1'i.
- `weekly.data`: `{v:1, kind:"weekly", period:{from,to,label}, money:{collected_kurus, expense_kurus, net_kurus, home_expense_kurus, prev_net_kurus, net_change_kurus, note}, offers:{new,quoted,accepted,rejected,conversion_recent_bp,conversion_prev_bp}, late_collections:{count,total_kurus,items[]}, next_7_days:{empty_days,empty_dates,days[]}, top_actions:[öneri]}`.
- `monthly.data`: `{v:1, kind:"monthly", period:{month:"2026-11",label}, money:{collected_kurus, expense_kurus, net_kurus, home_expense_kurus, prev_*…, net_change_kurus, note}, expense_breakdown:{by_category[],by_scope{}}, by_service[], receivables:{total_kurus,delivered_total_kurus,buckets}, offers:{…}, top_actions:[öneri]}`.
- `top_actions[]` = `{insight_id, rule_key, severity, title, text, why:[metrics], actions:[…]}` (en çok 3; "dayanak" metrikleriyle). `text` okunabilir özet (örn. aylık raporda "Tahsilat ₺7.550,00 …"). Kişisel giderler net hesabına girmez (`note`). Ortak yalnız kendi defterinin özetini alır.
- Bildirim: `type:"briefing"`, `data:{kind:"weekly"|"monthly", date, briefing_id}`.

### 19.2 Akşam kapanışı (oturumlu herkes; yalnız kendi)
| Yöntem + yol | Açıklama |
|---|---|
| `GET /assistant/closure/today[?refresh=1]` | Bugünün soruları + gün sonu özet kartı (yanıt verilmediyse soru listesi 30 dk'dan eskiyse yeniden üretilir) |
| `POST /assistant/closure/answers` | Yanıtları işler. Gövde: `{date?, answers:[…], free_note?, finish?}` |

Zamanlama (A1 varsayılanı 18:30; tercihle değişir): `closure.evening` işi bildirim atar (`type:"closure"`, `data:{kind:"evening", date, questions:n}`); **yanıt gelmediyse TEK nazik hatırlatma 20:30'da** (`data.kind:"evening_nudge"`), sonra ısrar yok. Yanıt verildiyse hatırlatma gelmez. Ertesi sabah brifingi yanıtlanmamış kapanışı "Dünün kapanışı" bloğuyla gösterir.

#### `GET /closure/today` — örnek
```json
{
  "date": "2026-11-25", "status": "pending", "completeness": 0, "closed_at": null,
  "questions": [
    { "id": "appt:uuid", "kind": "appointment", "text": "14:00 Ahmet Kaya (Montaj, Atatürk Cd. 5): nasıl geçti?", "skip_key": null, "skippable": true,
      "context": { "appointment_id": "uuid", "time": "14:00", "customer_name": "Ahmet Kaya", "customer_phone": "05321234567", "type": "Montaj", "offer_id": null, "project_id": "uuid" },
      "options": [ { "value": "yapildi", "label": "Yapıldı", "follow_up": [ { "value": "teklif_verilecek", "label": "Teklif verilecek" }, { "value": "anlastik", "label": "Anlaştık" }, { "value": "dusunecek", "label": "Düşünecek" }, { "value": "sonra_ara", "label": "Sonra ara" } ] },
                   { "value": "ertelendi", "label": "Ertelendi" }, { "value": "iptal", "label": "İptal" } ], "answer": null },
    { "id": "money", "kind": "money", "text": "Bugün tahsilat ya da gider oldu mu?", "skip_key": "money", "skippable": true,
      "context": { "recorded_collected_kurus": 0, "recorded_expense_kurus": 0, "payments_count": 0, "expenses_count": 0 },
      "options": [ { "value": "yok", "label": "Yok" }, { "value": "tahsilat", "label": "+ Tahsilat" }, { "value": "gider", "label": "+ Gider" } ], "answer": null },
    { "id": "stage:uuid", "kind": "stage", "text": "Ahmet Kaya iş: Teslim → Tamamlandı?", "options": [ { "value": "evet", "label": "Evet" }, { "value": "hayir", "label": "Hayır" }, { "value": "sonra", "label": "Sonra" } ], "context": { "project_id": "uuid", "from": "Teslim", "to": "Tamamlandı" }, "skippable": true, "answer": null },
    { "id": "cost:uuid", "kind": "cost", "text": "Ahmet Kaya (PRJ-1) için masraflar tamam mı?", "options": [ { "value": "tamam", "label": "Tamam" }, { "value": "eksik_var", "label": "Eksik var" } ], "context": { "project_id": "uuid" }, "skippable": true, "answer": null },
    { "id": "tomorrow", "kind": "tomorrow", "text": "Yarın 1 randevu, 1 tanesinde adres eksik. Hazır mıyız?", "options": [ { "value": "tamam", "label": "Tamam" }, { "value": "hatirlat", "label": "+ Hatırlat" } ], "context": { "count": 1, "missing_address": 1, "first_time": "10:00" }, "skippable": true, "answer": null }
  ],
  "free_note": null, "note_prompt": "Not düşmek istediğiniz bir şey var mı?", "skip_label": "Atla",
  "summary_card": {
    "title": "Gün sonu özeti", "date": "2026-11-25", "date_text": "25 Kas 2026",
    "appointments": { "total": 2, "done": 1, "postponed": 0, "cancelled": 0, "open": 1 },
    "money": { "collected_kurus": 0, "expense_kurus": 0 }, "new_requests_today": 0, "followups_created": 0,
    "tomorrow": { "count": 1, "first": "10:00 Ahmet Kaya (Montaj)" }, "completion": { "total": 5, "answered": 0, "skipped": 0, "percent": 0 },
    "text": "2 randevu: 1 yapıldı, 1 sonuçsuz. Tahsilat ₺0,00, gider ₺0,00. Yarın: 1 randevu (ilk: 10:00 Ahmet Kaya (Montaj))."
  },
  "closure_proposals": []
}
```
Kurallar: **en çok 5 soru**, sıra veri boşluğunu kapatma değerine göre (randevu sonucu ≤3 → para → aşama → maliyet onayı → yarın hazırlığı). Her soru **atlanabilir**. Aynı soru son 14 günde 2 kez atlandıysa sorulmaz. `money`/`cost` yalnız admin/muhasebe/ortak; saha yalnız `appointment` ve `tomorrow` (satış alt seçenekleri olmadan) alır. `status`: `pending|partial|done|skipped`.

#### `POST /closure/answers`
```json
{ "date": "2026-11-25",
  "answers": [
    { "question_id": "appt:uuid", "choice": "yapildi", "follow_up": "teklif_verilecek" },
    { "question_id": "money", "choice": "tahsilat", "amount_kurus": 150000, "project_id": "uuid" },
    { "question_id": "stage:uuid", "choice": "evet" },
    { "question_id": "cost:uuid", "choice": "tamam" },
    { "question_id": "tomorrow", "choice": "hatirlat" },
    { "question_id": "…", "skipped": true } ],
  "free_note": "Ahmet Bey'i haftaya ara", "finish": true }
```
Yanıt `200`: `{applied:[…], closure_proposals:[…], log:{…GET gövdesi…}, summary_card:{…}}`.
- **Doğrudan uygulananlar** (`applied[]`; asistanın kendi alanı, geri alınabilir): randevu durumu (`Yapıldı→tamamlandı`, `Ertelendi→ertelendi`, `İptal→iptal`), takip kaydı (`teklif_verilecek` yarın · `dusunecek` +2 gün · `sonra_ara` +3 gün), maliyet onayı (`projects.cost_confirmed_at`), "yarın hazırlık" hatırlatması (08:00).
- **Öneriler** (`closure_proposals[]`; **başka alanlara yazar, kullanıcı onayıyla uygulanır**): tahsilat/gider kaydı, teklif durumu "Kabul Edildi" (`anlastik`), proje aşaması, ertelenen randevuya yeni tarih. Her öneri `apply:{method,path,body,needs?}` ile **mevcut uca** çağrı tarifidir (`needs`: istemcinin tamamlaması gereken alanlar). Sunucu bunları kendiliğinden **yazmaz**.
```json
{ "type": "payment_create", "question_id": "money", "label": "Tahsilat ekle", "amount_kurus": 150000, "project_id": "uuid",
  "apply": { "method": "POST", "path": "/api/projects/<id>/payments", "body": { "amount": 1500, "paid_at": "2026-11-25T09:00:00.000Z", "method": "Nakit" }, "needs": [] } }
```
- **İdempotent**: aynı yanıt tekrar gönderilebilir (takip/hatırlatma yinelenmez). Yanıt değişirse eski takip iptal edilir.
- Hatalar `400` (Türkçe mesaj): bilinmeyen soru, geçersiz `choice`/`follow_up`, `amount_kurus` pozitif tam sayı değil ya da para sorusu dışında, gelecek gün, 3 günden eski gün, bilinmeyen alan. `finish:true` ya da tüm sorular yanıt/atlama → `status` `done` (hiçbiri yanıtlanmadıysa `skipped`). Yanıttan sonra `kind:"evening"` brifing kaydı (gün sonu özeti) saklanır.

### 19.3 Müdür önerileri (insight) — yalnız admin, muhasebe, ortak (`403` personel/saha)
Kapsam: admin+muhasebe → **işletme** (ortak verisi karışmaz); ortak → **yalnız kendi** verisi. Hesaplama son 30 dk içinde yapıldıysa önbellekten; sabah brifingi ve haftalık/aylık işler tazeler.
| Yöntem + yol | Açıklama |
|---|---|
| `GET /assistant/insights?status=acik\|ertelendi\|kapatildi\|uygulandi\|all&severity=info\|warn\|critical&limit=50` | → `{items:[insight], count}`; varsayılan `status=acik`; kritik önce, sonra skor. Geçersiz değer `400` |
| `GET /assistant/insights/:id` | Tek öneri (başka kapsam/olmayan `404`) |
| `POST /assistant/insights/:id/snooze` `{days: 1–90}` ya da `{until: ISO}` | Ertele (`status:"ertelendi"`); süre dolunca ya da şiddet yükselince yeniden açılır |
| `POST /assistant/insights/:id/dismiss` | Kapat; koşul sürse de **14 gün** açılmaz |
| `POST /assistant/insights/:id/applied` | "Aksiyonu uyguladım"; 7 gün susar |
| `POST /assistant/insights/:id/feedback` `{verdict:"yanlis"\|"alakasiz"\|"yararli", note?≤500}` | `yanlis/alakasiz` → kapanır + 30 gün susar (kural kalibrasyonu için kaydedilir); `yararli` açık kalır |
| `POST /assistant/insights/refresh` | Kapsamı hemen yeniden hesapla |

Insight örneği:
```json
{
  "id": "uuid", "rule_key": "M2", "rule_title": "Tahsilat gecikmesi", "severity": "warn", "status": "acik", "snoozed_until": null,
  "title": "Ahmet Kaya: ₺12.450,55 tahsilat bekliyor, 10 gündür açık",
  "body": "Ahmet Kaya için iş 'Teslim' aşamasına geçeli 10 gün oldu; kalan bakiye ₺12.450,55 (sözleşme+ilave ₺20.000,55, tahsil edilen ₺7.550,00). Ahmet'e nazik bir hatırlatma göndermek ya da aramak iyi olabilir.",
  "entity": { "type": "project", "id": "uuid" },
  "evidence": {                                  // "Neden?" ekranı: sayısal dayanak
    "rule": "M2", "severity": "warn", "why": "M2: …",
    "metrics": [ { "key": "balance", "label": "Kalan bakiye", "value": 1245055, "unit": "kurus", "display": "₺12.450,55" },
                 { "key": "age", "label": "Aşamaya geçeli gün", "value": 10, "unit": "days", "display": "10 gün" } ],
    "refs": [ { "type": "project", "id": "uuid", "label": "PRJ-T1 · Ahmet Kaya" } ] },
  "actions": [
    { "type": "whatsapp.template", "label": "Hatırlatma taslağı", "template_code": "odeme_hatirlatma", "phone": "05321234567", "text": "Merhaba Ahmet, …", "url": "https://wa.me/905321234567?text=…" },
    { "type": "call", "label": "Ara: Ahmet", "phone": "05321234567", "tel_uri": "tel:+905321234567" },
    { "type": "reminder.create", "label": "Hatırlat", "endpoint": { "method": "POST", "path": "/api/reminders" }, "body": { "title": "Tahsilat: Ahmet Kaya", "remind_at": "2026-11-26T06:00:00.000Z", "project_id": "uuid", "note": "Müdür önerisinden" } },
    { "type": "open", "label": "Aç", "entity_type": "project", "id": "uuid" } ],
  "first_seen_at": "…", "last_seen_at": "…", "occurrences": 1, "feedback": null, "closed_reason": null
}
```
- `evidence.metrics[].unit`: `kurus|count|bp|days|hours|date|text`; **`value` ham sayı, `display` hazır Türkçe metin**.
- Aksiyon tipleri (`actions[].type`): `reminder.create` (gövdeyi `POST /api/reminders`'a aynen gönderin), `call` (`tel_uri`), `whatsapp.template` (`template_code` ∈ `odeme_hatirlatma|teklif_takip|is_bilgilendirme|randevu_teyit`; hazır `text` ve `wa.me` `url`; gönderim istemcidedir), `appointment.create` (`endpoint` + `body` taslağı + `suggested_dates`), `call_list` (`items:[{name,phone,tel_uri,offer_id,age_days}]`), `open` (`entity_type`: `project|offer`), `screen` (`screen` + `params`: istemci ekranına yönlendirme). Bilinmeyen tip yok sayılmalı.
- `status` geçişleri: `acik → ertelendi|kapatildi|uygulandi`; koşul ortadan kalkınca sunucu `kapatildi` (`closed_reason:"kosul_ortadan_kalkti"`), kural kapatılınca `kural_kapali`.

#### Kural kataloğu
`rule_key`: M1 nakit açığı · M2 tahsilat gecikmesi · M2b tahsilat oranı · M3 düşük marj (hizmet türü) · M3b marj düşüşü · M4 boş takvim · M5 teklif dönüşümü · M6 bekleyen teklif yaşı · M6b cevapsız talep · M6c keşif sonrası teklif yok · M7 faturasız tahsilat (**`invoices` tablosuna bağlı**; v18 ile birlikte kurulu → `aktif`) · M8 KDV son günü (**`vat_periods` tablosuna bağlı**; v18 ile `aktif`, yalnız işletme kapsamı; tahmini tutar `odenecek_kurus`, kilitli dönem hariç) · M9 gider sıçraması · M10 müşteri bağımlılığı · M11 geciken iş · M12 satış hattı zayıf · M13 mevsim kıyası. Para her yerde kuruş; kişisel (`scope='ev'`) giderler işletme hesaplarına girmez.

#### `GET|PUT /assistant/insight-rules` — YALNIZ admin (`403` diğerleri)
`GET` → `{calibration_mode:false, rules:[{rule_key,title,description,group,enabled,status:"aktif"|"kapali"|"bagimli",dependency:{requires:["invoices"],available:false,missing:["invoices"]}|null,scope:"business,user",params:{…},defaults:{…},feedback:{yanlis:n,…}}]}`.
`PUT` kısmi: `{rules:[{rule_key, enabled?, params?:{ad:tamsayı}}], calibration_mode?:bool}`; `params` yalnız kuralın bilinen alanlarını kabul eder (0–1.000.000.000 tam sayı; para **kuruş**, oran **bp**), aksi `400`. Yanıt güncel `GET` gövdesi. Bağımlılığı karşılanmayan kural `status:"bagimli"` olur ve çalışmaz (v18 kurulu olduğundan M7/M8 normalde `aktif` döner).

### 19.4 Hatırlatma uzantısı
Mevcut `/api/reminders` (GET/POST/PATCH/DELETE) **aynen** çalışır; POST artık opsiyonel `recurrence` (`daily|weekdays|weekly|monthly`, aksi `400`) kabul eder; yanıtta yeni alanlar (`recurrence, snoozed_until, snooze_count, done_at, source, fired_at, offer_id, appointment_id`) görünür. `PATCH {status:"tamamlandi"}` tekrarlı hatırlatmada bir sonraki oluşumu ayrı satır olarak ekler (yerel saat korunur).
| Yöntem + yol | Açıklama |
|---|---|
| `POST /assistant/reminders/:id/snooze` `{preset:"15m"\|"1h"\|"tomorrow"}` ya da `{minutes: 5–1440}` | Ertele (yarın = 09:00 İstanbul). `remind_at` taşınır, `snooze_count` artar; → güncel hatırlatma. Bekleyen değilse `409`, başkasınınki `403` (admin/muhasebe hariç), geçersiz `400` |
| `POST /assistant/reminders/:id/complete` | Tamamla (idempotent) → `{reminder, next|null, already}` |
- Bildirim (`type:"reminder"`): vade gelince **tek** bildirim; `data:{kind:"reminder", reminder_id, actions:[{id:"done"|"snooze_15m"|"snooze_1h"|"snooze_tomorrow", label, method, path, body?}]}` (bildirim eylemleri bu uçlara gider). Ertelenen hatırlatmanın eski zamanlı işi sessizce atlanır.
- **Randevu öncesi** (`type:"reminder"`): önceki akşam **18:00** "Yarın N randevu" (`data.kind:"appointment_eve"`, kullanıcı başına gün başına TEK) ve **1 saat önce** (`data.kind:"appointment_hour"`, `data.actions:{call,whatsapp,directions}`); iptal/tamamlanan/taşınan randevu için atılmaz. Alıcı: randevunun atanan kullanıcısı ve sahibi.

### 19.5 Takipler (yalnız kendi)
`GET /assistant/followups?status=acik|yapildi|ertelendi|iptal|all` → `{items:[{id,kind,title,due_date,status,customer_name,customer_phone,offer_id,project_id,source}]}` ·
`POST /assistant/followups` `{title (1–200), due_date:"YYYY-MM-DD", kind?:"ara"|"teklif"|"tahsilat"|"bilgi"|"diger", offer_id?, project_id?, customer_name?, customer_phone?}` → `201` ·
`POST /assistant/followups/:id/done` · `POST /assistant/followups/:id/snooze` `{days:1–60}`. Başkasının takibi `404`.

### 19.6 Notlar / uyumluluk
- Yalnız ekleme: hiçbir mevcut uç/alan değişmedi; tek davranış farkı A1'in yer tutucu brifing/kapanış bildirimlerinin gerçek içerikle değişmesidir (`data.placeholder` kalktı; `data.kind` = `morning|evening|weekly|monthly`).
- Brifing/kapanış/hatırlatma işleri A1 kuyruğunda (`briefing.morning|weekly|monthly`, `closure.evening`, `closure.nudge`, `reminder.fire`); hepsi idempotent (`dedupeKey` kullanıcıyı içerir), kaçırılan eski saatte bildirim atmaz.
- Brifing/kapanış sunucuda doğrudan başka alanlara yazmaz: yan etkisi olan her şey `closure_proposals` olarak istemciye döner (komut çubuğunun `ai_actions` onay kartları §18'dedir ve ayrı bir mekanizmadır).
- Bilinen sınırlar: Türkçe ek üretimi yalnız k→ğ yumuşamasını uygular; M7 `invoices.odenecek_kurus` (tevkifat düşülmüş) ile tahsilatı karşılaştırır, yalnız `giden` ve iptal/taslak olmayan faturalar sayılır; M9 pay değil tutar karşılaştırır; proje aşaması geçiş tarihi (`stage_changed_at`) göç öncesi kayıtlarda göç anıdır.

