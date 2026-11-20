// Asistan modelleri için ortak, null-güvenli okuma yardımcıları.
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

/// Metin listesi: ["a"] ya da [{"message":"a"}] biçimlerini kabul eder.
List<String> readStrings(Object? v) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    if (e is String) {
      if (e.trim().isNotEmpty) out.add(e.trim());
    } else if (e is Map) {
      final m = asJsonMap(e);
      final s =
          m.strOrNull('message') ??
          m.strOrNull('text') ??
          m.strOrNull('label') ??
          m.strOrNull('reason');
      if (s != null) out.add(s);
    }
  }
  return out;
}

/// Kuruş tamsayı alanı → [Money].
Money kurus(JsonMap m, String key) => Money.fromKurus(m.intOr(key));

Money? kurusOrNull(JsonMap m, String key) {
  final v = m.intOrNull(key);
  return v == null ? null : Money.fromKurus(v);
}

/// `/api/...` ile başlayan sunucu yollarını taban adrese (zaten `/api` içerir) göre kısaltır.
String relativeApiPath(String path) {
  var p = path.trim();
  if (p.startsWith('/api/v1/')) return p.substring(7);
  if (p.startsWith('/api/')) return p.substring(4);
  if (!p.startsWith('/')) p = '/$p';
  return p;
}

/// Yolda doldurulmamış yer tutucu (`<id>`, `:id`) var mı?
bool hasPlaceholder(String path) =>
    path.contains('<') || RegExp(r'/:\w+').hasMatch(path);

/// Asistan uçlarındaki müşteri anahtarı: telefonun SON 10 hanesi (sözleşme C).
/// Uygulamanın `phoneKey`'i (tüm rakamlar) bu anahtara çevrilir.
String assistantCustomerKey(String? phoneOrKey) {
  final d = (phoneOrKey ?? '').replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}
