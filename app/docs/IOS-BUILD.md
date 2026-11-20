# iOS Derleme Rehberi

Bu Linux ortamında `flutter build ios` çalışmaz. iOS paketi bir Mac'te ya da bulut macOS derleyicisinde alınır.
Paket kimliği: `tr.com.controlx.asistan`. En düşük iOS: 15.0. Info.plist'te Türkçe izin metinleri (kamera, galeri, Face ID),
`ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` URL şeması ve WhatsApp/tel sorgu şemaları hazırdır.

## A. Mac'te
1. Xcode (güncel) + Flutter 3.50 kur; `flutter doctor` yeşil olsun.
2. `flutter pub get && cd ios && pod install --repo-update && cd ..`
3. `open ios/Runner.xcworkspace` → Runner → Signing & Capabilities: Team seç, bundle id `tr.com.controlx.asistan`.
4. Test cihazı: `flutter run --release`. Mağaza paketi: `flutter build ipa --release`.
5. TestFlight: Xcode Organizer ya da Transporter ile .ipa yükle (App Store Connect'te uygulama kaydı gerekir).
6. Ad Hoc (mağazasız): cihaz UDID'lerini Apple Developer'a ekle, Ad Hoc profil oluştur, Organizer'dan "Ad Hoc" dışa aktar.

## B. Codemagic (Mac gerekmez)
Depoyu bağla; iOS iş akışında Apple Developer API anahtarı (App Store Connect → Users and Access → Keys) ekle,
imzalamayı "automatic" bırak, komut: `flutter build ipa --release --export-options-plist=/Users/builder/export_options.plist`.
Çıktı .ipa TestFlight'a otomatik gönderilebilir.

## C. GitHub Actions (macos-latest)
```yaml
jobs:
  ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: flutter build ios --release --no-codesign
```
`--no-codesign` yalnız derlemeyi doğrular; dağıtım için imza sertifikası/profil sırları (secrets) eklenir.

## D. Share Extension ("Paylaş" menüsünde XC Asistan)
`receive_sharing_intent` iOS'ta bir Share Extension ister; Xcode'da elle eklenir:
1. File → New → Target → Share Extension, adı `ShareExtension`, bundle id `tr.com.controlx.asistan.ShareExtension`.
2. Runner ve ShareExtension için Signing & Capabilities → App Groups: `group.tr.com.controlx.asistan` (iki hedefte aynı).
3. ShareExtension `Info.plist` → `NSExtension` → `NSExtensionAttributes` → `NSExtensionActivationRule` ile metin/dosya/görüntü türlerini aç.
4. `ShareViewController` sınıfını `RSIShareViewController` alt sınıfı yap (eklenti belgesi). `AppGroupId` anahtarını
   `$(CUSTOM_GROUP_ID)` değerine bağla; Runner `Info.plist`'e `AppGroupId` ekle.
5. Podfile'a ShareExtension hedefini ekle: `target 'ShareExtension' do inherit! :search_paths end`; `pod install`.
6. Runner URL şeması zaten `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` (Info.plist).
Ayrıntı: receive_sharing_intent paketinin iOS kurulum bölümü (sürümle küçük farklar olabilir).

## E. Sık sorunlar
- "No signing certificate": Team seçilmemiş.
- Pod hatası: `cd ios && pod repo update && pod install`.
- Face ID izni metni eksikse uygulama kilit ekranında çöker: Info.plist `NSFaceIDUsageDescription` hazır, silme.
