// Marka ve SEKTÖR SÖZLÜĞÜ profili: uygulama tek sektöre özel DEĞİL, birçok küçük
// işletmeye (usta, esnaf, hizmet/saha işletmeleri) uyarlanabilir.
//
// Bu nesne şunları taşır: marka adı, logo, ana renk, firma adı, slogan ve
// "sektör sözlüğü" (Teklif→Fiyat teklifi, Keşif→Ön görüşme, randevu türleri,
// hizmet türleri, gider kategorileri). Ekranlar sabit metin yazmaz; terimleri
// `ref.watch(brandProfileProvider).terms` / `context.terms` üzerinden okur.
//
// Sunucuya giden değerler (randevu türü, gider kategorisi vb.) sözleşmedeki gibi
// KALIR; sözlük yalnızca GÖSTERİMDE çevirir (api değeri → etiket).
//
// Şimdilik profil yereldir (varsayılan: 'genel'). İleride GET /config ile sunucudan
// gelecek: [BrandProfile.fromJson] hazırdır, [BrandProfileNotifier.apply] yükler.
// Not: Android etiketi (AndroidManifest android:label) ve iOS görünen adı
// (Info.plist CFBundleDisplayName) yerel dosyalardır; ad değişirse oralar da güncellenir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../util/json.dart';

/// Gösterim terimleri. Anahtarlar sabittir (kodda kullanılır), değerler profile göredir.
@immutable
class Glossary {
  const Glossary({
    this.job = 'İş',
    this.jobs = 'İşler',
    this.offer = 'Teklif',
    this.offers = 'Teklifler',
    this.customer = 'Müşteri',
    this.customers = 'Müşteriler',
    this.appointment = 'Randevu',
    this.appointments = 'Randevular',
    this.survey = 'Ön görüşme',
    this.stock = 'Stok',
    this.money = 'Para',
    this.appointmentTypeLabels = const {},
    this.expenseCategoryLabels = const {},
    this.expenseCategories = const [],
    this.serviceTypes = const [],
  });

  final String job;
  final String jobs;
  final String offer;
  final String offers;
  final String customer;
  final String customers;
  final String appointment;
  final String appointments;

  /// Sözleşmedeki "Keşif" türünün gösterim adı (genel profilde "Ön görüşme").
  final String survey;
  final String stock;
  final String money;

  /// api değeri → gösterim etiketi. Eşleşme olmazsa değer olduğu gibi gösterilir.
  final Map<String, String> appointmentTypeLabels;
  final Map<String, String> expenseCategoryLabels;

  /// Gider kategorisi önerileri (api değerleri, sırayla). Boşsa `expenseCategoryLabels` anahtarları,
  /// o da boşsa finans modülündeki sektör nötr varsayılanlar kullanılır.
  final List<String> expenseCategories;

  /// Yeni kayıt formunda önerilen hizmet türleri (serbest metin de girilebilir).
  final List<String> serviceTypes;

  /// Randevu türü etiketi. [apiValue] sunucudaki değerdir ("Keşif", "baslama" ...).
  String appointmentTypeLabel(String? apiValue) {
    final v = (apiValue ?? '').trim();
    if (v.isEmpty) return appointment;
    final direct = appointmentTypeLabels[v];
    if (direct != null) return direct;
    final n = _norm(v);
    for (final e in appointmentTypeLabels.entries) {
      if (_norm(e.key) == n) return e.value;
    }
    switch (n) {
      case 'kesif':
        return survey;
      case 'baslama':
        return 'Başlama';
      case 'montaj':
        return 'Montaj';
      case 'teslim':
        return 'Teslim';
    }
    return v;
  }

  String expenseCategoryLabel(String? apiValue) {
    final v = (apiValue ?? '').trim();
    return expenseCategoryLabels[v] ?? v;
  }

  /// Formda gösterilecek randevu türü seçenekleri: (api değeri, etiket).
  /// Gönderilen değerler panelinkiyle aynıdır (`Keşif`, `Montaj`, `Teslim`, `Bakım`, `Diğer`).
  List<({String api, String label})> get appointmentTypeOptions => [
    for (final api in const ['Keşif', 'Montaj', 'Teslim', 'Bakım', 'Diğer'])
      (api: api, label: appointmentTypeLabel(api)),
  ];

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  factory Glossary.fromJson(JsonMap j) {
    Map<String, String> m(String k) =>
        asJsonMap(j[k]).map((a, b) => MapEntry(a, b.toString()));
    return Glossary(
      job: j.strOr('job', 'İş'),
      jobs: j.strOr('jobs', 'İşler'),
      offer: j.strOr('offer', 'Teklif'),
      offers: j.strOr('offers', 'Teklifler'),
      customer: j.strOr('customer', 'Müşteri'),
      customers: j.strOr('customers', 'Müşteriler'),
      appointment: j.strOr('appointment', 'Randevu'),
      appointments: j.strOr('appointments', 'Randevular'),
      survey: j.strOr('survey', 'Ön görüşme'),
      stock: j.strOr('stock', 'Stok'),
      money: j.strOr('money', 'Para'),
      appointmentTypeLabels: m('appointmentTypeLabels'),
      expenseCategoryLabels: m('expenseCategoryLabels'),
      expenseCategories: j.stringList('expenseCategories'),
      serviceTypes: j.stringList('serviceTypes'),
    );
  }
}

@immutable
class BrandProfile {
  const BrandProfile({
    required this.id,
    required this.appName,
    required this.companyName,
    this.tagline = 'İşlerin, müşterilerin ve paran tek yerde',
    this.monogram = 'XC',
    this.logoAsset,
    this.primaryColor,
    this.terms = const Glossary(),
  });

  /// Profil kimliği ('genel', 'x_control' ...).
  final String id;
  final String appName;
  final String companyName;
  final String tagline;

  /// Logo yokken çizilen rozet harfleri (1-3 harf).
  final String monogram;

  /// 'assets/brand/logo.png' gibi; null iken monogram rozeti çizilir.
  final String? logoAsset;

  /// Ana renk. null ise tokens.dart paleti kullanılır; doluysa tema bu rengi
  /// `primary` olarak uygular (firma başına renk).
  final Color? primaryColor;
  final Glossary terms;

  /// VARSAYILAN: sektör nötr profil. Başlangıç uygulama adı "XC Asistan".
  static const BrandProfile generic = BrandProfile(
    id: 'genel',
    appName: 'XC Asistan',
    companyName: 'İşletmem',
    monogram: 'XC',
    terms: Glossary(
      offer: 'Fiyat teklifi',
      offers: 'Fiyat teklifleri',
      survey: 'Ön görüşme',
      serviceTypes: [
        'Montaj',
        'Bakım / onarım',
        'Üretim',
        'Danışmanlık',
        'Diğer',
      ],
      appointmentTypeLabels: {
        'Keşif': 'Ön görüşme',
        'Montaj': 'Montaj',
        'Teslim': 'Teslim',
        'Bakım': 'Bakım',
        'Diğer': 'Diğer',
      },
    ),
  );

  /// ÖRNEK profil: X Control Yapı (ilk müşteri). Yalnızca örnek/yapılandırma;
  /// uygulama kodu bu profile bağımlı değildir.
  static const BrandProfile xControl = BrandProfile(
    id: 'x_control',
    appName: 'XC Asistan',
    companyName: 'X Control Yapı',
    monogram: 'XC',
    terms: Glossary(
      offer: 'Teklif',
      offers: 'Teklifler',
      survey: 'Keşif',
      serviceTypes: ['Montaj', 'Üretim', 'Bakım', 'Onarım', 'Diğer'],
      appointmentTypeLabels: {
        'Keşif': 'Keşif',
        'Montaj': 'Montaj',
        'Teslim': 'Teslim',
        'Bakım': 'Bakım',
        'Diğer': 'Diğer',
      },
    ),
  );

  static const Map<String, BrandProfile> builtIn = {
    'genel': generic,
    'x_control': xControl,
  };

  /// `--dart-define=BRAND=x_control` ile örnek profil seçilebilir.
  factory BrandProfile.fromEnvironment() {
    const id = String.fromEnvironment('BRAND', defaultValue: 'genel');
    return builtIn[id] ?? generic;
  }

  /// GET /config yanıtı (ileride). Eksik alanlar varsayılandan tamamlanır.
  factory BrandProfile.fromJson(JsonMap j, {BrandProfile base = generic}) {
    final color = j.strOr('primaryColor');
    final hex = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(color);
    return BrandProfile(
      id: j.strOr('id', base.id),
      appName: j.strOr('appName', base.appName),
      companyName: j.strOr('companyName', base.companyName),
      tagline: j.strOr('tagline', base.tagline),
      monogram: j.strOr('monogram', base.monogram),
      logoAsset: j.strOrNull('logoAsset') ?? base.logoAsset,
      primaryColor: hex == null
          ? base.primaryColor
          : Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16)),
      terms: j.mapOrNull('terms') == null
          ? base.terms
          : Glossary.fromJson(j.mapOrNull('terms')!),
    );
  }
}

class BrandProfileNotifier extends Notifier<BrandProfile> {
  @override
  BrandProfile build() => BrandProfile.fromEnvironment();

  /// Sunucudan (GET /config) ya da yerelden yeni profil yükler.
  void apply(BrandProfile profile) => state = profile;
}

final brandProfileProvider =
    NotifierProvider<BrandProfileNotifier, BrandProfile>(
      BrandProfileNotifier.new,
    );

/// Ekranlarda: `context.terms.offer`. (ConsumerWidget içinde `ref.watch(brandProfileProvider)` da olur.)
extension BrandX on BuildContext {
  BrandProfile get brand =>
      ProviderScope.containerOf(this).read(brandProfileProvider);
  Glossary get terms => brand.terms;
}

/// Logo: profil logosu ya da "XC" harfli yer tutucu rozet.
class BrandLogo extends ConsumerWidget {
  const BrandLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(brandProfileProvider);
    final asset = b.logoAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        semanticLabel: b.appName,
      );
    }
    // Yer tutucu logo: mavi çarpı "X" işareti (marka rengi). Gerçek logo logoAsset ile gelir.
    return Semantics(
      label: b.appName,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _XMarkPainter(context.colors.primary),
      ),
    );
  }
}

/// İki yuvarlak uçlu çapraz çubuktan oluşan "X" işareti.
class _XMarkPainter extends CustomPainter {
  _XMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.26;
    final m = w * 0.18;
    canvas.drawLine(Offset(m, m), Offset(w - m, w - m), paint);
    paint.color = color.withValues(alpha: 0.65);
    canvas.drawLine(Offset(w - m, m), Offset(m, w - m), paint);
  }

  @override
  bool shouldRepaint(_XMarkPainter old) => old.color != color;
}
