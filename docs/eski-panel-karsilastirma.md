# Eski Panel (v10) - Yeni Flutter Uygulaması Karşılaştırması

Tarih: 2026-11-20. Yalnız rapor; kod değiştirilmedi.

## 0. Kaynaklar ve yöntem

- Eski panel: kaynağı kayıp ama derlenmiş çıktısı BULUNDU: `/mnt/user-data/outputs/admin-panel-v10.zip` (TanStack Start/React). `server/_ssr/*.mjs` dosyaları okunabilir (minify değil); 8 ekranın tamamı (teklifler, projeler, müşteriler, randevular, finans, raporlar, kullanıcılar, stok) + giriş + kabuk/menü satır satır okundu. API tabanı `https://api.controlx.com.tr/api`.
- Ekran görüntülerinden 4'ü açıldı (Teklifler listesi, Finans Genel Bakış, tarih aralığı + son 12 ay grafiği, Alacaklarım); içerikleri kodla birebir örtüştü. Kalan görüntüler ayrıca incelenmedi; kod ana kaynak alındı.
- Eski backend uçları: `backend/src/routes/*` (grep ile tam liste). `admin-panel.jsx` (v1 prototip) yalnız `/offers` çağırıyor, kapsam dışı.
- Yeni uygulama: `/home/claude/xc_app/lib` içinde repository + ekran dosyaları okundu; DEMO değil gerçek HTTP repository çağrısı arandı (`main.dart` varsayılanı demo=false). Durum 'VAR' = ekran + gerçek uç çağrısı; 'YARIM' = kısmen; 'YOK' = ne ekran ne çağrı.
- Önemli: eski v10 paneli belge, galeri, rapor uçları, aktivite, hatırlatıcı, push, config, şifre değiştirme, oturum kapatma-hepsi, ayarlar kullanmıyordu. Bunlar 'eski backend yeteneği' olarak aşağıda ayrıca işaretli (Belge/Medya, Ayarlar, Oturum).

## 1. Özet tablo (modül x durum)

| Modül | VAR | YARIM | YOK | Toplam |
|---|---:|---:|---:|---:|
| Oturum | 6 | 0 | 1 | 7 |
| Kullanıcılar | 1 | 1 | 5 | 7 |
| Panel | 2 | 4 | 0 | 6 |
| Teklifler | 12 | 3 | 4 | 19 |
| Projeler | 11 | 3 | 2 | 16 |
| Müşteriler | 5 | 2 | 1 | 8 |
| Randevular | 6 | 0 | 1 | 7 |
| Finans | 8 | 5 | 3 | 16 |
| Raporlar | 1 | 1 | 4 | 6 |
| Stok | 3 | 0 | 1 | 4 |
| Belge/Medya | 3 | 0 | 2 | 5 |
| Ayarlar | 2 | 2 | 4 | 8 |
| **Toplam** | **60** | **21** | **28** | **109** |

## 2. Tam envanter

| # | Eski özellik | Uç | Yeni uygulama | Dosya / not |
|---|---|---|---|---|
| | **Oturum** | | | |
| A1 | Giriş (e-posta/şifre) | POST /auth/login | VAR | features/auth/presentation/login_screen.dart |
| A2 | Çıkış | (yerel) + DELETE /push/device | VAR | core/auth/session.dart |
| A3 | Oturum yenileme / süresi dolunca girişe dönüş | GET /auth/me, POST /auth/refresh | VAR | core/auth/session.dart (yeni; eskide yoktu) |
| A4 | Tüm cihazlardan çıkış | POST /auth/logout-all | VAR | features/settings/presentation/settings_screen.dart |
| A5 | Kendi şifresini değiştirme | PATCH /users/me/password | YOK | Ekran/çağrı yok (grep 'me/password' boş). Backend hazır |
| A6 | Profil: ad/e-posta/rol gösterimi | GET /auth/me | VAR | Ayarlar > Hesap kartı (düzenleme yok; backend de yok) |
| A7 | Rol bazlı menü ve rota koruması (admin/muhasebe/personel/saha/ortak) | capabilities | VAR | core/router/routes.dart RouteGuard, nav_items.dart |
| | **Kullanıcılar** | | | |
| K1 | Kullanıcı listesi (ad, e-posta, rol, katılım) | GET /users | YOK | settings_repository.dart boş iskelet; yalnız paylaşım adayı için çağrılıyor |
| K2 | Yeni kullanıcı (ad, e-posta, şifre >=6, rol) | POST /users | YOK | Ekran yok. Backend hazır (ortak yalnız saha/personel) |
| K3 | Kullanıcı silme (kendini silemez) | DELETE /users/:id | YOK | Ekran yok. Backend hazır |
| K4 | Başka kullanıcının şifresini sıfırlama | PATCH /users/:id/password | YOK | Eski panelde de UI yoktu; backend hazır (v16) |
| K5 | Rol atama / rol değiştirme | POST /users (rol) ; PATCH yok | YOK | Oluştururken rol seçimi eski panelde vardı; sonradan değiştirme backend'de de yok |
| K6 | Ortak (ayrı firma) izolasyonu ve kendi ekibini yönetme | /users, tüm uçlar | YARIM | İzolasyon sunucuda (uygulama aynı uçları kullanır) VAR; ortağın ekip yönetimi ekranı YOK |
| K7 | Paylaşım / atama için kullanıcı listesi | GET /users, /projects/:id/collaborators | VAR | lib/features/jobs/data/jobs_repository.dart |
| | **Panel** | | | |
| P1 | Toplam teklif + bekleyen sayısı kartı | GET /dashboard-init | YARIM | Bugün ekranında yalnız 'yeni teklif talepleri' sayısı; toplam yok |
| P2 | Bekleyen randevu kartı | dashboard-init / mobile/home | VAR | home_sections.dart HomeStatTiles (bugünkü randevu) |
| P3 | Bu ayki ciro kartı | dashboard-init | YARIM | 'Tahsilat' kartı alacak proje sayısı; bu ay ciro Finans/Raporlar'da |
| P4 | Aktif proje kartı | dashboard-init | YARIM | 'Geciken iş' var; aktif proje toplamı yalnız Raporlar'da |
| P5 | Son 8 teklif listesi | dashboard-init | YARIM | Yeni talepler listesi var (home_sections.dart), son 8 değil |
| P6 | Yenile + kart tıklayınca ilgili sayfa | — | VAR | pull_to_refresh, StatTile onTap |
| | **Teklifler** | | | |
| T1 | Durum çipleri (6 durum, sayı rozetli) | GET /offers?status= | YARIM | lib/features/jobs/presentation/jobs_screen.dart: çipler var, çip başına sayı yok |
| T2 | İsim/telefon arama | GET /offers?q= | VAR | sunucu taraflı |
| T3 | Sayfalama ('daha fazla göster') | limit/offset | VAR | paged_list_body.dart |
| T4 | Onay kutulu çoklu seçim + 'görünenleri seç' | — | YOK | grep checkbox/selection: yok |
| T5 | Toplu durum değiştirme | PATCH /offers/bulk-status | YOK | Repository'de çağrı yok. Backend hazır |
| T6 | Toplu silme | DELETE /offers/bulk | YOK | Repository'de çağrı yok. Backend hazır |
| T7 | Yeni teklif (ad*, telefon*, hizmet*, e-posta, bölge, mesaj) | POST /offers | VAR | lib/features/jobs/presentation/offer_form_screen.dart |
| T8 | Yeni teklifte 'mevcut müşteriden seç' arama | dashboard-init.customers | YOK | Formda müşteri seçici yok (yinelenen kayıt riski) |
| T9 | Teklif detay + bilgi düzenleme (ad, tel, e-posta, hizmet, bölge, mesaj, not) | GET/PATCH /offers/:id | VAR | offer_detail_screen.dart |
| T10 | Durum değiştirme (tekli) | PATCH /offers/:id/status | VAR | setOfferStatus |
| T11 | Teklif silme (onaylı) | DELETE /offers/:id | VAR | rol kuralı jobs_access.dart |
| T12 | Kalem editörü: açıklama/adet/birim fiyat/KDV dahil-hariç, canlı toplam | POST /quotes/:id | VAR | quote_editor_screen.dart (en çok N kalem, kopyala) |
| T13 | Kaydet -> durum 'Teklif Verildi' | POST /quotes/:id | VAR | sunucu davranışı |
| T14 | WhatsApp + e-posta ile PDF gönder | POST /quotes/:id/send | VAR | send_result_view.dart (kısmi başarı 207/502 yönetimi) |
| T15 | Gönderim tarihleri (WhatsApp/e-posta) | GET /offers/:id | VAR | Geçmiş sekmesi |
| T16 | Kabul -> proje otomatik, bilgi notu | PATCH status | VAR | offerToProject |
| T17 | Derin bağlantı ?offer= | — | VAR | /jobs/offers/:id |
| T18 | Kayıtlı şablondan kalem yükleme / şablon kaydetme-silme | GET/POST/DELETE /quote-templates | YARIM | Yükleme VAR; şablon oluşturma/silme YOK |
| T19 | Takip kodu / müşteri takip bağlantısı | GET /track/:code | YARIM | Kod gösteriliyor; bağlantı için --dart-define=TRACK_BASE_URL şart, /config okunmuyor |
| | **Projeler** | | | |
| J1 | Aşama çipleri (5 aşama) + müşteri/hizmet arama | GET /projects | VAR | jobs_lists.dart |
| J2 | 'Devam eden' / 'Tamamlanan' ayrı bölümler | — | YARIM | Aşama çipi var; ayrı başlık gruplaması doğrulanmadı |
| J3 | Kart: tutar/ödenen/kalan + aşama ilerleme çubuğu | GET /projects | VAR | jobs_cards.dart |
| J4 | Aşama değiştirme | PATCH /projects/:id/stage | VAR | setStage (hızlı 'sonraki aşama') |
| J5 | Toplam tutar düzenleme | PATCH /projects/:id/amount | VAR | project_detail_screen.dart |
| J6 | Başlangıç/bitiş tarihi (+bitişi temizle) | PATCH /projects/:id/dates | VAR | setDates |
| J7 | Müşteri adı / hizmet / notlar formu | PATCH /projects/:id | YARIM | UI yalnız Not düzenliyor; müşteri adı ve hizmet düzenleme UI yok (repo desteği var) |
| J8 | Görev ekle / durum (bekliyor-devam-tamam) / sil | POST/PATCH/DELETE tasks | YARIM | Ekle, durum, sil VAR; 'devam ediyor' ara durumu: yalnız Bekliyor/Tamamlandı yap düğmeleri |
| J9 | Göreve kişi atama | POST tasks assigned_user_id | VAR | AddTask atanan seçici |
| J10 | Proje içinden ödeme ekleme (tutar, yöntem, not) | POST /projects/:id/payments | VAR | FinanceNav.addPayment |
| J11 | Proje içinden gider ekleme | POST /expenses (project_id) | VAR | FinanceNav.addExpense |
| J12 | Ödeme/gider kaydında sahip (owner_id) seçimi + 'Kim ne kadar aldı' özeti | POST payments/expenses owner_id; GET collaborators | YOK | owner_id yalnız okunuyor, hiç yazılmıyor; özet kartı yok (ortak akışı) |
| J13 | İlave iş ekle / sil | POST/DELETE extras | VAR | project_detail_screen.dart |
| J14 | Proje paylaşımı (kullanıcıyla) ekle/kaldır | GET/POST/DELETE /shares | VAR | resource_sections.dart SharesSection |
| J15 | Projeyi silme (yalnız admin) | DELETE /projects/:id | YOK | grep deleteProject boş. Backend hazır |
| J16 | Yeni proje (elle) | POST /projects | VAR | project_form_screen.dart (eskide yoktu) |
| | **Müşteriler** | | | |
| M1 | Liste + ad/telefon/bölge arama | GET /customers?q= | VAR | customers_screen.dart |
| M2 | Satırda teklif sayısı ve proje sayısı | — | YARIM | Yalnız biri gösteriliyor (proje varsa proje, yoksa teklif) |
| M3 | Satırda sözleşme toplamı ve ödenen | total_contracted/total_paid | YARIM | Model okuyor; liste satırında GÖSTERİLMİYOR, yalnız detayda |
| M4 | Detay: iletişim, ilk iletişim, teklif+proje geçmişi | GET /customers/:key | VAR | customer_detail_screen.dart |
| M5 | Yeni müşteri (ad, tel, e-posta, bölge, not) | POST /customers | VAR | +yinelenen telefon uyarısı |
| M6 | Düzenle (yalnız manuel eklenen) | PATCH /customers/:key | VAR | tekliften gelende açıklayıcı hata |
| M7 | Sil (yalnız manuel) | DELETE /customers/:key | VAR | geri al penceresiyle |
| M8 | Müşteri birleştirme | — | YOK | Eski panelde ve backend'de de yok |
| | **Randevular** | | | |
| R1 | Liste, tarihe göre sıralı | GET /appointments | VAR | takvim + gün listesi (appointments_screen.dart) |
| R2 | Durum çipleri filtresi (beklemede/onaylandı/tamamlandı/iptal) | — | YOK | Yalnız 'Yalnız benim' süzgeci; durum çipi yok |
| R3 | Yeni randevu (tür, tarih-saat, not) | POST /appointments | VAR | tür/atanan/bağlı kayıt/çakışma uyarısı eklenmiş |
| R4 | Düzenle (tarih, not) | PATCH /appointments/:id | VAR | appointment_form_screen.dart |
| R5 | Durum değiştirme | PATCH | VAR | detay ekranı + geri al |
| R6 | Sil | DELETE | VAR | appointment_ui.dart |
| R7 | Keşif planlama (tekliğe/projeye bağlama) | appointment offer_id/project_id | VAR | link_picker_sheet.dart; tekliften tek dokunuşla 'keşif planla' kısayolu yok |
| | **Finans** | | | |
| F1 | Ödemeler listesi (proje, tarih, yöntem, tutar) | GET /projects/payments/all | VAR | payments_tab.dart |
| F2 | Ödemelerde başlangıç/bitiş tarih aralığı | — | YARIM | Yalnız ay gezintisi; serbest aralık yok |
| F3 | Ödemelerde yöntem filtresi (Havale/Nakit/Kredi Kartı) | — | YOK | payments_tab.dart'ta yok |
| F4 | Ödeme düzenle (tutar, yöntem, tarih, not) / sil | PATCH/DELETE /projects/payments/:id | VAR | payment_form_screen.dart |
| F5 | Ödeme özet kutuları (seçili aralık / bu ay / tüm zamanlar) | — | YARIM | Ay toplamı var; 'tüm zamanlar' yok |
| F6 | Giderler listesi + kapsam çipleri | GET /expenses | VAR | expenses_tab.dart |
| F7 | Gider ekle/düzenle/sil (kategori, tutar, tarih, proje, not) | POST/PATCH/DELETE /expenses | VAR | expense_form_screen.dart |
| F8 | Kapsam etiketleri Ev / Dükkan / İşletme | scope ev|dukkan|genel | YARIM | Etiketler Kişisel/İşletme/Genel olarak değişmiş; eski 'İşletme'=genel idi. Kullanıcıya karışık gelebilir |
| F9 | Sabit gider: ekle/düzenle/sil/'Bu ay ekle' | /recurring-expenses | VAR | recurring_tab.dart (+pasif) |
| F10 | Alacaklarım (toplam, tamamlanan işten alacak) | dashboard-init | VAR | receivables_section.dart + vade + WhatsApp hatırlatma |
| F11 | Proje bazlı kâr/zarar | payments+expenses | VAR | lib/features/reports/presentation/reports_screen.dart (Raporlar sekmesinde) |
| F12 | Genel bakış aylık/yıllık: ciro, gider, net kâr, son 12 ay grafiği | /reports/revenue, /profit | VAR | lib/features/reports/presentation/money_chart.dart |
| F13 | Bu ay / bu yıl net kâr + önceki döneme % değişim | — | YARIM | Net kâr var; % delta rozeti yok |
| F14 | Seçili tarih aralığında kâr/zarar | — | YOK | Serbest tarih aralığı seçici yok |
| F15 | Gider kategori dağılımı | — | YOK | Pasta/dağılım yok |
| F16 | Ev/Dükkan/İşletme gider kartları (bu ay + genel) | — | YARIM | Ev giderleri satırı Raporlar'da; üç kartlı kırılım yok |
| | **Raporlar** | | | |
| Q1 | Toplam / Kabul / Reddedilen / Kabul oranı | GET /reports/summary | YARIM | Kabul oranı VAR; reddedilen sayısı ayrı gösterilmiyor |
| Q2 | Aylık/yıllık teklif üretimi çubuk grafiği (teklif vs kabul) | dashboard-init | YOK | Raporlar gelir-gider odaklı |
| Q3 | Kabul oranı trend çizgisi | — | YOK |  |
| Q4 | Hizmet dağılımı (pasta) | GET /reports/service-distribution | VAR | reports_screen.dart |
| Q5 | 'Son teklifler' (10) listesi | — | YOK |  |
| Q6 | Rapor dışa aktarma (CSV/Excel/PDF), yazdır | — | YOK | Eski panelde de yok; yalnız fatura/KDV dışa aktarma var |
| | **Stok** | | | |
| S1 | Liste, ± ile hızlı miktar | GET/PATCH /materials | VAR | stock_screen.dart |
| S2 | Düşük stok uyarısı (eşik) | low_stock_threshold | VAR | filtre + Bugün kartı |
| S3 | Malzeme ekle/düzenle/sil (ad, birim, stok, eşik, not) | POST/PATCH/DELETE | VAR | stock_form_screen.dart |
| S4 | Stok hareket geçmişi | — | YOK | Eski panelde ve backend'de de yok |
| | **Belge/Medya** | | | |
| D1 | Belge/fotoğraf yükle/sil (teklif, proje) | POST/DELETE /documents | VAR | resource_sections.dart (kamera + dosya) |
| D2 | Belge listesi, açma, PDF | GET /documents, imzalı URL | VAR | PDF 10 dk bağlantı; göndermeden önizleme backend'de yok |
| D3 | Proje galerisi (önce/sonra, siteye yayınlama) | /gallery/* | YOK | Eski panelde UI yoktu; backend hazır |
| D4 | Aktivite / denetim günlüğü (kayıt bazlı) | GET /activity/:type/:id | VAR | Geçmiş bölümü |
| D5 | Takip sayfası kararı (müşteri) | /track/:code | YOK | Müşteri yüzü; mobil kapsam dışı olabilir |
| | **Ayarlar** | | | |
| Y1 | Tema, biyometrik kilit, bağlantı denemesi, sürüm | — | VAR | settings_screen.dart (yeni) |
| Y2 | Firma bilgisi / logo / marka / sözlük (admin) | GET/PATCH /config | YOK | Uygulama /config'i hiç okumuyor; marka yerel. Backend hazır |
| Y3 | Teklif şablonu yönetimi | /quote-templates | YOK | Bkz. T18 |
| Y4 | Mesaj şablonları yönetimi | /message-templates | YARIM | Kullanım/render var; ekleme-düzenleme yok |
| Y5 | Ödeme bilgileri (IBAN vb.) | — | YOK | Backend'de ayrı uç bulunamadı (config alanı olabilir; doğrulanmadı) |
| Y6 | Yedek / veri dışa aktarma | — | YOK | Backend'de yok |
| Y7 | Bildirim tercihleri + bildirim kutusu | /assistant/prefs, /inbox | VAR | yeni |
| Y8 | Anlık (push) bildirim | POST/DELETE /push/device | YARIM | FCM yok: NoopPushService; yalnız yerel bildirim |

## 3. Eksikler (öncelikli)

Tahmini iş: S (yarım gün altı), M (1-2 gün), L (3+ gün). 'Backend' sütunu eski sunucuda ucun var olup olmadığını gösterir.

### P0 - Canlıya geçişi engeller
| # | Eksik | İş | Backend |
|---|---|---|---|
| 1 | Kullanıcı yönetimi: liste, ekle (rol seçimi), sil, şifre sıfırla (K1-K5). Bugün personel/saha hesabı açmak için web panel şart; web panel kapatılacaksa mobilden yönetilemez | M | Hazır: GET/POST/DELETE /users, PATCH /users/:id/password (ortak yalnız kendi oluşturdukları) |
| 2 | Kendi şifreni değiştir (A5). Başarıda yanıttaki YENİ jetonu saklamak gerekir (eski jetonlar iptal olur) | S | Hazır: PATCH /users/me/password |
| 3 | Gerçek sunucuya duman testi: docs/CORE-REQUESTS.md 'canlı API'ye duman testi yapılmadı, yalnız DEMO/ScriptedAdapter' diyor. Bu rapor da yalnız kod okumasına dayanır | M | Hazır sunucu |
| 4 | Backend boşluğu: `GET /projects` satırında `balance` yok; istemci ilave işleri bilmeden hesaplıyor -> Alacaklar ve proje kartlarında kalan tutar yanlış çıkabilir | S (backend) | Yok (backend'e eklenmeli) |

### P1 - Eski panelle günlük işi aksatır
| # | Eksik | İş | Backend |
|---|---|---|---|
| 5 | Tekliflerde çoklu seçim + toplu durum + toplu silme (T4-T6) | M | Hazır: PATCH /offers/bulk-status, DELETE /offers/bulk |
| 6 | Projeyi silme, yalnız admin (J15) | S | Hazır: DELETE /projects/:id |
| 7 | Ödeme/gider sahibi (owner_id) seçimi + 'Kim ne kadar aldı' özeti (J12); ortak/ortaklı işlerde para kimin defterine yazıldığı belirsiz kalır | M | Hazır: owner_id gövdesi, GET /projects/:id/collaborators |
| 8 | Yeni teklifte mevcut müşteriden seç (T8); aksi halde yinelenen müşteri | S | Hazır: GET /customers?q= |
| 9 | Finans: ödemelerde tarih aralığı + yöntem filtresi; seçili aralık kâr/zarar (F2, F3, F14) | M | Hazır (istemci tarafı süzme; /reports/profit tarih paramı da var) |
| 10 | Kapsam etiketleri uyumu (F8): Ev/Dükkan/İşletme -> Kişisel/İşletme/Genel; eski 'İşletme' = sunucudaki `genel`. Metinleri eskiyle hizala ya da kullanıcıya açıkla | S | Hazır |
| 11 | Randevularda durum süzgeci (R2) | S | Hazır |
| 12 | FCM push (Y8): arka planda bildirim yok | L | Hazır: POST/DELETE /push/device; Firebase hesabı gerekli (yok) |
| 13 | Takip bağlantısı: `TRACK_BASE_URL` build'e verilmeli ya da /config okunmalı (T19) | S | Yok: /config içinde trackingBaseUrl alanı yok |
| 14 | Proje formunda müşteri adı + hizmet düzenleme (J7) | S | Hazır: PATCH /projects/:id |
| 15 | Müşteri listesinde sözleşme/ödenen/teklif+proje sayıları (M2, M3) | S | Hazır (alanlar zaten geliyor) |

### P2 - İyileştirme
| # | Eksik | İş | Backend |
|---|---|---|---|
| 16 | Rapor: teklif üretimi aylık/yıllık grafik, kabul oranı trendi, reddedilen sayısı, son teklifler (Q1-Q3, Q5) | M | Hazır (dashboard-init / reports/summary statusCounts) |
| 17 | Gider kategori dağılımı, % değişim rozetleri, 3 kapsamlı gider kartları (F13, F15, F16) | M | Hazır (istemci hesabı) |
| 18 | Ayarlar: firma bilgisi/logo/sözlük (GET/PATCH /config), teklif şablonu oluştur/sil, mesaj şablonu yönetimi (Y2-Y4) | L | Hazır: /config, /quote-templates, /message-templates |
| 19 | Proje galerisi, önce/sonra, yayınlama (D3) | M | Hazır: /gallery/* |
| 20 | Panel kartları: toplam teklif, aktif proje, bu ay ciro, son 8 teklif (P1, P3-P5) | S | Hazır |
| 21 | Rapor/liste dışa aktarma CSV/Excel/PDF (Q6) | M | Yok (yalnız /invoices/export ve /vat/periods/:ym/export) |
| 22 | Ödeme bilgileri (IBAN) ayarı (Y5), yedek/dışa aktarma (Y6), stok hareket geçmişi (S4), müşteri birleştirme (M8) | L | Yok (eski panelde de yoktu) |
| 23 | Tekliften 'keşif planla' kısayolu; görev 'devam ediyor' durumu (R7, J8) | S | Hazır |
| 24 | Teklif PDF'i göndermeden önizleme | M | Yok: GET /quotes/:id/pdf (CORE-REQUESTS) |

## 4. Yeni uygulamada olup eski panelde olmayanlar
- Asistan: sohbet/komut çubuğu ve onay kartları, günlük brifing, akşam kapanışı, müdür önerileri (insight), takipler, yazışma içe aktarma (KVKK onaylı), diğer uygulamalardan paylaşım alma.
- Fatura takibi, KDV dönemleri (hesapla/kilitle/dışa aktar), vergi takvimi, tahsilat planı ve vade, alacak yaşlandırma, mesaj şablonları.
- Yerel sabah/akşam bildirimleri, bildirim kutusu, biyometrik kilit, koyu tema, çevrimdışı bandı, geri al (silme sonrası).
- Saha modu (rol bazlı sade ekranlar), randevu takvimi + çakışma uyarısı + atama, hatırlatıcı erteleme/tamamlama.
- Kişisel (ev) giderin işletme kârından ayrılması, WhatsApp'ta alacak hatırlatma, elle proje oluşturma, kaynak bazlı belge/fotoğraf yükleme (kamera), kayıt bazlı aktivite geçmişi, rol bazlı sektör sözlüğü (marka profili).

## 5. Özet
- Toplam madde: 109 | VAR 60 | YARIM 21 | YOK 28
- Eski v10 paneli bulundu (admin-panel-v10.zip, SSR çıktısı okunabilir); 9 menü öğesi, 8 ekran envanterlendi.
- En büyük boşluk: Kullanıcılar ekranı tamamen yok (settings_repository.dart boş iskelet).
- Teklifte toplu seçim/işlem, proje silme, ödeme sahibi (owner_id), tarih aralığı kâr/zarar yok.
- Backend ucu: yukarıdakilerin hemen hepsi için HAZIR; eksik olanlar: projects `balance`, quote PDF önizleme, rapor dışa aktarma.
- P0: (1) Kullanıcı yönetimi, (2) şifre değiştirme, (3) canlı API duman testi, (4) projects `balance` backend alanı.
- Uyarı: Durumlar kod okumasıyla belirlendi; uygulama derlenip çalıştırılmadı.
