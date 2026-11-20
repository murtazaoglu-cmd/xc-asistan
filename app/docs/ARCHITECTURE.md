# XC Asistan: Mimari ve Geliştirme Rehberi

Flutter 3.50 / Dart 3.14 (Android + iOS). Durum yönetimi Riverpod 3, yönlendirme go_router 18, HTTP dio 5.
UI paketi `material_ui` (Flutter 3.50'de Material ayrı pakettir: `import 'package:material_ui/material_ui.dart'`).
Yerelleştirme için `GlobalMaterialLocalizations.delegates` (material_ui'dan) kullanılır.

## 1. Katmanlar

```
lib/
  main.dart, app.dart        açılış, MaterialApp.router, AppRoot (yaşam döngüsü, kilit, derin bağlantı)
  core/                      ORTAK ÇEKİRDEK (feature ajanları DEĞİŞTİRMEZ; eksik varsa koordinatöre bildirir)
    config/                  AppConfig (--dart-define), BrandProfile (marka + sözlük)
    theme/                   tokens.dart (tek stil kaynağı), app_theme.dart
    util/                    Money, Ist/InstantRange (tarih), PhoneUtil, JsonReader, Fmt, domain_enums
    api/                     ApiClient, AppException, interceptor'lar, bağlantı, sürüm denetimi
    auth/                    SessionNotifier, yetkiler (AppCapabilities), biyometrik kilit
    storage/                 TokenStore (güvenli), AppPrefs
    notifications/           yerel bildirim + günlük brifing + PushService arayüzü
    share/                   "Paylaş" menüsünden gelen içerik (ReceivedShare)
    router/                  rotalar, yönlendirme, kabuk, menü kataloğu
    ui/                      ortak widget'lar (ui.dart barrel)
    demo/                    DEMO modu: bellek içi sahte API
  features/<f>/              her özellik kendi klasöründe
    <f>_routes.dart          GoRoute listesi
    data/<f>_repository.dart soyut sınıf + Http uygulaması + provider
    data/<f>_demo.dart       DEMO rotaları (o özelliğin uçları)
    presentation/            ekranlar ve özelliğe özel widget'lar
```

Bağımlılık yönü: `features → core`. `core` hiçbir feature'ı bilmez (tek istisna: demo kayıt defteri
`core/demo/demo_adapter.dart` feature demo dosyalarını listeler). Feature'lar birbirinin klasörüne YAZMAZ ve
birbirinin `presentation` kodunu içe aktarmaz; ortak ihtiyaç `core/ui` ya da `core/util` konusudur.

## 2. Sözleşme kuralları (sunucu ile)

- Para: kabloda TL ondalık; uygulamada tamsayı kuruş: `Money`. `double` ile tutar toplanmaz.
  `Money.fromJson(row['total'])`, gösterim `MoneyText`, gönderim `money.toJson()`.
- Tarih: kabloda UTC ISO. Gün sınırları İstanbul (sabit UTC+3): `Ist`, `InstantRange` (today, weekRange Pzt başlangıçlı, monthRange).
  Ekranda `DateText` (ham `DateTime.toString()` kullanma).
- Telefon: `PhoneUtil` (0532... → 90532...; `tel:`, WhatsApp uygulama/web bağlantısı). Müşteri anahtarı `phoneKey`.
- Enum değerleri sunucudaki Türkçe değerlerdir (`OfferStatus.fromApi('Yeni')`). Bilinmeyen değer çökertmez (null → nötr görünüm).
- 401: reddedilen jeton şimdiki jetonla karşılaştırılır; tek seferlik, döngüsüz oturum sonu. 
- Yeniden deneme yalnız güvenli GET'lerde (üstel bekleme). POST/PATCH/DELETE otomatik tekrarlanmaz.
- 207 (kısmi) ve 502 `acceptStatuses` ile ele alınır (örnek: `jobs_demo.dart` teklif gönderimi).
- 5xx sunucu ayrıntısı kullanıcıya gösterilmez (maskelenir).
- Silme uçları geri alınamaz: `UndoSnackbar.deferred` ile gerçek DELETE geciktirilir.

## 3. Yeni ekran / rota / repository ekleme (tarif)

1. Repository (`features/<f>/data/<f>_repository.dart`):
   ```dart
   abstract class FooRepository { Future<List<Foo>> list(); }
   class HttpFooRepository implements FooRepository {
     HttpFooRepository(this.api); final ApiClient api;
     @override Future<List<Foo>> list() async =>
         (await api.getList('/foo')).map((e) => Foo.fromJson(e as Map<String, dynamic>)).toList();
   }
   final fooRepositoryProvider = Provider<FooRepository>((ref) => HttpFooRepository(ref.watch(apiClientProvider)));
   final fooListProvider = FutureProvider.autoDispose((ref) => ref.watch(fooRepositoryProvider).list());
   ```
   Model `fromJson` içinde `JsonReader` uzantıları (`str`, `intOr`, `money`...) kullan; eksik/null alanda çökme olmasın.
2. Ekran: `AsyncValueView` (yükleniyor → iskelet, hata → Tekrar dene, boş → EmptyState) + `PullToRefresh`.
   Referans: `features/home/presentation/home_screen.dart`.
3. Rota: `features/<f>/<f>_routes.dart` içinde GoRoute; yetki `RouteGuard` (core/router/routes.dart) ve menü
   görünürlüğü `NavCatalog` (core/router/nav_items.dart) tek kaynaktan gelir.
4. DEMO: `features/<f>/data/<f>_demo.dart` içine `DemoRoute('GET', '/foo', (req) => DemoResponse.json(...))`.
5. Test: repository için `ScriptedAdapter` (test/helpers/fakes.dart), ekran için `pumpUi`/`pumpXcApp` (test/ui, test/helpers/app_harness.dart).

Hata kalıbı: repository `AppException` fırlatır (`AppException.from(e)`); ekran `ErrorState(error: e, onRetry: ...)`
gösterir. Form kayıtlarında 400 → alan mesajı, 409 → çakışma mesajı; `BottomSaveBar(loading: true)` çift gönderimi engeller.

## 4. Yetki ve kabuk

Roller: admin, personel, saha. `AppCapabilities.forRole` ekran yetkilerini üretir.
Alt çubuk: Bugün · İşler · Asistan (ortada, büyük) · Müşteriler · Para. Sol menü (ve "Daha fazla" ekranı): Müşteriler,
Asistan, Randevular, Stok, Raporlar, Fatura/KDV, Ayarlar (tüm modüller menüden erişilir; geniş ekranda `SideNav` yinelenenleri ayıklar). SAHA sade kabuk görür (Bugün + Randevular, menüde yalnız Ayarlar; ayrıca `/assistant/briefing|closure|inbox|prefs` yolları açıktır: sade brifing, zil, tercihler); yasak yola gidişte
`/today`'e yönlenir (UI gizlemesine ek olarak yönlendirme koruması). Android geri tuşu: iç sayfa → sekme kökü → Bugün → çıkış.
Girişsiz açılan derin bağlantı girişten sonra korunur (`?from=`).

GENİŞ EKRAN (>= 900 dp, `Breakpoints.wide`): kabuk alt çubuk + çekmece yerine lacivert sol kenar menüsü (`SideNav`: tüm öğeler,
kullanıcı, çıkış) + içerik alanı kurar; `AppScaffold` bu durumda menü düğmesini göstermez (`ShellController.wide`). Ekranlar
`Breakpoints.isWide(context)` / `isExtraWide` (>= 1280) ile kendi düzenini uyarlar. Web ajanı bu iskeleti derinleştirir
(ana-ayrıntı sütunları, tablo görünümü, klavye kısayolları); rol/yetki mantığı `NavCatalog`'dan gelmeye devam eder.

## 5. Marka ve sektör bağımsızlığı (ÖNEMLİ İLKE)

Ürün tek firmaya ya da tek sektöre bağlı DEĞİLDİR. Firma adı, renk, logo ve sektör dili `BrandProfile` içindedir
(`core/config/brand_profile.dart`). Varsayılan `BrandProfile.generic` ('genel': "XC Asistan", "İşletmem",
"Fiyat teklifi", "Keşif" yerine "Ön görüşme"); örnek profil `BrandProfile.xControl` (X Control Yapı).
`--dart-define=BRAND=x_control` ile seçilir; ileride `GET /config` yanıtıyla `brandProfileProvider.notifier.apply(...)`
(`fromJson`) yüklenebilir.

Kurallar:
- Ekran metninde firma adını ya da sektör terimini SABİT YAZMA. `context.brand.companyName`, `context.terms`
  (`Glossary`: `appointmentTypeLabel`, hizmet türleri, "teklif" sözcüğü...) kullan.
- Sözlük yalnız GÖRÜNTÜ içindir: kabloya giden değerler (ör. randevu türü `'Keşif'`) çevrilmez, yalnız gösterilirken çevrilir.
- WhatsApp varsayılan metni `defaultWhatsAppText(companyName, name:)` ile marka adı taşır.
- Renkler `core/theme/tokens.dart` (`AppPalette`); marka birincil rengi `AppTheme.light(primary:)` ile gelir. Sabit renk yazma.

## 5b. Tasarım kaynağı ve token eşlemesi

Onaylı görsel tasarım: `/mnt/user-data/outputs/tasarim/` (design-board.png, design-board-expanded.png, design-tokens.json,
index.html = gezilebilir prototip, README.md). Tüm değerler `lib/core/theme/tokens.dart` içindedir; başka dosyada renk/ölçü yazılmaz.

| Tasarım | Token |
|---|---|
| Ana #3B82F6 / açık ana #60A5FA (koyu temada ana) | `ColorScheme.primary`, `XcColors.assistant/info` |
| Lacivert #172033, ikincil #24324A | `XcColors.navy/navySecondary` (saha ekranı zemini), açık tema `onSurface` |
| Arka plan #F5F7FB / yüzey #FFFFFF / çizgi #E4E9F1 | `surfaceContainerLow` / `surface` / `outlineVariant` |
| Metin #172033, soluk #718096 | `onSurface`, `onSurfaceVariant` |
| YZ #8B5CF6 + açık zemin | `XcColors.ai/aiContainer/onAiContainer` (`AiCard`) |
| Başarı #16A34A, uyarı #F59E0B, hata #EF4444 | `XcColors.success/warning`, `ColorScheme.error` |
| Koyu: #0B1324 zemin, #1E2938 yüzey, #334155 kart, #22C55E/#FBBF24/#F87171/#A78BFA | `darkScheme/darkExtras` |
| Köşe 10/12/18/22 (+8/16/24) | `Radii.sm/md/card/xl` (+`xs/lg/xxl`) |
| Boşluk 4/8/12/16/24/32 | `Space.xs…xxl` |
| Dokunma 48, düğme 48–56, gövde 16 | `Sizes.minTouch`, `TypeTokens.body` |
| Inter (gömülü, çevrimdışı; Türkçe karakter destekli) | `TypeTokens.fontFamily`, `assets/fonts/Inter-*.otf` |
| Logo: mavi çarpı "X" (yer tutucu) | `BrandLogo` (çizim), `BrandProfile.logoAsset` ile değişir |

Marka rengi (`BrandProfile.primaryColor`) ana rengi ve asistan düğmesini değiştirir; YZ/durum renkleri sabit kalır.
Tasarım bileşenleri: alt çubukta ortada büyük yuvarlak mavi ✦ Asistan düğmesi (`AppBottomBar`), `StatTile` (4'lü sayı kutuları),
`AiCard` (Asistan Özeti, Onay, Not önerisi, Taslak yanıt, Müdür önerisi: Uyarı etiketi, "Neden?", İncele/Sonra),
`StatusChip` (Bekliyor turuncu, Gönderildi mavi, Kabul/Ödendi yeşil, Red kırmızı), durum ekranları (boş, iskelet, hata, çevrimdışı).
Saha ekranı: lacivert zemin (`navy`) + büyük butonlar; ilgili feature (home/appointments) bu token'ları kullanır.
İkonlar Material rounded/outline (Lucide yerine, ek paket yok). Testler: `test/ui/design_test.dart` renk/ölçü değerlerini doğrular.
Not: beyaz üstü #3B82F6 küçük metinde AA (4,5:1) vermez; küçük metin için `onSurface` kullan, ana renk düğme/ikon/vurguda.

## 6. Ortak widget kataloğu (`core/ui/ui.dart`)

| Widget | Amaç |
|---|---|
| `AppScaffold` | Başlık, menü düğmesi, `bottomBar` (klavyede görünür kalır), genişlik sınırı |
| `SectionCard` | Başlıklı kart bölümü |
| `StatusChip(.offer/.stage/.appointment/.send/.task)` | Durum etiketi (renk + ikon + metin) |
| `EmptyState`, `ErrorState`, `SkeletonList/SkeletonBox`, `AsyncValueView` | Yükleniyor/boş/hata kalıbı |
| `PullToRefresh`, `PullToRefresh.fill` | Aşağı çekip yenile (boş/hata durumunda `.fill`) |
| `MoneyText`, `DateText` | Tutar ve tarih gösterimi |
| `PhoneActionButtons`, `PhoneActions`, `AddressActions` | Ara / WhatsApp / yol tarifi |
| `BottomSaveBar` | Form alt eylem çubuğu |
| `ConfirmDialog.show` | Onay (yıkıcı işlemde `destructive: true`) |
| `UndoSnackbar.show / .deferred` | Geri al bildirimi (silmede `deferred`) |
| `OfflineBanner` | Çevrimdışı şeridi (kabuk otomatik koyar) |
| `AiCard(kind: …)` | Asistan/YZ önerisi kartları (özet, onay, not, taslak yanıt, müdür önerisi) |
| `StatTile` | Sayı kutusu (Randevu/Tahsilat/Teklif/Geciken iş) |
| `FeaturePlaceholder` | Henüz yazılmamış özelliğin yer tutucusu (ajan kendi ekranıyla değiştirir) |

Dokunma hedefi en az 48 dp; metin ölçeklemede taşma olmamalı (dar alanda `Wrap`).

## 7. Özellik sahipliği ve sınırları

Her ajan YALNIZ kendi `features/<f>/` klasörüne yazar (ve kendi testlerine: `test/features/<f>/`).
`core/` ve başka feature klasörleri değiştirilmez.

| Klasör | Uçlar (sözleşme) | Ortak widget'lar |
|---|---|---|
| `jobs` (+ offer/project detay) | /offers, /offers/:id, /offers/:id/status, /projects, /projects/:id/full, /projects/:id/stage, /quotes/:offerId (+/send; 200/207/502) | StatusChip, MoneyText, PhoneActionButtons, UndoSnackbar, ConfirmDialog |
| `customers` (+ detay) | /customers, /customers/:phoneKey | PhoneActions, AddressActions, StatusChip |
| `appointments` (+ detay) | /appointments (GET/POST), /appointments/:id (GET/PATCH/DELETE) | DateText, BottomSaveBar, ConfirmDialog, PhoneActionButtons |
| `finance` | /projects/:id/payments, gider/ödeme uçları | MoneyText, BottomSaveBar |
| `invoices_vat` | fatura ve KDV uçları | MoneyText, Money.vat/withVat |
| `stock` | /materials, /materials/:id | AsyncValueView, BottomSaveBar |
| `reports` | /reports/summary, /reports/profit, /reports/revenue, /reports/service-distribution (fl_chart) | MoneyText, SectionCard |
| `assistant` | /mobile/home (brifing), alınan paylaşım (`/assistant/share`, `ReceivedShare`) | AsyncValueView |
| `home` (Bugün) | /mobile/home | REFERANS uygulama |
| `settings`, `auth`, `more` | çekirdek tarafından yazıldı | çekirdek |

Adlandırma: "AlinanPaylasim" kavramı kodda `ReceivedShare`'dir.

## 8. Bildirimler

Yerel bildirimler `flutter_local_notifications`; saat dilimi Europe/Istanbul. Günlük brifing 08:00 (sabah) ve 19:00 (akşam),
Ayarlar'dan değiştirilir. `inexactAllowWhileIdle` kullanılır: `SCHEDULE_EXACT_ALARM` izni BİLEREK istenmez (Play politikası,
kullanıcıya izin ekranı çıkarmaz); bu yüzden bildirim saati birkaç dakika kayabilir. Android 13+ için `POST_NOTIFICATIONS`
ilk girişte istenir. İçerik `BriefingContentProvider` ile değiştirilir. Anlık push için `PushService` arayüzü hazırdır
(şimdi `NoopPushService`; FCM sonra bu arayüze takılır, çıkışta `DELETE /push/device` zaten çağrılır).

## 9. DEMO modu

`flutter run --dart-define=DEMO=true`. Dio'nun `HttpClientAdapter`'ı bellek içi sahte API ile değişir; repository'ler
değişmez. Giriş: e-postada `admin` / `personel` (ya da `muhasebe`) / `saha` geçen herhangi bir adres, herhangi bir şifre;
şifre `yanlis` ise 401. Jeton `demo-token-<rol>`; rol dışı uçlar 403 döner. Yeni uç eklemek için
`features/<f>/data/<f>_demo.dart` dosyasına `DemoRoute` ekle (kayıt `core/demo/demo_adapter.dart`).

## 10. Çalıştırma, test, derleme

```
flutter pub get
flutter analyze                         # 0 sorun beklenir
flutter test                            # tüm testler yeşil
flutter run --dart-define=DEMO=true
flutter run --dart-define=API_BASE_URL=https://... --dart-define=BRAND=x_control
flutter build apk --release             # android/key.properties varsa yayın imzası
```
Gradle 429 (indirme sınırı) alırsan komutu yeniden çalıştır ya da `--no-daemon` kullan.
Bu ortamda `flutter build ios` ÇALIŞMAZ (macOS gerekir): bkz. `docs/IOS-BUILD.md`.

Test kalıpları: saf mantık için düz `test`; ekran için `testWidgets` + `pumpUi` (tek widget) ya da `pumpXcApp`
(gerçek uygulama + DEMO API, `settle()`; sonsuz iskelet animasyonu yüzünden `pumpAndSettle` kullanma);
ağ için `ScriptedAdapter`; yerel bildirim/biyometrik/bağlantı için `test/helpers/fakes.dart` sahteleri.
`UndoSnackbar.deferred` testinde Future'ı `await` etme; `pump` ile süreyi ilerlet.

## 10b. Web derlemesi (panel.controlx.com.tr: eski web panelinin yerine)

Aynı kod, aynı tasarım; geniş ekranda uyarlanır. Derleme/yayın: **`docs/WEB-DEPLOY.md`** (Apache, Let's Encrypt, eski paneli devreden çıkarma,
geri alma), iş akışı taslağı `.github/workflows/web.yml`, Apache örneği `deploy/apache/`.

```
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=API_BASE_URL=https://api.controlx.com.tr/api
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=DEMO=true      # backend'siz demo
```
- **Adresler** `#` içermez (`usePathUrlStrategy`, `main.dart`); kök yol ve `--base-href` desteklenir (`web/index.html`).
  Derin bağlantılar (`/customers/05321112233`) go_router ile çalışır; girişsiz açılan bağlantı girişten sonra korunur (`?from=`);
  tarayıcı geri/ileri düğmeleri rota yığınını izler. Sekme başlığı rotaya göre güncellenir (`core/web/page_title.dart`, `PageTitleSync`).
- **Hiçbir harici CDN'e bağımlılık yok:** CanvasKit paket içinde (`--no-web-resources-cdn`), Inter ve ikonlar `assets/` içinde, açılış ekranı satır içi betiksiz (`web/boot.js`).
  CSP: `script-src 'self' 'wasm-unsafe-eval'`, `connect-src 'self' https://api.controlx.com.tr`.
- **Platform korumaları** (`kIsWeb`; web'de `dart:io` `Platform`/`File` KULLANMA):

  | Alan | Web davranışı |
  |---|---|
  | Oturum jetonu | `flutter_secure_storage` web = WebCrypto AES-GCM, `localStorage` (isteğe bağlı `WEB_SESSION_ONLY` → `sessionStorage`). Koruma düzeyi: bkz. WEB-DEPLOY §8 (XSS'e karşı asıl savunma CSP). F5 sonrası oturum sürer. DEMO web: demo jetonu `PrefsTokenStore`. |
  | İstemci türü | `client:"web"` (kısa ömürlü jeton); `X-Client` başlığı gönderilmez |
  | Biyometrik kilit | kapalı, Ayarlar'da gizli |
  | Yerel bildirim / zamanlama | `NoopNotificationsGateway`; yerine uygulama içi **Gelen kutusu** (Bugün'deki zil, palette "Gelen kutusu") |
  | Paylaş menüsü | `NoopShareSource`; dışa aktarma **tarayıcı indirmesi** (`WebDownloadExportSharer`, `core/web/browser.dart`) |
  | Dosya seçme/yükleme | seçiciler bayt verir → `PickedFileStore` (`xcmem://`); `image_picker` `blob:` adresi `ApiClient.upload` içinde okunur |
  | tel: / WhatsApp | `url_launcher`; web'de doğrudan `https://wa.me/...` (uygulama şeması denenmez) |
  | CSV / yazdır | `DataTableView` araç çubuğu: CSV (UTF-8 BOM, `;`, formül enjeksiyonuna karşı) ve ayrı sayfada yazdırma |

- **Geniş ekran yerleşimi** (hepsi çekirdekte, feature ekranları yalnız bunları kullanır; mobil (< 900 dp) düzen aynıdır):
  - `AppScaffold(wideLayout: true)`: içerik en çok 1440 dp ve ortalı; form/ayrıntı sayfaları 840 dp. Telefon/tablet 640.
  - `ResponsiveColumns` (1 / 2 / 3 sütun; Bugün, Raporlar), `SideBySide` (Finans özeti + grafik).
  - `DataTableView<T>` (core/ui/data_table_view.dart): sıralanabilir sütunlar, satır hover, Tab ile gezinti + Enter, odak halkası (`FocusRing`),
    imleç, tooltip, dar pencerede yatay kaydırma. Kullanım: Para → Ödemeler/Giderler, Fatura/KDV → Faturalar, Kullanıcılar.
  - **Ana-ayrıntı** (`core/router/master_detail.dart`, pencere >= 1200 dp): `masterPanesProvider` (app_wiring.dart) hangi liste ekranının
    kalıcı sol bölme olacağını söyler (İşler, Müşteriler, Randevular). Ayrıntı rotaları sağdaki dal gezgininde açılır; liste ekranı, rota ve
    URL DEĞİŞMEZ. Kök konumda sağ bölme "bir kayıt seçin" boş durumu gösterir. Yeni liste eklemek: `MasterPane(prefix, builder, ...)`.
  - Klavye (`ShellScaffold`): `Ctrl/Cmd+K` veya `/` (metin girişinde değilken) → "Hızlı git" paleti; `Esc` → ayrıntı bölmesini kapat.
    `HardwareKeyboard` işleyicisi kullanılır (odak nerede olursa olsun çalışır; metin girişini bozmaz).
- Test: `test/core` (CSV, başlık, dosya deposu, tablo, kolonlar, palet), `test/web` (ana-ayrıntı, tablolar, kısayollar, derin bağlantı,
  başlık), `test/screens/overflow_walk_test.dart` (360, 1024, 1280, 1440 genişlikte taşma gezintisi).
  Gerçek tarayıcı denetimi: `python3 tool/web_flows.py <build/web> <klasör>` ve ekran görüntüsü için `tool/web_shots.py` (Playwright).

## 11. Bilinen sınırlar

- iOS burada derlenemez; Share Extension (iOS "Paylaş") Xcode'da elle eklenir.
- FCM/anlık push yok (arayüz hazır). Bildirim saatleri yaklaşıktır.
- Simge (mavi çarpı X) ve logo yer tutucu vektördür (`tool/gen_icons.py`, `BrandLogo`); web'de yerel bildirim/biyometrik/paylaşım yok (yerine gelen kutusu/indirme).
- Web: tuval tabanlı (CanvasKit) olduğundan tarayıcının metin arama (Ctrl+F) ve sayfa yazdırması içeriği görmez; tablolar için "Yazdır" ve "CSV indir" kullanılır. Ekran okuyucu için anlamsal ağaç ilk Tab'da açılır.
- Web'de tel: bağlantısı masaüstünde bir şey yapmayabilir (aygıtın aramaya kayıtlı uygulaması yoksa).
- Zorunlu güncelleme kancası pasiftir (`AppConfig.forceUpdateEnabled`); `/health` sürüm alanları gelince açılır.

## 12. Fatura ve KDV (features/invoices_vat)
- Rotalar: `/invoices-vat` (sekmeler: Faturalar, KDV, Vergi Takvimi, Ödeme Planı; `?tab=` ile açılır), `/invoices-vat/new`, `/invoices-vat/plan/new`, `/invoices-vat/:id`, `/invoices-vat/:id/edit`. Rol: admin/muhasebe tam, ortak yalnız kendi defteri (takvimi okur), personel/saha yok (RouteGuard + yetki yok ekranı).
- Tutarlar tamsayı kuruş (`Money`), oranlar sunucudan (`GET /vat/rates`); önizleme `VatCalc` ile kuruş doğru, kesin hesap sunucuda. Doğrulanmamış oran/tarih/tevkifat `ConfirmBadge` ("Mali müşavire teyit edin") ile işaretlenir. Uygulama fatura kesmez, hukuki/mali tavsiye vermez.
- Tahsilat planı bölümü proje detayına gömülür: `PaymentScheduleSection(projectId:, projectCode:, customerName:, remaining:)`. Finans ekranı bunu doğrudan içe aktarmaz; `paymentScheduleBuilderProvider` override'ı ile bağlanır (bkz. CORE-REQUESTS.md "invoices_vat ajanı").
- DEMO: `invoicesVatDemoRoutes(db)` `demo_adapter.dart` içinde KAYITLIDIR. Tahsilat planı bölümü `lib/app_wiring.dart` ile finans alacak kartına bağlıdır. Testler: `test/features/invoices_vat/` (`harness.dart`: `pumpFeature`, `demoRepo`, `apiWith`).


## 13. Asistan (features/assistant): ÜCRETSİZ, KURAL TABANLI
Yapay zekâ / LLM çağrısı YOKTUR. "Asistanla konuş" = Türkçe komut çubuğu; yanıtı sunucudaki kural tabanlı ayrıştırıcı verir (`POST /assistant/commands`). Anlaşılmazsa "Ne demek istediniz?" seçenek kartı çıkar. Yazma işlemleri HİÇBİR ZAMAN kendiliğinden yapılmaz: Onay kartı (Onayla / Düzenle / Vazgeç), uygulandıktan sonra 10 dk "Geri al".

**Dışa açık yüz:** başka klasörler yalnız `lib/features/assistant/assistant_public.dart` dosyasını içe aktarır.

| Ne | Nasıl takılır |
|---|---|
| Bugün ekranı özet kartı | `BriefingSummaryCard()` (mor "Asistan Özeti", 4 sayı karosu; `onOpen` verilmezse `/assistant/briefing`). Saha için sade, para/teklif karosu yok (içeride süzülür). Home ajanı Bugün gövdesinin en üstüne koyar. |
| Üst çubuk zili | `InboxBellButton()` (okunmamış rozeti); sayı için `inboxUnreadCountProvider`. Rota: `/assistant/inbox`. Asistan sekmesinde zaten ekli; Bugün AppBar `actions`'a eklenebilir. |
| Bildirim tercihleri | `AssistantPrefsSection(shrinkWrap: true)` ya da ekran `/assistant/prefs` (GET/PUT `/assistant/prefs`). Kayıt sonrası sabah/akşam bildirimleri yeniden kurulur. |
| Müşteri kartı yazışma bölümü | `conversationSectionBuilderProvider.overrideWithValue((ctx, a) => AssistantConversationSection(phoneKey: a.customer.phoneKey, name: a.customer.name))`. Asistan müşteri anahtarı telefonun SON 10 hanesidir (`assistantCustomerKey`); uygulamanın `phoneKey`'i (tüm rakamlar) bu bölümde çevrilir. |
| Sabah/akşam yerel bildirimi | `assistantNotificationSchedulerProvider.apply()` (açılışta, girişten sonra ve tercih değişince). Core arayüzü (`NotificationService`) değişmedi; tüm gün seçiliyse günlük tekrar, gün kısıtı varsa 7 günlük tek seferlik (kimlik 1011–1017 / 1021–1027). Dokununca `/assistant/briefing` ve `/assistant/closure`. |
| DEMO uçları | `assistantDemoRoutes(db)` `demo_adapter.dart`'ta KAYITLIDIR. |

**Rotalar** (`AssistantPaths`): `/assistant` (sohbet), `/assistant/briefing` (+`/history?type=weekly|monthly`, `/view` extra=Briefing), `/assistant/insights` (+`/rules`, yalnız admin), `/assistant/closure`, `/assistant/inbox`, `/assistant/prefs`, `/assistant/consents`, `/assistant/suggestions?conversation=&customer=`, `/assistant/share?customer=`.

**Rol görünürlüğü:** saha → para/tahsilat/teklif/stok/soru/müdür YOK, yazışma içe aktarma YOK; yalnız kendi randevuları ve sade brifing. Personel → para ve tahsilat YOK, müdür YOK. Müdür önerileri ve haftalık/aylık rapor: admin, muhasebe, ortak. Kural düzenleme (aç/kapa, eşik): yalnız admin. Sunucu zaten süzer; istemci `visibleBlocks` ile ikinci savunmadır. "bağımlılık" (bagimli) durumundaki kurallar arayüzde gösterilmez.

**Gizlilik:** sohbet geçmişi cihazda kısa tutulur (en çok 30 mesaj, 7 gün, kullanıcıya özel anahtar), oturum kapanınca ve "Sohbeti temizle" ile silinir; kartlarda yalnız kimlik ve durum saklanır. Yazışma içe aktarma aydınlatma metni ve açık rıza olmadan yüklemez; müşteri kartından tüm yazışma verisi silinebilir.

**Testler:** `test/features/assistant/` (`harness.dart`: asistan DEMO uçlarını sahte HTTP olarak sunar; `demoRepo`, `pumpScreen`, `containerFor`).


## 14. Birleştirme (entegrasyon) durumu

**Kompozisyon kökü: `lib/app_wiring.dart`.** Feature'lar birbirinin presentation kodunu içe aktarmaz; bağlantılar burada
Riverpod override'ları olarak kurulur ve `main.dart` ile test harness'i (`test/helpers/app_harness.dart`) AYNI `featureWiring`
listesini kullanır. Yeni bir özellikler arası bağ gerekiyorsa buraya eklenir.

| Bağ | Nerede |
|---|---|
| Müşteri kartı → yazışma bölümü | `conversationSectionBuilderProvider` → `AssistantConversationSection` |
| Finans alacak kartı → vade/ödeme planı | `paymentScheduleBuilderProvider` → `invoices_vat` `PaymentScheduleSection` |
| Sabah/akşam bildirimi | `dailySchedulerProvider` → `AssistantBackedDailyScheduler` (core çağrıları asistan kurucusuna gider; çift bildirim yok) |
| Fatura/KDV dışa aktarma | `exportSharerProvider` → `ShareSheetExportSharer` (`share_plus`) |
| Riverpod yeniden deneme | `ProviderScope(retry: noProviderRetry)` (`main.dart`); hata durumu iskelet olarak takılı kalmaz |
| Proje ödeme/gider ekleme | jobs proje ekranı doğrudan `FinanceNav.addPayment/addExpense` (kayıtta ekran yenilenir) |
| Bugün ekranı | zil (`InboxBellButton`) + `BriefingSummaryCard(showStats: false)`; saha: "Günün brifingi" düğmesi |
| Ayarlar | Bildirimler kartı = `AssistantPrefsSection` (sunucu tercihleri) + izin düğmesi |
| Oturum | açılış/giriş/ön plana dönüşte `dailySchedulerProvider.apply()`; çıkışta bildirimler iptal (`cancelAll`) + sohbet geçmişi silinir |
| DEMO | `demo_adapter.dart` tüm modüllerin rotalarını kaydeder (home, appointments, jobs, customers, finance, stock, reports, invoices_vat, assistant) |

**Otomatik ekran gezintisi:** `test/screens/overflow_walk_test.dart`; DEMO'da her rol için ana ekranları 360x800 ve 1280x800'de
gezer, `FlutterError` (RenderFlex taşması dahil) olmamasını doğrular. Yeni ekran eklerken rotayı bu dosyadaki listeye ekleyin.
`test/integration/wiring_test.dart`: rol koruması, menü, çekirdek eklemeleri, bağlantıların varlığı.

**Derleme:**
```
flutter build apk --release --dart-define=DEMO=true                                   # demo (sahte API)
flutter build apk --release --dart-define=API_BASE_URL=https://api.controlx.com.tr/api --dart-define=BRAND=x_control
```
İmza `android/key.properties` ile (yoksa debug imzası). `apksigner verify --print-certs` ile doğrulanır.


## 15. Kullanıcılar, şifre, finans dönemi, müşteri seçici (settings / finance / customers)

- **Kullanıcılar** (`features/settings`): rotalar `/users`, `/users/new`; `/settings/password`. Yalnız admin ve ortak (`AppCapabilities.showUsers`, `RouteGuard`, menü `NavCatalog.drawer`). Kurallar saf mantıkta: `UserRules` (atanabilir roller, silme/sıfırlama/rol/aktif engelleri), `UserValidators` (şifre en az 8, en çok 72 bayt, yaygın şifre yok). Rol değiştirme ve aktif/pasif `PATCH /users/:id` ister (sunucuda YOK): `kUserEditApi` / DEMO bayrağıyla açılır.
- **Şifre değiştirme**: `PATCH /users/me/password` → yanıttaki yeni jeton `sessionProvider.notifier.adoptToken`.
- **Finans dönemi**: `activePeriodProvider` = serbest aralık (`customPeriodProvider`, bitiş günü dahil, İstanbul günü) ya da seçili ay. Özet/Ödemeler/Giderler hep bunu kullanır; süzgeçler `paymentsInRange` / `expensesInRange`.
- **Kapsam adları**: sunucu `ev|dukkan|genel` aynı; kullanıcıya Ev / Dükkan / İşletme (`ScopeView.label`), toplamlarda "Ev/Dükkan/İşletme Giderleri" (`groupLabel`). Ev kâra dahil değil.
- **Kayıt sahibi**: `OwnerPickerBlock` (`ownerCandidatesProvider`), `owner_id` yalnız değiştirildiyse gönderilir; "Kim ne kadar aldı" = `FinanceCalc.byOwner`.
- **Müşteri seçici**: `features/customers/customers_public.dart` → `showCustomerPicker(context)`.
