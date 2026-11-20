// Null-güvenli JSON okuma yardımcıları. Modeller elle yazılır (kod üretici yok);
// bu uzantı `fromJson` içinde sağlam, tek tip okuma sağlar.
import 'dates.dart';
import 'money.dart';

typedef JsonMap = Map<String, dynamic>;

/// Bilinmeyen bir değeri güvenle [JsonMap]'e çevirir (değilse boş harita).
JsonMap asJsonMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

/// Bilinmeyen bir değeri güvenle [JsonMap] listesine çevirir.
List<JsonMap> asJsonList(Object? v) {
  if (v is List) return v.whereType<Map>().map(asJsonMap).toList();
  return <JsonMap>[];
}

extension JsonReader on Map<String, dynamic> {
  /// Metin; sayı/bool gelirse metne çevirir; yoksa null.
  String? str(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  /// Boş olmayan metin ya da null (boşluklar kırpılır).
  String? strOrNull(String key) {
    final v = str(key)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String strOr(String key, [String fallback = '']) => str(key) ?? fallback;

  int? intOrNull(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  int intOr(String key, [int fallback = 0]) => intOrNull(key) ?? fallback;

  double? doubleOrNull(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  bool boolOr(String key, [bool fallback = false]) {
    final v = this[key];
    if (v is bool) return v;
    if (v is String)
      return v == 'true' ? true : (v == 'false' ? false : fallback);
    if (v is num) return v != 0;
    return fallback;
  }

  /// UTC an (ISO-8601). Çözülemezse null.
  DateTime? dateTime(String key) => Ist.tryParse(str(key));

  /// TL değeri → [Money]. Yoksa/çözülemezse null.
  Money? moneyOrNull(String key) => Money.tryFromJson(this[key]);

  /// TL değeri → [Money]; yoksa sıfır.
  Money money(String key) => moneyOrNull(key) ?? Money.zero;

  List<JsonMap> list(String key) => asJsonList(this[key]);

  List<String> stringList(String key) {
    final v = this[key];
    if (v is List)
      return v.whereType<Object>().map((e) => e.toString()).toList();
    return <String>[];
  }

  JsonMap? mapOrNull(String key) {
    final v = this[key];
    return v is Map ? asJsonMap(v) : null;
  }
}
