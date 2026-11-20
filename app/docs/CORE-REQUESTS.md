
# Çekirdek istekleri: durum (birleştirme sonrası)

Gösterim: [x] uygulandı · [ ] AÇIK (backend / karar / sonraki iş). Bağlantılar `lib/app_wiring.dart` içindedir.

## finance (Para)
- [x] 1. `Glossary.expenseCategories` (+ `fromJson`); `FinanceCategories.options` önce bunu, sonra `expenseCategoryLabels` anahtarlarını, sonra sektör nötr varsayılanları kullanır.
- [x] 2. `GET /projects` modeli: `ProjectRef` `customer_phone` ve sunucu `balance` alanını okur (`remaining` sunucu bakiyesini kullanır; elle paid/extras değişince eski hesap). DEMO satırları `balance` döner.
  - [ ] Backend: gerçek `GET /projects` satırına `balance` (sözleşme + ilave - tahsilat) eklenmesi. Yoksa istemci eski hesabı kullanır (ilave işleri bilmez).
  - [ ] WhatsApp hatırlatmada `/customers?q=` yedeği duruyor (`customer_phone` gelince devre dışı kalır).
- [ ] 3. (Sözleşme) `/recurring-expenses` satır biçimi yazılmadı; finance `{id, category, amount, note, scope, active}` varsayıyor.

## customers / stock / reports
- [x] 1. Riverpod yeniden deneme: `ProviderScope(retry: noProviderRetry)` (`main.dart`) ve test harness'inde `ProviderContainer(retry:)`. Feature'lardaki yerel `retry` ayarları zararsız kaldı.
- [ ] 2. Backend: `GET /customers` satırına `note` ve `source` (`manual|offer`) ekleme önerisi.
- [ ] 3. Backend: `GET /reports/project-profit` (şimdi istemcide `/projects` + `/expenses` birleştirilir).
- [ ] 4. Karar: Raporlar yetkisi sözleşmede A M O **P** (personel dahil); uygulama `showReports = !isField`. Yönetici kararı bekliyor.
- [x] 5. Müşteri/stok alt rotaları feature içinde; `RouteGuard` kök yola göre çalışır.
- [x] 6. `conversationSectionBuilderProvider` → `AssistantConversationSection` bağlandı (müşteri kartında "Yazışmalar ve notlar").

## jobs
- [x] 1. `finance.addPayment/addExpense`: jobs proje ekranı `FinanceNav` ile gider; kayıtta proje yenilenir. Geçici `finance_links.dart` SİLİNDİ.
- [ ] 2. Backend: `GET /quotes/:offerId/pdf` (göndermeden önizleme).
- [~] 3. `share_plus` eklendi ve Fatura/KDV dışa aktarmasına bağlandı. Jobs PDF/dosya paylaşımı hâlâ bağlantı kopyala/aç (sonraki iş: `SharePlus` ile bağlantı/dosya).
- [ ] 4. `/config` içinde `trackingBaseUrl` (şimdi `--dart-define=TRACK_BASE_URL`).
- [ ] 5. Backend: teklif yanıtına `project_id` ("Projeye çevir" şimdi `GET /projects?q=` süzmesi kullanıyor).
- [x] 6. `field_home_body.dart` 47px taşması giderildi (etiket + rozet tek `Text.rich`, `Flexible`).

## invoices_vat
- [x] 1. `invoicesVatDemoRoutes(db)` `demo_adapter.dart`'ta kayıtlı.
- [x] 2. `share_plus` eklendi; `exportSharerProvider` → `ShareSheetExportSharer`.
- [~] 3. `paymentScheduleBuilderProvider` bağlandı (finans alacak kartı → `PaymentScheduleSection`).
  - [ ] `paymentMethodOptionsProvider` (Çek/Senet) BİLEREK bağlanmadı: `POST /projects/:id/payments` sözleşmede yalnız Havale/Nakit/Kredi Kartı; backend çek/senedi kabul edince bağlanır.
- [ ] 4. Backend boşlukları: vergi takvimi "tamamlandı" alanı (`PATCH /tax-calendar/items/:key`), `GET /customers` satırında `id`, `POST /payment-schedule/generate` `method`, dışa aktarmada `X-Needs-Confirmation`.

## home + appointments
- [x] 1. Yeniden deneme: kök `retry` ayarlandı (bkz. customers/stock/reports 1).
- [ ] 2. Backend: `PATCH /reminders/:id` ile `remind_at` (ertele şimdi POST + PATCH, atomik değil).
- [ ] 3. Doğrula: `PATCH /appointments/:id` null = bağlantı/atama temizleme.
- [ ] 4. `DemoDb.mobileHome` hatırlatıcıları `status`'a göre süzmüyor (home_demo süzüyor; yalnız DEMO).
- [x] 5. Başka ekranlardan randevu formu bağlantıları (`AppointmentsRoutes.newPath`) kullanılabilir durumda.

## assistant
- [x] 1. `assistantDemoRoutes(db)` kayıtlı.
- [ ] 2. Sesle yazma: `speech_to_text` eklenmedi (mikrofon klavye ipucu veriyor). Eklenirse `dictationServiceProvider` override + Android `RECORD_AUDIO` + iOS izin metinleri.
- [x] 3. Saha için `/assistant/briefing|closure|inbox|prefs` açıldı (`RouteGuard`); sohbet/içe aktarma sahada kapalı. Saha Bugün ekranında "Günün brifingi" düğmesi.
- [x] 4. Ayarlar → Bildirimler kartı artık `AssistantPrefsSection` (core'un yerel sabah/akşam anahtarları kaldırıldı).
- [x] 5. Müşteri kartı bağlantısı (bkz. customers 6).
- [x] 6. Bildirim zamanlama: `dailySchedulerProvider` `AssistantBackedDailyScheduler` ile değiştirildi; açılış, giriş, ön plana dönüş ve ayarlardan `AssistantNotificationScheduler.apply()` çalışır (çift bildirim yok). `NotificationPayloads.evening` = `/assistant/closure`.
  - [ ] Gün kısıtlı tercihlerde bildirim 7 gün sonra biter (her açılışta yenilenir).
- [x] 7. Bugün: `InboxBellButton` (AppBar) + `BriefingSummaryCard(showStats: false)` (kendi 4 karolu satırı Bugün'ün `HomeStatTiles`'ı ile çakışmasın diye kapalı).
- [x] 8. Çıkışta: `cancelAll` (oturum) + `chatHistoryStoreProvider.clearAll()` (`AppRoot`).
- [ ] 9. Backend varsayımları (sözleşmeyle doğrulanmalı): `answer.data` biçimi, öneri alanları, `GET /assistant/briefings` biçimi, ayrı `POST /assistant/consents` gövdesi, son 10 hane müşteri arama ucu.
- [ ] 10. iOS Paylaşım Uzantısı Xcode'da elle eklenir (`docs/IOS-BUILD.md`).

## Birleştirme sırasında bulunan ve düzeltilenler
- [x] FAB `Hero` etiketi çakışması (rota atlamalarında "multiple heroes"): `AppScaffold` FAB'ı `HeroMode(enabled: false)` ile sarar.
- [x] `AssistantPrefsSection(shrinkWrap: true)` yükleniyor/hata durumları sınırsız yükseklikte çizilemiyordu (Ayarlar çöküyordu): sabit yükseklikli durumlar + yenilemesiz gövde.
- [x] Bayat test beklentileri: Bugün selamlaması saate göre (Günaydın/İyi günler/...), teklif detayı kimlik yerine müşteri adı, müşteri kartı yazışma başlığı.

## Bilinen açık konular
- Ekran gezintisi testi Ahem yazı tipiyle çalışır (gerçek Inter'den daha geniş); gerçek cihazda taşma olasılığı düşüktür ama cihaz/yazı ölçeği (1.3x+) ayrıca denenmelidir.
- iOS derlemesi bu ortamda yapılamaz.
- Gerçek API sürümü canlı sunucuya karşı DUMAN testi yapılmadı (yalnız DEMO ve ScriptedAdapter ile test edildi).

## settings / finance / customers (eski panel karşılaştırması P0/P1 turu)

### Yapılanlar
- [x] Kullanıcı yönetimi (`/users`, menüde "Kullanıcılar", yalnız admin/ortak; `RouteGuard` + `AppCapabilities.showUsers`): liste/arama/rol süzgeci, ekle, sil (onay; kendini ve son yöneticiyi silme engeli), şifre sıfırla, DEMO uçları.
- [x] Şifre değiştirme (`/settings/password`): yeni jeton `SessionNotifier.adoptToken` ile saklanır (çekirdeğe küçük ekleme). "Tüm cihazlardan çıkış" zaten vardı (Ayarlar > Oturum), teste bağlandı.
- [x] Finans: serbest tarih aralığı (`customPeriodProvider`, `activePeriodProvider`), ödeme yöntemi süzgeci, "Tüm zamanlar", kâr/zarar kartı (negatifse "Zarar"), `owner_id` seçici + "Kim ne kadar aldı", Ev/Dükkan/İşletme etiketleri (sunucu değerleri `ev|dukkan|genel` değişmedi; `ScopeView.label/groupLabel`).
- [x] Müşteriler: `customers_public.dart` → `showCustomerPicker(context)` (Customer? döner) ve liste satırında sözleşme/ödenen/teklif özeti.
- Çekirdek dosyalara dokunuşlar: `core/auth/session.dart` (adoptToken), `auth_models.dart` (showUsers), `router/routes.dart` (Routes.users, changePassword, guard), `router/nav_items.dart` (Kullanıcılar öğesi), `demo/demo_adapter.dart` (settings DEMO rotaları jobs'tan ÖNCE kayıtlı: GET /users artık tam liste döner).

### jobs ajanına (bağlanacak)
- [x] Yeni teklif ve yeni proje formları `showCustomerPicker` ile bağlandı ("Mevcut müşteriden seç"; ad/telefon her zaman, e-posta/bölge/adres müşteride varsa doldurulur; düzenleme formunda yok).
- [x] Paylaşım adayı seçicisi kendisini (`currentUserProvider`) süzer.

### Backend isteği (kendim YAZMADIM; istemci geri düşüşlü)
1. `PATCH /users/:id` `{name?, role?, active?}` (A; kendi rolünü/son admini koru) + `GET /users` satırında `active`, `created_by`; pasif kullanıcı girişi 401. İstemci: `kUserEditApi` (`--dart-define=USER_EDIT_API=true`) kapalıyken rol değiştir/pasifleştir gizli; DEMO'da açık. Şifre ve silme uçları hazır.
2. `POST /users` gövdesinde isteğe bağlı `leader_id` (admin, ortak firmaya bağla). İstemci aynı bayrakla gönderir.
3. Sunucuda son yöneticinin silinmesini engelle (şimdi yalnız kendini silme 400; istemci son admin korumasını UI'da uygular).
4. `GET /projects` satırına `balance` (P0-4; değişmedi). İstemci `ProjectRef.serverBalance` varsa kullanır, yoksa `total + extras - paid` (ilave işleri bilmez).
5. `GET /projects/:id/collaborators` kayıt sahibi seçici için kullanılır; 403/404 gelirse seçici sessizce gizlenir. Gider/ödeme `owner_id` kuralı (v16) sunucuda; yetkisiz atama sessizce kendi defterine düşer (istemci notla belirtir).
6. `GET /reports/project-profit` (zaten açıktı).
7. Kullanıcı kimliği → ad: kayıt sahibi adı `GET /auth/me` `team` içinden çözülür; bilinmeyen kimlik "Başka kullanıcı" görünür. `owner_name` alanı ödeme/gider satırında gelirse tam çözülür.

### Kalan eksikler (bu turda yapılmadı)
- Gider kategori dağılımı ve önceki döneme % değişim rozeti (P2: F13, F15).
- Proje formunda kayıt sahibi yalnız ödeme/gider formlarında; sabit gider formunda yok.
- Müşteri seçicinin teklif formuna bağlanması (jobs).


## jobs (eski panel P1 turu)
- [x] Teklifler: çoklu seçim (uzun bas / "Seç"; "Görünenleri seç"; `OfferSelectionBar`), toplu durum (`PATCH /offers/bulk-status`, "Geri al" ile eski durumlara), toplu silme (`DELETE /offers/bulk`, onay + geciktirilmiş gerçek silme + "Geri al"). Sunucu toplu uçları yalnız SAYI döner ve erişimsizi sessizce atlar: `runBulk` (jobs_bulk.dart) parça başına (50) toplu çağrı yapar, sayı eksikse hangi kaydın işlenmediğini tek tek doğrular, toplu çağrı hata verirse (ağ dışı) tek tek uygular (eşzamanlılık 3). Sonuç özeti: "5 işlem: 4 başarılı, 1 hatalı" + nedenler; hatalılar seçili kalır.
- [x] Proje silme (`DELETE /projects/:id`, yalnız admin, proje ayrıntısı menüsü): bağlı görev/ilave/ödeme/gider uyarısı, ödeme/gider varsa onay kutusu, geciktirilmiş gerçek silme + "Geri al". Eski panelde proje listesinde çoklu seçim yoktu; eklenmedi.
- [x] Proje listesi bölümleri: "Devam eden ..." / "Tamamlananlar" başlıkları ve sayaçları.
- [x] `OfferCard` taşmaları giderildi (tutar ve bekleme etiketi `Flexible`).
- [ ] Backend önerisi: toplu uçlar atlanan kimlikleri de döndürsün (`{updated, skipped:[{id,reason}]}`); istemci şimdi tek tek doğruluyor.
- [ ] Jobs PDF/dosya paylaşımı `SharePlus` ile hâlâ yapılmadı (bağlantı kopyala/aç).
- [ ] Proje listesinde çoklu seçim/silme eklenmedi (eski panelde yok).


## WEB paneli (panel.controlx.com.tr) turu

### Yapılanlar
- [x] Web derlemesi (`flutter build web`), temiz URL, açılış ekranı, manifest/ikonlar, CDN'siz CanvasKit, CSP uyumlu `index.html`; `docs/WEB-DEPLOY.md`, `deploy/apache/`, `.github/workflows/web.yml`.
- [x] Çekirdek: `AppScaffold(wideLayout)`, `ResponsiveColumns`, `SideBySide`, `DataTableView`, `FocusRing`, `core/router/master_detail.dart` (ana-ayrıntı, YALNIZ yönlendirme katmanından: İşler dahil), komut paleti (Ctrl+K, `/`), sekme başlığı, `core/web/browser.dart` (indir/yazdır/blob), `PickedFileStore`, `Csv`.
- [x] Backend: `CORS_ORIGINS` içinde `https://panel.controlx.com.tr` SUNUCU-GUNCELLEME.md'de ZATEN VAR (satır 164); deneme adresi için WEB-DEPLOY §3 geçici `panel-yeni` eklemeyi anlatır.
- [x] İstemci türü: web `client:"web"` gönderir (7 gün jeton); `X-Client: mobile` yalnız mobilde.

### jobs ajanı bitince yapılacaklar (jobs klasörüne dokunulmadı)
- [ ] `jobs/data/document_picker.dart` web: `FilePicker.pickFile()` webde `path == null` döner; `PlatformDocumentPicker.pickFile` içinde
  `kIsWeb ? PickedFileStore.put(await f.xFile.readAsBytes()) : f.path` kullanın (`core/files/picked_files.dart`) ve `PickedDocument.size`'ı `f.size`'dan alın.
  `image_picker` (kamera/galeri) için ek iş gerekmez: `blob:` yolunu `ApiClient.upload` okur.
- [ ] Ana-ayrıntıda seçili satır vurgusu: liste kartı `ShellController.maybeOf(context)?.split == true` iken konumu `GoRouterState.of(context).uri` ile karşılaştırıp kartı vurgulasın (şimdi vurgu yok; müşteri/randevu için de aynı).
- [ ] Teklif/proje DETAY ekranlarında geniş yerleşim: `project_detail_screen.dart` (1400+ satır) `ResponsiveColumns` ile iki sütun (sol: özet/aşama, sağ: ödeme/giderler/belgeler); `offer_detail_screen.dart` benzer. Şimdi tek sütun, en çok 840 dp.
- [ ] 900–1200 dp arası (ana-ayrıntı yok) İşler listesi için `DataTableView` (teklifler: kod, müşteri, hizmet, durum, tutar, tarih; projeler: kod, müşteri, aşama, sözleşme, kalan) ve CSV.
- [ ] Teklif PDF: backend `GET /quotes/:offerId/pdf` gelince web'de `browserDownload(bytes, 'teklif.pdf', 'application/pdf')`; şimdilik bağlantı aç/kopyala.
- [ ] `jobs` formlarında `Ctrl+S` ile kaydet kısayolu (isteğe bağlı) ve Esc ile vazgeç (şimdi yalnız Geri).
- [ ] `JobsScreen`/`CustomersScreen` listeleri master bölmesinde de ayrı bir `AppScaffold` çizer; jobs "Seç" çoklu seçim kipi çalışır, ama toplu işlem sonrası sağ bölme açık kayıt silinirse `context.go(Routes.jobs)` ile köke dönmesi önerilir.

### Bilinen sınırlar (web)
- Web'de Ctrl+F/sayfa yazdırma tuval içeriğini görmez (tablolarda "Yazdır"/"CSV" var).
- Finans formları (`/finance/payments/new` vb.) kök gezginde TAM EKRAN açılır (kenar menüsüz): mobil davranışı korundu; web'de pencere/panel olarak açmak sonraki iş.
- Müşteri/Stok listeleri 900–1200 dp arasında tablo değil kart (ana-ayrıntı >= 1200 dp'de var).
- Gerçek API sürümü canlı sunucuya karşı elle duman testi yapılmadı (yalnız DEMO + ScriptedAdapter + gerçek tarayıcıda DEMO).
