// Form doğrulama ve seçenekler (saf mantık; testlenir).
import '../../../core/config/brand_profile.dart';
import '../../../core/util/money.dart';
import 'finance_models.dart';

abstract final class FinanceValidators {
  /// NUMERIC(12,2) üst sınırı: 9.999.999.999,99
  static final Money maxAmount = Money.fromKurus(999999999999);

  /// Tutar metni → Money. Hata mesajı varsa ikinci değer dolu.
  static ({Money? value, String? error}) amount(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return (value: null, error: 'Tutarı girin.');
    if (s.contains('-') || s.contains('−')) {
      return (value: null, error: 'Tutar negatif olamaz.');
    }
    // Virgülden sonra en çok 2 hane (kuruş doğruluğu).
    final comma = s.lastIndexOf(',');
    if (comma >= 0 && s.length - comma - 1 > 2) {
      return (value: null, error: 'En çok 2 ondalık hane girin (kuruş).');
    }
    final m = Money.parseUserInput(s);
    if (m == null) {
      return (value: null, error: 'Geçerli bir tutar girin (örn. 12.500,50).');
    }
    if (!m.isPositive) {
      return (value: null, error: 'Tutar sıfırdan büyük olmalı.');
    }
    if (m > maxAmount) return (value: null, error: 'Tutar çok büyük.');
    return (value: m, error: null);
  }

  static String? category(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'Kategori seçin ya da yazın.';
    if (s.length > 100) return 'Kategori en çok 100 karakter olabilir.';
    return null;
  }

  static String? note(String? raw) =>
      (raw ?? '').length > 500 ? 'Not en çok 500 karakter olabilir.' : null;
}

/// Ödeme yöntemi seçeneği. Çek/senet sonra invoices_vat ile gelecek: bu liste
/// [paymentMethodOptionsProvider] ile genişletilir (sunucu sözleşmesi izin verdiğinde).
class PaymentMethodOption {
  const PaymentMethodOption(this.api, this.label);
  final String api;
  final String label;

  static const List<PaymentMethodOption> standard = [
    PaymentMethodOption('Havale', 'Havale'),
    PaymentMethodOption('Nakit', 'Nakit'),
    PaymentMethodOption('Kredi Kartı', 'Kredi Kartı'),
  ];
}

/// Gider kategorileri: önce marka sözlüğü (`expenseCategoryLabels`), yoksa sektör nötr varsayılanlar.
abstract final class FinanceCategories {
  static const List<String> business = [
    'İşyeri kirası',
    'Elektrik/Su/Doğalgaz',
    'Maaş',
    'Sigorta/SGK',
    'Malzeme',
    'Yakıt',
    'Araç bakım',
    'Vergi',
    'Telefon/İnternet',
    'Diğer',
  ];
  static const List<String> personal = [
    'Ev kirası',
    'Elektrik/Su/Doğalgaz',
    'Market',
    'Sağlık',
    'Diğer',
  ];
  static const List<String> project = [
    'Malzeme',
    'İşçilik',
    'Nakliye',
    'Taşeron',
    'Yakıt',
    'Diğer',
  ];

  /// Seçilebilir kategori adları (api değeri). [recent]: son kullanılanlar başa gelir (en çok 4).
  static List<String> options(
    Glossary terms, {
    required ScopeView scope,
    required bool hasProject,
    Iterable<String> recent = const [],
  }) {
    final fromBrand = terms.expenseCategories.isNotEmpty
        ? terms.expenseCategories
        : terms.expenseCategoryLabels.keys.toList();
    final base = fromBrand.isNotEmpty
        ? fromBrand
        : hasProject
        ? project
        : (scope == ScopeView.personal ? personal : business);
    final out = <String>[];
    for (final r in recent) {
      final t = r.trim();
      if (t.isNotEmpty && !out.contains(t) && out.length < 4) out.add(t);
    }
    for (final b in base) {
      if (!out.contains(b)) out.add(b);
    }
    return out;
  }

  /// Gösterim etiketi (sözlük varsa çevirir; yoksa olduğu gibi).
  static String label(Glossary terms, String api) {
    final t = terms.expenseCategoryLabel(api);
    return t.isEmpty ? api : t;
  }
}
