// Arama sorgusu normalleştirme ve alfabetik gruplama (saf mantık; testlenir).
import '../../../core/util/phone.dart';
import 'customer_models.dart';

abstract final class CustomerSearch {
  static const int maxQueryLength = 100;

  /// Sunucuya giden `q`. Telefon gibi görünen girdi (rakam, boşluk, tire, parantez, +)
  /// rakamlara indirgenir ve ülke kodu atılır: "+90 532 111" → "0532111".
  /// Sunucu ≥3 rakamda boşluk/tire fark etmez; biz yine de tek biçime getiririz.
  static String normalizeQuery(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final looksPhone = RegExp(r'^[\d\s\-+()]+$').hasMatch(t);
    if (looksPhone) {
      var d = PhoneUtil.digits(t);
      if (d.startsWith('0090')) {
        d = d.substring(2);
      }
      if (d.length >= 5 &&
          d.startsWith('90') &&
          (t.startsWith('+') || d.length >= 12)) {
        d = '0${d.substring(2)}';
      }
      if (d.length >= 3) return d;
    }
    return t.length > maxQueryLength ? t.substring(0, maxQueryLength) : t;
  }

  // ---- Türkçe alfabetik sıra ----
  static const String _alphabet = 'abcçdefgğhıijklmnoöprsştuüvyz';

  static String _lower(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  static int _rank(String ch) {
    final i = _alphabet.indexOf(ch);
    if (i >= 0) return i + 100;
    // q, w, x Türk alfabesinde yok: p..r arası / sona yakın sırala.
    return switch (ch) {
      'q' => 100 + _alphabet.indexOf('r'),
      'w' => 100 + _alphabet.indexOf('v'),
      'x' => 100 + _alphabet.indexOf('y'),
      _ => ch.codeUnitAt(0),
    };
  }

  /// Türkçe harf sırasına göre karşılaştırma ("Çelik" C'den sonra, D'den önce).
  static int compareTr(String a, String b) {
    final x = _lower(a), y = _lower(b);
    final n = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      final d = _rank(x[i]) - _rank(y[i]);
      if (d != 0) return d;
    }
    return x.length - y.length;
  }

  /// Grup başlığı: ilk harfin büyüğü ("ı"→"I", "i"→"İ"); harf değilse "#".
  static String groupLetter(String name) {
    final t = name.trim();
    if (t.isEmpty) return '#';
    final c = _lower(t[0]);
    if (_alphabet.contains(c) || 'qwx'.contains(c)) {
      return switch (c) {
        'i' => 'İ',
        'ı' => 'I',
        _ => c.toUpperCase(),
      };
    }
    return '#';
  }

  /// Alfabetik sıralı ve harf gruplu liste. "#" grubu en sonda.
  static List<CustomerGroup> group(Iterable<Customer> customers) {
    final sorted = customers.toList()
      ..sort((a, b) {
        final c = compareTr(a.name, b.name);
        return c != 0 ? c : a.phoneKey.compareTo(b.phoneKey);
      });
    final out = <CustomerGroup>[];
    for (final c in sorted) {
      final l = groupLetter(c.name);
      if (out.isEmpty || out.last.letter != l) {
        out.add(CustomerGroup(l, [c]));
      } else {
        out.last.customers.add(c);
      }
    }
    final hash = out.where((g) => g.letter == '#').toList();
    if (hash.isNotEmpty) {
      out
        ..removeWhere((g) => g.letter == '#')
        ..addAll(hash);
    }
    return out;
  }
}

class CustomerGroup {
  CustomerGroup(this.letter, this.customers);
  final String letter;
  final List<Customer> customers;
}
