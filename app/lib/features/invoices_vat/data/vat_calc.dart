// Saf hesap yardımcıları. SUNUCU sonuçları esastır; burası yalnız ÖNİZLEME içindir
// (form alt toplamı, taksit sihirbazı). Hepsi tamsayı kuruş aritmetiğidir (double yok).
// Uygulama fatura KESMEZ; bunlar hukuki/mali tavsiye değildir.
import 'package:flutter/foundation.dart';

import '../../../core/util/money.dart';
import 'invoices_vat_models.dart';

int _divRound(int a, int b) {
  final neg = (a < 0) != (b < 0);
  final q = (a.abs() * 2 + b.abs()) ~/ (b.abs() * 2);
  return neg ? -q : q;
}

/// Oran yüzde sayısı → baz puan (yüzde*100): 20 → 2000, 7,5 → 750. Tamsayı aritmetiği için.
int _basisPoints(num percent) => (percent * 100).round();

@immutable
class VatPreview {
  const VatPreview({
    required this.matrah,
    required this.kdv,
    required this.tevkifat,
    required this.tutar,
    required this.odenecek,
  });
  final Money matrah;
  final Money kdv;
  final Money tevkifat;

  /// Genel toplam (KDV dahil, tevkifat DÜŞÜLMEDEN).
  final Money tutar;

  /// Ödenecek = genel toplam − tevkifat.
  final Money odenecek;
}

abstract final class VatCalc {
  /// Belgedeki KDV ile hesaplanan arasındaki fark bu kuruşu aşarsa sunucu 400 `kdv_mismatch` verir.
  static const int mismatchToleranceKurus = 5;

  /// KDV hariç matrahtan: kdv = matrah × oran, tevkifat = kdv × pay/payda.
  static VatPreview fromMatrah(
    Money matrah,
    num ratePercent, {
    Withholding? withholding,
  }) {
    final kdv = Money.fromKurus(
      _divRound(matrah.kurus * _basisPoints(ratePercent), 10000),
    );
    return _build(matrah, kdv, withholding);
  }

  /// KDV DAHİL tutardan: matrah = tutar / (1 + oran).
  static VatPreview fromGross(
    Money gross,
    num ratePercent, {
    Withholding? withholding,
  }) {
    final bp = _basisPoints(ratePercent);
    final matrah = Money.fromKurus(_divRound(gross.kurus * 10000, 10000 + bp));
    // KDV = tutar − matrah: toplam tam tutuyor (kuruş kaybolmaz).
    final kdv = gross - matrah;
    return _build(matrah, kdv, withholding);
  }

  static VatPreview _build(Money matrah, Money kdv, Withholding? w) {
    final tevk = (w != null && w.valid)
        ? Money.fromKurus(_divRound(kdv.kurus * w.pay, w.payda))
        : Money.zero;
    final tutar = matrah + kdv;
    return VatPreview(
      matrah: matrah,
      kdv: kdv,
      tevkifat: tevk,
      tutar: tutar,
      odenecek: tutar - tevk,
    );
  }

  /// Belgedeki KDV hesaplananla uyuşuyor mu (tolerans ≤ 5 kuruş).
  static bool kdvMatches(Money documentKdv, Money computed) =>
      (documentKdv.kurus - computed.kurus).abs() <= mismatchToleranceKurus;

  /// Dönem önizlemesi (cihazda, tahmini): hesaplanan = Σ giden KDV − giden tevkifat;
  /// indirilecek = Σ gelen indirilebilir KDV; net = hesaplanan − indirilecek − devreden;
  /// ödenecek = max(net, 0); devreden = max(−net, 0). İptal/taslak sayılmaz.
  static PeriodPreview periodPreview(
    Iterable<Invoice> invoices, {
    Money previousCarry = Money.zero,
  }) {
    var hesaplanan = Money.zero;
    var indirilecek = Money.zero;
    var indirilemeyen = Money.zero;
    for (final i in invoices) {
      if (i.isCancelled || i.status == InvoiceStatus.taslak) continue;
      if (i.direction == InvoiceDirection.giden) {
        hesaplanan += i.kdv - i.tevkifat;
      } else if (i.direction == InvoiceDirection.gelen) {
        if (i.kdvDeductible) {
          indirilecek += i.kdv;
        } else {
          indirilemeyen += i.kdv;
        }
      }
    }
    final net = hesaplanan - indirilecek - previousCarry;
    return PeriodPreview(
      hesaplanan: hesaplanan,
      indirilecek: indirilecek,
      indirilemeyen: indirilemeyen,
      net: net,
      odenecek: net.clampNonNegative(),
      devreden: (-net).clampNonNegative(),
    );
  }
}

@immutable
class PeriodPreview {
  const PeriodPreview({
    required this.hesaplanan,
    required this.indirilecek,
    required this.indirilemeyen,
    required this.net,
    required this.odenecek,
    required this.devreden,
  });
  final Money hesaplanan;
  final Money indirilecek;
  final Money indirilemeyen;
  final Money net;
  final Money odenecek;
  final Money devreden;
}

// ---------------------------------------------------------------- Taksit planı

@immutable
class PlannedInstallment {
  const PlannedInstallment({
    required this.index,
    required this.dueDate,
    required this.amount,
  });

  /// 1'den başlar.
  final int index;

  /// `YYYY-AA-GG`
  final String dueDate;
  final Money amount;
}

abstract final class InstallmentPlanner {
  static const int maxCount = 60;

  /// Toplamı [count] eşit parçaya böler; kuruş artığı SON taksite eklenir (sunucuyla aynı kural).
  /// Vadeler [firstDue] + (i × [intervalDays]) gündür. Geçersiz girişte boş liste.
  static List<PlannedInstallment> generate({
    required Money total,
    required int count,
    required String firstDue,
    int intervalDays = 30,
  }) {
    if (!total.isPositive || count < 1 || count > maxCount) return const [];
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(firstDue);
    if (m == null || intervalDays < 1) return const [];
    final start = DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    final base = total.kurus ~/ count;
    final remainder = total.kurus - base * count;
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return [
      for (var i = 0; i < count; i++)
        PlannedInstallment(
          index: i + 1,
          dueDate: fmt(start.add(Duration(days: intervalDays * i))),
          amount: Money.fromKurus(i == count - 1 ? base + remainder : base),
        ),
    ];
  }
}

// ---------------------------------------------------------------- VKN / TCKN

enum TaxIdState { empty, badLength, checksumFailed, ok }

abstract final class TaxIdCheck {
  /// e-Arşivde nihai tüketici için kullanılan sabit numara (sağlama toplamı tutmaz, geçerlidir).
  static const String consumerPlaceholder = '11111111111';

  /// Opsiyonel alan: boş serbest; 10 (VKN) ya da 11 (TCKN) hane ZORUNLU; sağlama toplamı
  /// tutmazsa SERT hata değil UYARI ([TaxIdState.checksumFailed]).
  static TaxIdState check(String? raw) {
    final d = (raw ?? '').replaceAll(RegExp(r'\s'), '');
    if (d.isEmpty) return TaxIdState.empty;
    if (!RegExp(r'^\d+$').hasMatch(d) || (d.length != 10 && d.length != 11)) {
      return TaxIdState.badLength;
    }
    if (d == consumerPlaceholder) return TaxIdState.ok;
    final ok = d.length == 10 ? _vknOk(d) : _tcknOk(d);
    return ok ? TaxIdState.ok : TaxIdState.checksumFailed;
  }

  static bool _tcknOk(String d) {
    if (d.startsWith('0')) return false;
    final n = d.split('').map(int.parse).toList();
    final odd = n[0] + n[2] + n[4] + n[6] + n[8];
    final even = n[1] + n[3] + n[5] + n[7];
    final d10 = (((odd * 7) - even) % 10 + 10) % 10;
    final d11 = n.sublist(0, 10).fold<int>(0, (a, b) => a + b) % 10;
    return n[9] == d10 && n[10] == d11;
  }

  static bool _vknOk(String d) {
    final n = d.split('').map(int.parse).toList();
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      final tmp = (n[i] + (9 - i)) % 10;
      final p = (tmp * (1 << (9 - i))) % 9;
      sum += (tmp != 0 && p == 0) ? 9 : p;
    }
    return (10 - (sum % 10)) % 10 == n[9];
  }
}
