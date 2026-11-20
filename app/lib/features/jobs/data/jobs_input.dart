// SAHİBİ: jobs ajanı. Form girdisi (metin) → doğrulanmış modele çeviriciler. Saf ve test edilebilir.
import '../../../core/util/money.dart';
import 'jobs_models.dart';

/// Teklif editöründeki bir satırın ham (metin) girdisi.
class QuoteRowInput {
  const QuoteRowInput({
    required this.desc,
    required this.qty,
    required this.price,
    this.vatIncluded = false,
  });

  final String desc;
  final String qty;
  final String price;
  final bool vatIncluded;

  factory QuoteRowInput.fromItem(QuoteItem it) => QuoteRowInput(
    desc: it.desc,
    qty: formatQty(it.qty),
    price: it.price.format(symbol: false, hideZeroKurus: true),
    vatIncluded: it.vatIncluded,
  );

  /// 2 → "2", 1.5 → "1,5" (Türkçe ondalık virgül).
  static String formatQty(num q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toString().replaceAll('.', ',');

  /// "1,5" / "1.5" / "2" → sayı; çözülemezse null.
  static num? parseQty(String? s) {
    final t = (s ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    if (n == null || !n.isFinite) return null;
    return n;
  }

  static String? validateDesc(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Açıklama girin.';
    if (t.length > QuoteMath.maxDescLength) {
      return 'En çok ${QuoteMath.maxDescLength} karakter.';
    }
    return null;
  }

  static String? validateQty(String? v) {
    final n = parseQty(v);
    if (n == null) return 'Adet girin.';
    if (!(n > 0)) return 'Adet 0\'dan büyük olmalı.';
    return null;
  }

  static String? validatePrice(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Fiyat girin.';
    final m = Money.parseUserInput(t);
    if (m == null) return 'Geçerli bir tutar girin.';
    if (m.isNegative) return 'Fiyat negatif olamaz.';
    return null;
  }

  bool get isValid =>
      validateDesc(desc) == null &&
      validateQty(qty) == null &&
      validatePrice(price) == null;

  /// Geçerliyse kalem; değilse null.
  QuoteItem? toItem() {
    if (!isValid) return null;
    return QuoteItem(
      desc: desc.trim(),
      qty: parseQty(qty)!,
      price: Money.parseUserInput(price)!,
      vatIncluded: vatIncluded,
    );
  }
}

/// Satır listesi → kalemler (geçersiz satırlar atlanır) ve toplam.
class QuoteDraft {
  const QuoteDraft(this.rows);
  final List<QuoteRowInput> rows;

  List<QuoteItem> get validItems =>
      rows.map((r) => r.toItem()).whereType<QuoteItem>().toList();

  bool get allValid => rows.isNotEmpty && rows.every((r) => r.isValid);

  QuoteTotals get totals => QuoteMath.compute(validItems);
}
