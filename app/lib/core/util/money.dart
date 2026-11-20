// Para: TL ondalık double ile ASLA hesap yapılmaz. Tutar kuruş (int) olarak
// tutulur; toplama/çıkarma/KDV hep tamsayı aritmetiğidir.
import 'package:flutter/foundation.dart';

@immutable
class Money implements Comparable<Money> {
  const Money._(this.kurus);

  /// Kuruş cinsinden tutar (1 TL = 100 kuruş). Negatif olabilir (ör. ilave iş indirimi).
  final int kurus;

  static const Money zero = Money._(0);

  factory Money.fromKurus(int kurus) => Money._(kurus);

  /// TL (ondalık) → Money. Yuvarlama en yakın kuruşa (0,5 sıfırdan uzağa).
  factory Money.fromTl(num tl) => Money._((tl * 100).round());

  /// Sunucudan gelen değer (sayı ya da noktalı metin) → Money; çözülemezse null.
  static Money? tryFromJson(Object? v) {
    if (v == null) return null;
    if (v is Money) return v;
    if (v is int) return Money._(v * 100);
    if (v is num) return v.isFinite ? Money.fromTl(v) : null;
    if (v is String) return _parseDecimalString(v.trim());
    return null;
  }

  factory Money.fromJson(Object? v) => tryFromJson(v) ?? zero;

  /// Kullanıcının yazdığı tutar (Türkçe biçim): "12.500", "12.500,50", "1250,5", "₺ 99".
  /// Kural: virgül varsa ondalıktır, noktalar binliktir. Virgül yoksa: tek nokta ve
  /// sonrasında tam 3 hane ve baştaki sayı 1-3 haneli (0 ile başlamayan) ise binliktir
  /// ("12.500" = 12500); aksi halde nokta ondalıktır ("12.5" = 12,5). 2'den fazla ondalık
  /// hane geçersizdir (null). Sunucu sözleşmesi virgülü KABUL ETMEZ; bu yüzden gönderirken
  /// [toApiString] kullanın.
  static Money? parseUserInput(String input) {
    var s = input
        .replaceAll('₺', '')
        .replaceAll(RegExp(r'TL', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;
    var negative = false;
    if (s.startsWith('-') || s.startsWith('−')) {
      negative = true;
      s = s.substring(1);
    }
    if (s.isEmpty) return null;
    String normalized;
    if (s.contains(',')) {
      if (','.allMatches(s).length > 1) return null;
      normalized = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (s.contains('.')) {
      final parts = s.split('.');
      final last = parts.last;
      final isThousands =
          parts.length > 2 ||
          (last.length == 3 &&
              parts.first.isNotEmpty &&
              parts.first.length <= 3 &&
              !parts.first.startsWith('0'));
      normalized = isThousands ? parts.join() : s;
    } else {
      normalized = s;
    }
    final m = _parseDecimalString(normalized);
    if (m == null) return null;
    return negative ? -m : m;
  }

  // "1250.50" / "-3.5" / "12" → Money (en çok 2 ondalık; fazlası yuvarlanır).
  static Money? _parseDecimalString(String s) {
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(s);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final frac = match.group(3) ?? '';
    var k = whole * 100;
    if (frac.isNotEmpty) {
      final padded = frac.padRight(3, '0');
      k += int.parse(padded.substring(0, 2));
      if (int.parse(padded[2]) >= 5) k += 1; // en yakın kuruşa yuvarla
    }
    return Money._(sign * k);
  }

  Money operator +(Money o) => Money._(kurus + o.kurus);
  Money operator -(Money o) => Money._(kurus - o.kurus);
  Money operator -() => Money._(-kurus);
  bool operator <(Money o) => kurus < o.kurus;
  bool operator <=(Money o) => kurus <= o.kurus;
  bool operator >(Money o) => kurus > o.kurus;
  bool operator >=(Money o) => kurus >= o.kurus;

  /// Adet ile çarpma (ör. 2,5 adet x birim fiyat). Sonuç en yakın kuruşa yuvarlanır.
  Money times(num quantity) => Money._((kurus * quantity).round());

  /// KDV tutarı: [percent] yüzde (sözleşme: sabit %20). Tamsayı aritmetiği, yarım yukarı.
  Money vat([int percent = 20]) => Money._(_divRound(kurus * percent, 100));

  /// Fiyata KDV eklenmiş hâli.
  Money withVat([int percent = 20]) => this + vat(percent);

  /// KDV DAHİL tutardan KDV hariç tutar ("vatIncluded: true" kalemleri için).
  Money excludingVat([int percent = 20]) =>
      Money._(_divRound(kurus * 100, 100 + percent));

  Money abs() => Money._(kurus.abs());
  Money max(Money o) => kurus >= o.kurus ? this : o;
  Money min(Money o) => kurus <= o.kurus ? this : o;

  /// Negatif ise sıfır ("kalan bakiye" gibi: Σ max(x, 0)).
  Money clampNonNegative() => kurus < 0 ? zero : this;

  bool get isZero => kurus == 0;
  bool get isNegative => kurus < 0;
  bool get isPositive => kurus > 0;

  /// YALNIZCA gösterim/grafik için; hesap yapmayın.
  double toTl() => kurus / 100;

  /// Sunucuya gönderim biçimi: noktalı metin, 2 ondalık ("1250.50"). Virgül yok.
  String toApiString() {
    final a = kurus.abs();
    final s = '${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
    return kurus < 0 ? '-$s' : s;
  }

  /// JSON kodlayıcı bunu kullanır: noktalı metin (sözleşme kabul eder).
  String toJson() => toApiString();

  /// Gösterim: "₺12.450,00", negatif: "−₺1.250,00". [hideZeroKurus] true iken tam
  /// liralarda kuruş gizlenir ("₺12.450").
  String format({bool symbol = true, bool hideZeroKurus = false}) {
    final a = kurus.abs();
    final lira = _groupThousands(a ~/ 100);
    final kr = a % 100;
    final body = (hideZeroKurus && kr == 0)
        ? lira
        : '$lira,${kr.toString().padLeft(2, '0')}';
    final prefix = kurus < 0 ? '−' : '';
    return '$prefix${symbol ? '₺' : ''}$body';
  }

  static String _groupThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // a / b, yarım sıfırdan uzağa yuvarlama (tamsayı).
  static int _divRound(int a, int b) {
    final neg = a < 0;
    final q = ((a.abs() * 2 + b) ~/ (b * 2));
    return neg ? -q : q;
  }

  static Money sum(Iterable<Money> items) =>
      items.fold(zero, (acc, m) => acc + m);

  @override
  int compareTo(Money other) => kurus.compareTo(other.kurus);

  @override
  bool operator ==(Object other) => other is Money && other.kurus == kurus;

  @override
  int get hashCode => kurus.hashCode;

  @override
  String toString() => 'Money(${format()})';
}
