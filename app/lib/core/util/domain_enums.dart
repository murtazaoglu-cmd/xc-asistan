// Sözleşmedeki sabit değerler (enum). `api` sunucuya giden/gelen yazımdır
// (Türkçe karakterli, TAM bu yazım). Bilinmeyen değer için `fromApi` null döner:
// arayüz ham metni olduğu gibi göstermelidir.
enum OfferStatus {
  yeni('Yeni'),
  incelendi('İncelendi'),
  kesifPlanlandi('Keşif Planlandı'),
  teklifVerildi('Teklif Verildi'),
  kabulEdildi('Kabul Edildi'),
  reddedildi('Reddedildi');

  const OfferStatus(this.api);
  final String api;
  String get label => api;
  static OfferStatus? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum ProjectStage {
  malzemeTemini('Malzeme Temini'),
  uretim('Üretim'),
  montaj('Montaj'),
  teslim('Teslim'),
  tamamlandi('Tamamlandı');

  const ProjectStage(this.api);
  final String api;
  String get label => api;
  static ProjectStage? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum TaskStatus {
  bekliyor('bekliyor', 'Bekliyor'),
  devamEdiyor('devam_ediyor', 'Devam ediyor'),
  tamamlandi('tamamlandi', 'Tamamlandı');

  const TaskStatus(this.api, this.label);
  final String api;
  final String label;
  static TaskStatus? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum ReminderStatus {
  bekliyor('bekliyor', 'Bekliyor'),
  tamamlandi('tamamlandi', 'Tamamlandı');

  const ReminderStatus(this.api, this.label);
  final String api;
  final String label;
  static ReminderStatus? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum PaymentMethod {
  havale('Havale'),
  nakit('Nakit'),
  krediKarti('Kredi Kartı');

  const PaymentMethod(this.api);
  final String api;
  String get label => api;
  static PaymentMethod? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

/// Gider kapsamı: `genel` panelde "İşletme" diye görünür.
enum ExpenseScope {
  ev('ev', 'Ev (kişisel)'),
  dukkan('dukkan', 'Dükkan'),
  genel('genel', 'İşletme');

  const ExpenseScope(this.api, this.label);
  final String api;
  final String label;
  static ExpenseScope? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

/// `quotes.last_send_status`
enum SendStatus {
  gonderildi('gonderildi', 'Gönderildi'),
  kismen('kismen', 'Kısmen gönderildi'),
  basarisiz('basarisiz', 'Gönderilemedi');

  const SendStatus(this.api, this.label);
  final String api;
  final String label;
  static SendStatus? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

/// Randevu türü/durumu SERBEST metindir (≤40). Panelin değerleri ve normalleştirme.
abstract final class AppointmentValues {
  static const List<String> types = [
    'Keşif',
    'Montaj',
    'Teslim',
    'Bakım',
    'Diğer',
  ];
  static const List<String> statuses = [
    'beklemede',
    'onaylandı',
    'tamamlandı',
    'iptal',
  ];

  /// Karşılaştırma için normalleştirir: küçük harf + Türkçe karakter sadeleştirme
  /// ("tamamlandı"/"tamamlandi" aynı sayılır).
  static String normalize(String? v) => (v ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  /// "iptal…" ile başlayanlar ana ekranda gizlenir.
  static bool isCancelled(String? status) =>
      normalize(status).startsWith('iptal');
  static bool isDone(String? status) =>
      normalize(status).startsWith('tamamlan');

  /// Gösterim: ilk harf büyük ("beklemede" → "Beklemede"); bilinmeyeni olduğu gibi.
  static String statusLabel(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '-';
    switch (normalize(t)) {
      case 'planlandi':
        return 'Planlandı';
      case 'tamamlandi':
        return 'Tamamlandı';
      case 'onaylandi':
        return 'Onaylandı';
    }
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Tür etiketi: sistem türleri (`baslama`, `teslim`, `kesif`, `montaj`) güzelleştirilir.
  static String typeLabel(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Randevu';
    switch (normalize(t)) {
      case 'baslama':
        return 'Başlama';
      case 'kesif':
        return 'Keşif';
      case 'montaj':
        return 'Montaj';
      case 'teslim':
        return 'Teslim';
    }
    return t;
  }
}
