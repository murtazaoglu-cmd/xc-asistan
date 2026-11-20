// Stok modelleri (sözleşme §11). Satır:
// {id,name,unit,stock_quantity,low_stock_threshold,note,updated_at,owner_id}.
// Düşük stok: stock_quantity ≤ low_stock_threshold (ana ekranda `min_stock` adıyla).
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';

@immutable
class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    this.unit = 'adet',
    this.quantity = 0,
    this.minStock = 5,
    this.note,
    this.updatedAt,
    this.ownerId,
  });

  final String id;
  final String name;
  final String unit;
  final double quantity;

  /// `low_stock_threshold` (ya da `min_stock`).
  final double minStock;
  final String? note;
  final DateTime? updatedAt;
  final String? ownerId;

  bool get isOut => quantity <= 0;

  /// Düşük stok: miktar ≤ eşik.
  bool get isLow => quantity <= minStock;

  factory StockItem.fromJson(JsonMap j) => StockItem(
    id: j.strOr('id'),
    name: j.strOr('name'),
    unit: j.strOrNull('unit') ?? 'adet',
    quantity: j.doubleOrNull('stock_quantity') ?? 0,
    minStock:
        j.doubleOrNull('low_stock_threshold') ??
        j.doubleOrNull('min_stock') ??
        5,
    note: j.strOrNull('note'),
    updatedAt: j.dateTime('updated_at'),
    ownerId: j.strOrNull('owner_id'),
  );

  StockItem copyWith({double? quantity}) => StockItem(
    id: id,
    name: name,
    unit: unit,
    quantity: quantity ?? this.quantity,
    minStock: minStock,
    note: note,
    updatedAt: updatedAt,
    ownerId: ownerId,
  );
}

/// Miktar biçimleme / ayrıştırma (virgüllü Türkçe girdi, ondalık birimler: kg, metre).
abstract final class StockQty {
  static const double max = 1000000000;

  /// 12 → "12"; 2.5 → "2,5"; 0.125 → "0,125" (en çok 3 ondalık).
  static String format(double q) {
    final r = round(q);
    if (r == r.roundToDouble()) return r.toInt().toString();
    var s = r.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
  }

  /// Kayan nokta birikimini önler (0.1+0.2).
  static double round(double q) => (q * 1000).roundToDouble() / 1000;

  /// "12,5" / "12.5" / "1.250" (bin) → double; geçersiz/negatif/çok büyükse null.
  static double? parse(String input) {
    var s = input.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;
    if (s.contains(',')) {
      if (','.allMatches(s).length > 1) return null;
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', ''); // 1.250 → 1250
    }
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(s)) return null;
    final v = double.tryParse(s);
    if (v == null || v < 0 || v > max) return null;
    return v;
  }

  /// Sunucuya: tam sayıysa int, değilse ondalık (negatif olmayan sayı).
  static num toJson(double q) {
    final r = round(q);
    return r == r.roundToDouble() ? r.toInt() : r;
  }
}

/// Form girdisi.
@immutable
class StockInput {
  const StockInput({
    required this.name,
    this.unit = 'adet',
    this.quantity = 0,
    this.minStock = 5,
    this.note = '',
  });

  final String name;
  final String unit;
  final double quantity;
  final double minStock;
  final String note;

  JsonMap toJson() => {
    'name': name.trim(),
    'unit': unit.trim().isEmpty ? 'adet' : unit.trim(),
    'stock_quantity': StockQty.toJson(quantity),
    'low_stock_threshold': StockQty.toJson(minStock),
    'note': note.trim().isEmpty ? null : note.trim(),
  };
}

abstract final class StockValidators {
  static String? name(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Malzeme adı girin.';
    if (t.length > 200) return 'Ad en fazla 200 karakter olabilir.';
    return null;
  }

  static String? unit(String? v) => (v ?? '').trim().length > 30
      ? 'Birim en fazla 30 karakter olabilir.'
      : null;

  /// Negatif olmayan sayı (miktar ve asgari stok).
  static String? quantity(String? v, {String field = 'Miktar'}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '$field girin.';
    if (StockQty.parse(t) == null) {
      return '$field sıfır ya da pozitif bir sayı olmalı.';
    }
    return null;
  }

  static String? note(String? v) => (v ?? '').trim().length > 2000
      ? 'Not en fazla 2000 karakter olabilir.'
      : null;
}
