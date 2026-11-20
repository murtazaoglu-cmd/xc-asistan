// Fatura ve KDV modelleri: /mnt/user-data/outputs/mobile-api-contract-B.md ile birebir.
// Para alanları `*_kurus` TAMSAYI kuruştur ([Money]); oran yüzde sayısıdır (20 = %20);
// tarih `YYYY-AA-GG` (İstanbul günü). Bilinmeyen/eksik alan çökertmez.
// Doğrulanmamış oran/tarih/tevkifat için [Confirmation] ("Mali müşavire teyit edin").
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

/// Kuruş alanı: tamsayı ya da (yanlışlıkla) ondalık gelirse en yakın kuruşa yuvarlar.
Money? kurusOrNull(JsonMap j, String key) {
  final v = j[key];
  if (v is int) return Money.fromKurus(v);
  if (v is num) return v.isFinite ? Money.fromKurus(v.round()) : null;
  if (v is String) {
    final n = num.tryParse(v.trim());
    return n == null ? null : Money.fromKurus(n.round());
  }
  return null;
}

Money kurusOf(JsonMap j, String key) => kurusOrNull(j, key) ?? Money.zero;

/// Kabloya `*_kurus` olarak giden tamsayı.
int toKurus(Money m) => m.kurus;

/// "YYYY-AA-GG" → İstanbul günü başlangıcı (UTC an); çözülemezse null.
DateTime? parseDay(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.length < 10) return null;
  return Ist.tryParse(t);
}

/// UTC an → "YYYY-AA-GG" (İstanbul günü).
String dayKey(DateTime instant) {
  final w = Ist.wall(instant);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${w.year.toString().padLeft(4, '0')}-${two(w.month)}-${two(w.day)}';
}

// ---------------------------------------------------------------- Teyit

/// "Mali müşavire teyit edin" bayrağı. Biçimler: `confirmation{needed,reasons[]}`,
/// `needs_confirmation` + `confirmation_reasons[]`, `verified:false`.
@immutable
class Confirmation {
  const Confirmation({this.needed = false, this.reasons = const []});
  final bool needed;
  final List<String> reasons;

  static const Confirmation none = Confirmation();

  factory Confirmation.fromJson(JsonMap j) {
    final nested = j.mapOrNull('confirmation');
    var needed = false;
    var reasons = <String>[];
    if (nested != null) {
      needed = nested.boolOr('needed') || nested.boolOr('needs_confirmation');
      reasons = nested.stringList('reasons');
    }
    if (j.boolOr('needs_confirmation')) needed = true;
    if (j.containsKey('verified') && !j.boolOr('verified', true)) needed = true;
    final top = j.stringList('confirmation_reasons');
    if (top.isNotEmpty) reasons = {...reasons, ...top}.toList();
    if (reasons.isNotEmpty && nested == null && top.isEmpty) needed = true;
    return Confirmation(needed: needed, reasons: reasons);
  }
}

// ---------------------------------------------------------------- Enum'lar

enum InvoiceDirection {
  giden('giden', 'Giden', 'Kestiğim faturalar'),
  gelen('gelen', 'Gelen', 'Aldığım faturalar');

  const InvoiceDirection(this.api, this.label, this.hint);
  final String api;
  final String label;
  final String hint;
  static InvoiceDirection? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum InvoiceStatus {
  taslak('taslak', 'Taslak'),
  kesildi('kesildi', 'Kesildi'),
  gonderildi('gonderildi', 'Gönderildi'),
  odendi('odendi', 'Ödendi'),
  iptal('iptal', 'İptal');

  const InvoiceStatus(this.api, this.label);
  final String api;
  final String label;
  static InvoiceStatus? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }

  /// Yalnız taslak/iptal silinebilir (sözleşme).
  bool get deletable => this == taslak || this == iptal;
}

/// Belge türü kodları (`invoice_type`). Etiketi sunucu `invoice_type_label` ile de verir.
enum InvoiceType {
  eFatura('e-fatura', 'e-Fatura'),
  eArsiv('e-arsiv', 'e-Arşiv Fatura'),
  kagit('kagit', 'Kâğıt fatura'),
  giderPusulasi('gider-pusulasi', 'Gider pusulası'),
  serbestMeslek('serbest-meslek', 'Serbest meslek makbuzu'),
  musthsil('musthsil', 'Müstahsil makbuzu'),
  diger('diger', 'Diğer');

  const InvoiceType(this.api, this.label);
  final String api;
  final String label;
  static InvoiceType? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

/// Tahsilat yöntemi (plan satırı ve "Ödendi işaretle"). Çek/Senet yalnız plan/fatura uçlarında.
enum ScheduleMethod {
  havale('Havale'),
  nakit('Nakit'),
  krediKarti('Kredi Kartı'),
  cek('Çek'),
  senet('Senet');

  const ScheduleMethod(this.api);
  final String api;
  String get label => api;
  bool get isInstrument => this == cek || this == senet;
  static ScheduleMethod? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

enum ScheduleKind {
  taksit('taksit', 'Taksit'),
  vade('vade', 'Vade'),
  bakiye('bakiye', 'Bakiye'),
  cek('cek', 'Çek'),
  senet('senet', 'Senet');

  const ScheduleKind(this.api, this.label);
  final String api;
  final String label;
  static ScheduleKind? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }
}

// ---------------------------------------------------------------- Fatura

@immutable
class InvoiceWarning {
  const InvoiceWarning({required this.code, required this.message});
  final String code;
  final String message;
  factory InvoiceWarning.fromJson(JsonMap j) =>
      InvoiceWarning(code: j.strOr('code'), message: j.strOr('message'));
}

@immutable
class InvoiceFile {
  const InvoiceFile({
    required this.id,
    required this.name,
    this.url,
    this.mime,
    this.sizeBytes,
  });
  final String id;
  final String name;

  /// İMZALI URL (10 dk). Saklanmaz; her açılışta fatura yeniden çekilir.
  final String? url;
  final String? mime;
  final int? sizeBytes;

  factory InvoiceFile.fromJson(JsonMap j) => InvoiceFile(
    id: j.strOr('id'),
    name: j.strOrNull('file_name') ?? j.strOrNull('name') ?? 'Ek dosya',
    url: j.strOrNull('file_url') ?? j.strOrNull('url'),
    mime: j.strOrNull('mime') ?? j.strOrNull('content_type'),
    sizeBytes: j.intOrNull('size'),
  );

  String get lowerName => name.toLowerCase();
  bool get isImage =>
      (mime ?? '').startsWith('image/') ||
      RegExp(r'\.(png|jpe?g|webp|gif|heic|heif)$').hasMatch(lowerName);
  bool get isPdf => (mime ?? '').contains('pdf') || lowerName.endsWith('.pdf');
}

/// Tevkifat oranı "pay/payda" (ör. 4/10).
@immutable
class Withholding {
  const Withholding(this.pay, this.payda);
  final int pay;
  final int payda;
  bool get valid => pay > 0 && payda > 0 && pay <= payda;
  String get label => '$pay/$payda';

  /// "4/10" | {pay,payda} | {numerator,denominator}; çözülemezse null.
  static Withholding? parse(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final m = asJsonMap(v);
      final p = m.intOrNull('pay') ?? m.intOrNull('numerator');
      final d = m.intOrNull('payda') ?? m.intOrNull('denominator');
      if (p == null || d == null) return null;
      return Withholding(p, d);
    }
    if (v is String) {
      final m = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(v);
      if (m == null) return null;
      return Withholding(int.parse(m.group(1)!), int.parse(m.group(2)!));
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Withholding && other.pay == pay && other.payda == payda;
  @override
  int get hashCode => Object.hash(pay, payda);
}

@immutable
class Invoice {
  const Invoice({
    required this.id,
    required this.direction,
    required this.matrah,
    required this.kdv,
    required this.tutar,
    required this.odenecek,
    this.tevkifat = Money.zero,
    this.kdvOran,
    this.withholding,
    this.statusRaw = '',
    this.invoiceTypeRaw,
    this.invoiceTypeLabel,
    this.invoiceNo,
    this.ettn,
    this.counterparty,
    this.counterpartyTaxId,
    this.issueDate,
    this.dueDate,
    this.paidAt,
    this.customerId,
    this.customerName,
    this.projectId,
    this.projectCode,
    this.note,
    this.overdue = false,
    this.kdvDeductible = true,
    this.kdvExemptionReason,
    this.files = const [],
    this.warnings = const [],
    this.confirmation = Confirmation.none,
    this.period,
  });

  final String id;
  final InvoiceDirection? direction;
  final Money matrah;
  final Money kdv;
  final Money tevkifat;
  final Money tutar;
  final Money odenecek;
  final num? kdvOran;
  final Withholding? withholding;
  final String statusRaw;
  final String? invoiceTypeRaw;
  final String? invoiceTypeLabel;
  final String? invoiceNo;
  final String? ettn;
  final String? counterparty;
  final String? counterpartyTaxId;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? customerId;
  final String? customerName;
  final String? projectId;
  final String? projectCode;
  final String? note;
  final bool overdue;
  final bool kdvDeductible;
  final String? kdvExemptionReason;
  final List<InvoiceFile> files;
  final List<InvoiceWarning> warnings;
  final Confirmation confirmation;
  final String? period;

  InvoiceStatus? get status => InvoiceStatus.fromApi(statusRaw);
  InvoiceType? get type => InvoiceType.fromApi(invoiceTypeRaw);
  String get typeLabel =>
      invoiceTypeLabel ?? type?.label ?? invoiceTypeRaw ?? 'Belge';
  bool get isPaid => status == InvoiceStatus.odendi;
  bool get isCancelled => status == InvoiceStatus.iptal;
  bool get canMarkPaid => !isPaid && !isCancelled;

  /// Ekranda ham UUID gösterilmez: "FT-023" ya da karşı taraf adı.
  String get title {
    final no = invoiceNo?.trim();
    final cp = counterparty?.trim();
    if (no != null && no.isNotEmpty && cp != null && cp.isNotEmpty) {
      return '$no · $cp';
    }
    if (cp != null && cp.isNotEmpty) return cp;
    if (no != null && no.isNotEmpty) return no;
    return typeLabel;
  }

  factory Invoice.fromJson(JsonMap j) {
    final matrah = kurusOf(j, 'matrah_kurus');
    final kdv = kurusOf(j, 'kdv_kurus');
    final tevk = kurusOf(j, 'tevkifat_kurus');
    final tutar = kurusOrNull(j, 'tutar_kurus') ?? (matrah + kdv);
    return Invoice(
      id: j.strOr('id'),
      direction: InvoiceDirection.fromApi(j.str('direction')),
      matrah: matrah,
      kdv: kdv,
      tevkifat: tevk,
      tutar: tutar,
      odenecek: kurusOrNull(j, 'odenecek_kurus') ?? (tutar - tevk),
      kdvOran: j['kdv_oran'] is num
          ? j['kdv_oran'] as num
          : num.tryParse(j.str('kdv_oran') ?? ''),
      withholding:
          Withholding.parse(j['tevkifat_oran']) ??
          Withholding.parse(j['tevkifat']),
      statusRaw: j.strOr('status'),
      invoiceTypeRaw: j.strOrNull('invoice_type'),
      invoiceTypeLabel: j.strOrNull('invoice_type_label'),
      invoiceNo: j.strOrNull('invoice_no'),
      ettn: j.strOrNull('ettn'),
      counterparty: j.strOrNull('counterparty'),
      counterpartyTaxId: j.strOrNull('counterparty_tax_id'),
      issueDate: parseDay(j.str('issue_date')),
      dueDate: parseDay(j.str('due_date')),
      paidAt: parseDay(j.str('paid_at')),
      customerId: j.strOrNull('customer_id'),
      customerName: j.strOrNull('customer_name'),
      projectId: j.strOrNull('project_id'),
      projectCode: j.strOrNull('project_code'),
      note: j.strOrNull('note'),
      overdue: j.boolOr('overdue'),
      kdvDeductible: j.boolOr('kdv_indirilebilir', true),
      kdvExemptionReason: j.strOrNull('kdv_istisna_nedeni'),
      files: j.list('files').map(InvoiceFile.fromJson).toList(),
      warnings: j.list('warnings').map(InvoiceWarning.fromJson).toList(),
      confirmation: Confirmation.fromJson(j),
      period: j.strOrNull('period'),
    );
  }
}

// ---------------------------------------------------------------- Oranlar

@immutable
class VatRate {
  const VatRate({
    required this.id,
    required this.percent,
    required this.label,
    this.isDefault = false,
    this.confirmation = Confirmation.none,
  });
  final String id;

  /// Yüzde sayısı (20 = %20).
  final num percent;
  final String label;
  final bool isDefault;
  final Confirmation confirmation;

  String get percentLabel => '%${formatPercent(percent)}';

  factory VatRate.fromJson(JsonMap j) {
    final p = j['rate'] ?? j['oran'] ?? j['percent'] ?? j['kdv_oran'];
    final percent = p is num ? p : (num.tryParse('$p') ?? 0);
    return VatRate(
      id: j.strOr('id', formatPercent(percent)),
      percent: percent,
      label:
          j.strOrNull('label') ??
          j.strOrNull('name') ??
          '%${formatPercent(percent)}',
      isDefault: j.boolOr('is_default') || j.boolOr('default'),
      confirmation: Confirmation.fromJson(j),
    );
  }
}

String formatPercent(num p) => p == p.roundToDouble()
    ? p.round().toString()
    : p.toString().replaceAll('.', ',');

@immutable
class WithholdingType {
  const WithholdingType({
    required this.id,
    required this.label,
    required this.pay,
    required this.payda,
    this.confirmation = Confirmation.none,
  });
  final String id;
  final String label;
  final int pay;
  final int payda;
  final Confirmation confirmation;
  Withholding get ratio => Withholding(pay, payda);

  factory WithholdingType.fromJson(JsonMap j) {
    final pay = j.intOrNull('pay') ?? j.intOrNull('numerator') ?? 0;
    final payda = j.intOrNull('payda') ?? j.intOrNull('denominator') ?? 10;
    return WithholdingType(
      id: j.strOr('id', '$pay/$payda'),
      label: j.strOrNull('label') ?? j.strOrNull('name') ?? '$pay/$payda',
      pay: pay,
      payda: payda,
      confirmation: Confirmation.fromJson(j),
    );
  }
}

@immutable
class VatRates {
  const VatRates({
    this.rates = const [],
    this.withholdingTypes = const [],
    this.disclaimer,
  });
  final List<VatRate> rates;
  final List<WithholdingType> withholdingTypes;
  final String? disclaimer;

  VatRate? get defaultRate {
    for (final r in rates) {
      if (r.isDefault) return r;
    }
    return rates.isEmpty ? null : rates.first;
  }

  VatRate? byPercent(num p) {
    for (final r in rates) {
      if (r.percent == p) return r;
    }
    return null;
  }

  factory VatRates.fromJson(JsonMap j) => VatRates(
    rates: j.list('rates').map(VatRate.fromJson).toList(),
    withholdingTypes: j
        .list('withholding_types')
        .map(WithholdingType.fromJson)
        .toList(),
    disclaimer: j.strOrNull('disclaimer'),
  );
}

// ---------------------------------------------------------------- KDV dönemi

@immutable
class RateBreakdownRow {
  const RateBreakdownRow({
    required this.percent,
    required this.matrah,
    required this.kdv,
  });
  final num percent;
  final Money matrah;
  final Money kdv;
}

@immutable
class VatPeriod {
  const VatPeriod({
    required this.key,
    this.hesaplananToplam = Money.zero,
    this.tevkifatGiden = Money.zero,
    this.hesaplanan = Money.zero,
    this.indirilecek = Money.zero,
    this.indirilemeyen = Money.zero,
    this.kdv2 = Money.zero,
    this.oncekiDevreden = Money.zero,
    this.net = Money.zero,
    this.odenecek = Money.zero,
    this.devreden = Money.zero,
    this.dueDate,
    this.locked = false,
    this.estimated = true,
    this.confirmation = Confirmation.none,
    this.documentCount = 0,
    this.breakdown = const [],
    this.note,
  });

  /// "2026-11" (aylık) ya da "2026-Q4".
  final String key;
  final Money hesaplananToplam;
  final Money tevkifatGiden;
  final Money hesaplanan;
  final Money indirilecek;
  final Money indirilemeyen;
  final Money kdv2;
  final Money oncekiDevreden;
  final Money net;
  final Money odenecek;
  final Money devreden;
  final DateTime? dueDate;
  final bool locked;
  final bool estimated;
  final Confirmation confirmation;
  final int documentCount;
  final List<RateBreakdownRow> breakdown;
  final String? note;

  bool get isQuarterly => key.contains('Q');

  factory VatPeriod.fromJson(JsonMap j) {
    final bd = <RateBreakdownRow>[];
    final raw = j['oran_kirilimi'];
    Iterable<JsonMap> rows = const [];
    if (raw is List) rows = asJsonList(raw);
    if (raw is Map) {
      rows = raw.entries.map((e) => {'oran': e.key, ...asJsonMap(e.value)});
    }
    for (final r in rows) {
      final o = r['oran'] ?? r['rate'] ?? r['kdv_oran'];
      bd.add(
        RateBreakdownRow(
          percent: o is num ? o : (num.tryParse('$o') ?? 0),
          matrah: kurusOf(r, 'matrah_kurus'),
          kdv: kurusOf(r, 'kdv_kurus'),
        ),
      );
    }
    return VatPeriod(
      key:
          j.strOrNull('period') ??
          j.strOrNull('ym') ??
          j.strOrNull('key') ??
          j.strOr('id'),
      hesaplananToplam: kurusOf(j, 'hesaplanan_toplam_kurus'),
      tevkifatGiden: kurusOf(j, 'tevkifat_giden_kurus'),
      hesaplanan: kurusOf(j, 'hesaplanan_kurus'),
      indirilecek: kurusOf(j, 'indirilecek_kurus'),
      indirilemeyen: kurusOf(j, 'indirilemeyen_kurus'),
      kdv2: kurusOf(j, 'kdv2_kurus'),
      oncekiDevreden: kurusOf(j, 'onceki_devreden_kurus'),
      net: kurusOf(j, 'net_kurus'),
      odenecek: kurusOf(j, 'odenecek_kurus'),
      devreden: kurusOf(j, 'devreden_kurus'),
      dueDate: parseDay(j.str('due_date')),
      locked: j.str('status') == 'kilitli',
      estimated: j.boolOr('tahmini', true),
      confirmation: Confirmation.fromJson(j),
      documentCount: j.intOr('belge_sayisi'),
      breakdown: bd,
      note: j.strOrNull('note'),
    );
  }
}

/// `GET /invoices/summary`: giden/gelen KDV toplamları (biçim esnek okunur).
@immutable
class InvoiceSummary {
  const InvoiceSummary({
    this.gidenKdv = Money.zero,
    this.gelenKdv = Money.zero,
    this.gidenMatrah = Money.zero,
    this.gelenMatrah = Money.zero,
    this.confirmation = Confirmation.none,
  });
  final Money gidenKdv;
  final Money gelenKdv;
  final Money gidenMatrah;
  final Money gelenMatrah;
  final Confirmation confirmation;

  factory InvoiceSummary.fromJson(JsonMap j) {
    final g = j.mapOrNull('giden') ?? const <String, dynamic>{};
    final a = j.mapOrNull('gelen') ?? const <String, dynamic>{};
    return InvoiceSummary(
      gidenKdv: kurusOf(g, 'kdv_kurus'),
      gelenKdv: kurusOf(a, 'kdv_kurus'),
      gidenMatrah: kurusOf(g, 'matrah_kurus'),
      gelenMatrah: kurusOf(a, 'matrah_kurus'),
      confirmation: Confirmation.fromJson(j),
    );
  }
}

// ---------------------------------------------------------------- Vergi takvimi

@immutable
class TaxItem {
  const TaxItem({
    required this.key,
    required this.title,
    this.id,
    this.kind = '',
    this.periodLabel,
    this.nominalDate,
    this.dueDate,
    this.shifted = false,
    this.shiftReasons = const [],
    this.daysUntil,
    this.confirmation = Confirmation.none,
    this.custom = false,
    this.note,
  });
  final String key;
  final String? id;
  final String title;
  final String kind;
  final String? periodLabel;
  final DateTime? nominalDate;
  final DateTime? dueDate;
  final bool shifted;
  final List<String> shiftReasons;
  final int? daysUntil;
  final Confirmation confirmation;

  /// Kullanıcının kendi hatırlatması (düzenlenebilir/silinebilir).
  final bool custom;
  final String? note;

  /// Tamamlama kaydı anahtarı (cihazda): öğe + son gün.
  String get doneKey => '$key|${dueDate == null ? '' : dayKey(dueDate!)}';

  /// "8 gün kaldı", "Bugün son gün", "2 gün geçti". Gün sayısı yoksa [now]'a göre hesaplanır.
  String countdownLabel([DateTime? now]) => countdownText(effectiveDays(now));

  int? effectiveDays([DateTime? now]) {
    if (dueDate != null) return Ist.dayDiff(now ?? Ist.now(), dueDate!);
    return daysUntil;
  }

  factory TaxItem.fromJson(JsonMap j) {
    final kind = j.strOr('kind');
    final source = j.strOr('source');
    return TaxItem(
      key: j.strOrNull('key') ?? j.strOr('id'),
      id: j.strOrNull('id'),
      title: j.strOr('title', 'Vergi takvimi'),
      kind: kind,
      periodLabel: j.strOrNull('period_label'),
      nominalDate: parseDay(j.str('nominal_date')),
      dueDate: parseDay(j.str('due_date')),
      shifted: j.boolOr('shifted'),
      shiftReasons: j.stringList('shift_reasons'),
      daysUntil: j.intOrNull('days_until'),
      confirmation: Confirmation.fromJson(j),
      custom:
          j.boolOr('custom') ||
          kind == 'ozel' ||
          const {'kullanici', 'user', 'ozel'}.contains(source),
      note: j.strOrNull('note'),
    );
  }
}

String countdownText(int? days) {
  if (days == null) return '';
  if (days == 0) return 'Bugün son gün';
  if (days > 0) return '$days gün kaldı';
  return '${-days} gün geçti';
}

@immutable
class TaxCalendar {
  const TaxCalendar({
    this.items = const [],
    this.statu,
    this.disclaimer,
    this.needsConfirmationCount = 0,
  });
  final List<TaxItem> items;
  final String? statu;
  final String? disclaimer;
  final int needsConfirmationCount;

  factory TaxCalendar.fromJson(JsonMap j) => TaxCalendar(
    items: j.list('items').map(TaxItem.fromJson).toList(),
    statu: j.strOrNull('statu'),
    disclaimer: j.strOrNull('disclaimer'),
    needsConfirmationCount: j.intOr('needs_confirmation_count'),
  );
}

@immutable
class TaxSettings {
  const TaxSettings({this.taxStatus, this.vatPeriodType});
  final String? taxStatus;
  final String? vatPeriodType;
  factory TaxSettings.fromJson(JsonMap j) => TaxSettings(
    taxStatus: j.strOrNull('tax_status'),
    vatPeriodType: j.strOrNull('vat_period_type'),
  );
}

// ---------------------------------------------------------------- Tahsilat planı

@immutable
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.amount,
    this.projectId,
    this.offerId,
    this.invoiceId,
    this.kindRaw = 'taksit',
    this.dueDate,
    this.method,
    this.instrumentNo,
    this.bank,
    this.note,
    this.statusRaw = 'bekliyor',
    this.effectiveStatusRaw,
    this.paidAt,
    this.paymentId,
    this.customerName,
    this.customerPhone,
    this.projectCode,
    this.daysOverdue,
    this.sequence,
  });

  final String id;
  final Money amount;
  final String? projectId;
  final String? offerId;
  final String? invoiceId;
  final String kindRaw;
  final DateTime? dueDate;
  final String? method;
  final String? instrumentNo;
  final String? bank;
  final String? note;
  final String statusRaw;
  final String? effectiveStatusRaw;
  final DateTime? paidAt;
  final String? paymentId;
  final String? customerName;
  final String? customerPhone;
  final String? projectCode;
  final int? daysOverdue;
  final int? sequence;

  ScheduleKind? get kind => ScheduleKind.fromApi(kindRaw);
  ScheduleMethod? get methodEnum => ScheduleMethod.fromApi(method);
  bool get isPaid => statusRaw == 'odendi';
  bool get isCancelled => statusRaw == 'iptal';
  bool get isPending => !isPaid && !isCancelled;

  /// Vadesi geçti (sunucu `effective_status: gecikti` ya da vade bugünden önce).
  bool isOverdue([DateTime? now]) {
    if (!isPending) return false;
    if (effectiveStatusRaw == 'gecikti') return true;
    final d = dueDate;
    return d != null && Ist.dayDiff(now ?? Ist.now(), d) < 0;
  }

  int overdueDays([DateTime? now]) {
    if (!isOverdue(now)) return 0;
    final d = dueDate;
    if (d != null) return -Ist.dayDiff(now ?? Ist.now(), d);
    return daysOverdue ?? 0;
  }

  String get displayWho {
    final c = customerName?.trim();
    final p = projectCode?.trim();
    if (c != null && c.isNotEmpty && p != null && p.isNotEmpty)
      return '$p · $c';
    return (c != null && c.isNotEmpty) ? c : (p ?? 'Plan satırı');
  }

  factory ScheduleItem.fromJson(JsonMap j) => ScheduleItem(
    id: j.strOr('id'),
    amount: kurusOf(j, 'amount_kurus'),
    projectId: j.strOrNull('project_id'),
    offerId: j.strOrNull('offer_id'),
    invoiceId: j.strOrNull('invoice_id'),
    kindRaw: j.strOr('kind', 'taksit'),
    dueDate: parseDay(j.str('due_date')),
    method: j.strOrNull('method'),
    instrumentNo: j.strOrNull('instrument_no'),
    bank: j.strOrNull('bank'),
    note: j.strOrNull('note'),
    statusRaw: j.strOr('status', 'bekliyor'),
    effectiveStatusRaw: j.strOrNull('effective_status'),
    paidAt: parseDay(j.str('paid_at')),
    paymentId: j.strOrNull('payment_id'),
    customerName: j.strOrNull('customer_name'),
    customerPhone: j.strOrNull('customer_phone') ?? j.strOrNull('phone'),
    projectCode: j.strOrNull('project_code'),
    daysOverdue: j.intOrNull('days_overdue') ?? j.intOrNull('daysOverdue'),
    sequence: j.intOrNull('seq') ?? j.intOrNull('sequence'),
  );
}

/// Yaşlandırma kovası anahtarları (sunucu sırasıyla).
const List<String> agingBucketKeys = [
  'notDue',
  '0-30',
  '31-60',
  '61-90',
  '90+',
];

String agingBucketLabel(String key) => switch (key) {
  'notDue' => 'Vadesi gelmedi',
  '0-30' => '0-30 gün',
  '31-60' => '31-60 gün',
  '61-90' => '61-90 gün',
  '90+' => '90+ gün',
  _ => key,
};

@immutable
class AgingItem {
  const AgingItem({
    required this.amount,
    this.scheduleId,
    this.invoiceId,
    this.customerName,
    this.customerPhone,
    this.projectCode,
    this.dueDate,
    this.daysOverdue,
    this.source,
  });
  final Money amount;
  final String? scheduleId;
  final String? invoiceId;
  final String? customerName;
  final String? customerPhone;
  final String? projectCode;
  final DateTime? dueDate;
  final int? daysOverdue;
  final String? source;

  String get displayWho {
    final c = customerName?.trim();
    final p = projectCode?.trim();
    if (c != null && c.isNotEmpty && p != null && p.isNotEmpty)
      return '$p · $c';
    return (c != null && c.isNotEmpty) ? c : (p ?? 'Alacak');
  }

  factory AgingItem.fromJson(JsonMap j) => AgingItem(
    amount:
        kurusOrNull(j, 'amount_kurus') ??
        kurusOrNull(j, 'balance_kurus') ??
        kurusOf(j, 'totalKurus'),
    scheduleId:
        j.strOrNull('schedule_id') ??
        (j.str('source') == 'schedule' ? j.strOrNull('id') : null),
    invoiceId:
        j.strOrNull('invoice_id') ??
        (j.str('source') == 'invoice' ? j.strOrNull('id') : null),
    customerName: j.strOrNull('customer_name') ?? j.strOrNull('counterparty'),
    customerPhone: j.strOrNull('customer_phone') ?? j.strOrNull('phone'),
    projectCode: j.strOrNull('project_code'),
    dueDate: parseDay(j.str('due_date')),
    daysOverdue: j.intOrNull('days_overdue') ?? j.intOrNull('daysOverdue'),
    source: j.strOrNull('source'),
  );
}

@immutable
class AgingBucket {
  const AgingBucket({
    this.count = 0,
    this.total = Money.zero,
    this.items = const [],
  });
  final int count;
  final Money total;
  final List<AgingItem> items;

  factory AgingBucket.fromJson(JsonMap j) => AgingBucket(
    count: j.intOr('count'),
    total: kurusOf(j, 'totalKurus'),
    items: j.list('items').map(AgingItem.fromJson).toList(),
  );
}

@immutable
class AgingReport {
  const AgingReport({
    this.buckets = const {},
    this.total = Money.zero,
    this.overdue = Money.zero,
    this.overdueCount = 0,
    this.overdueItems = const [],
  });
  final Map<String, AgingBucket> buckets;
  final Money total;
  final Money overdue;
  final int overdueCount;
  final List<AgingItem> overdueItems;

  AgingBucket bucket(String key) => buckets[key] ?? const AgingBucket();

  factory AgingReport.fromJson(JsonMap j) {
    final b = j.mapOrNull('buckets') ?? const <String, dynamic>{};
    return AgingReport(
      buckets: {
        for (final k in agingBucketKeys)
          if (b[k] is Map) k: AgingBucket.fromJson(asJsonMap(b[k])),
      },
      total: kurusOf(j, 'totalKurus'),
      overdue: kurusOf(j, 'overdueKurus'),
      overdueCount: j.intOr('overdueCount'),
      overdueItems: j.list('overdueItems').map(AgingItem.fromJson).toList(),
    );
  }
}

// ---------------------------------------------------------------- Mesaj şablonları

enum ReminderTone {
  nazik('nazik', 'Nazik'),
  orta('orta', 'Orta'),
  kesin('kesin', 'Kesin');

  const ReminderTone(this.api, this.label);
  final String api;
  final String label;
  static ReminderTone? fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return null;
  }

  /// Önerilen şablon anahtarı (`receivable_reminder.suggestedTemplateKey`).
  String get templateKey => 'odeme_$api';

  /// Gecikme gününe göre önerilen ton (≤7 nazik, ≤30 orta, sonrası kesin).
  static ReminderTone forDaysOverdue(int days) =>
      days <= 7 ? nazik : (days <= 30 ? orta : kesin);
}

@immutable
class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.name,
    this.key,
    this.category,
    this.tone,
    this.body,
    this.system = true,
  });
  final String id;
  final String name;
  final String? key;
  final String? category;
  final String? tone;
  final String? body;
  final bool system;

  factory MessageTemplate.fromJson(JsonMap j) => MessageTemplate(
    id: j.strOr('id'),
    name: j.strOrNull('name') ?? j.strOrNull('title') ?? 'Şablon',
    key: j.strOrNull('key'),
    category: j.strOrNull('category'),
    tone: j.strOrNull('tone'),
    body: j.strOrNull('body') ?? j.strOrNull('text'),
    system: j.boolOr('system', j.boolOr('is_system', true)),
  );
}

@immutable
class RenderedMessage {
  const RenderedMessage({
    required this.text,
    this.whatsappUrl,
    this.whatsappAppUrl,
    this.phone,
    this.missing = const [],
    this.complete = true,
    this.urlTooLong = false,
    this.warnings = const [],
  });
  final String text;
  final String? whatsappUrl;
  final String? whatsappAppUrl;
  final String? phone;
  final List<String> missing;
  final bool complete;
  final bool urlTooLong;
  final List<String> warnings;

  factory RenderedMessage.fromJson(JsonMap j) => RenderedMessage(
    text: j.strOr('text'),
    whatsappUrl: j.strOrNull('whatsappUrl'),
    whatsappAppUrl: j.strOrNull('whatsappAppUrl'),
    phone: j.strOrNull('phone'),
    missing: j.stringList('missing'),
    complete: j.boolOr('complete', true),
    urlTooLong: j.boolOr('urlTooLong'),
    warnings: [
      for (final w
          in (j['warnings'] is List ? j['warnings'] as List : const []))
        if (w is Map) asJsonMap(w).strOr('message') else w.toString(),
    ],
  );
}

// ---------------------------------------------------------------- Seçici satırları

@immutable
class RefItem {
  const RefItem({required this.id, required this.label, this.sub});
  final String id;
  final String label;
  final String? sub;
}

// ---------------------------------------------------------------- Dışa aktarma

@immutable
class ExportFile {
  const ExportFile({
    required this.bytes,
    required this.filename,
    required this.mime,
    this.needsConfirmation = false,
  });
  final Uint8List bytes;
  final String filename;
  final String mime;
  final bool needsConfirmation;
}
