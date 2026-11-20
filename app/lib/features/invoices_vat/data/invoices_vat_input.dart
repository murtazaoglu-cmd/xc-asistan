// Yazma gövdeleri (sözleşme B) ve form doğrulaması. Doğrulama burada, ekran yalnız çağırır.
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import 'invoices_vat_models.dart';
import 'vat_calc.dart';

/// Tutar girişi biçimi: KDV hariç (matrah) ya da KDV dahil (tutar).
enum AmountBasis { exclusive, inclusive }

@immutable
class InvoiceInput {
  const InvoiceInput({
    required this.direction,
    required this.issueDate,
    required this.amount,
    required this.basis,
    this.invoiceType,
    this.invoiceNo,
    this.ettn,
    this.counterparty,
    this.counterpartyTaxId,
    this.kdvOran,
    this.documentKdv,
    this.withholding,
    this.kdvExemptionReason,
    this.kdvDeductible,
    this.status,
    this.dueDate,
    this.customerId,
    this.projectId,
    this.note,
    this.acceptMismatch = false,
  });

  final InvoiceDirection direction;

  /// `YYYY-AA-GG`
  final String issueDate;
  final Money amount;
  final AmountBasis basis;
  final InvoiceType? invoiceType;
  final String? invoiceNo;
  final String? ettn;
  final String? counterparty;
  final String? counterpartyTaxId;
  final num? kdvOran;

  /// Belgedeki KDV (verilirse sunucu hesapla karşılaştırır; >5 kuruş fark → `kdv_mismatch`).
  final Money? documentKdv;
  final Withholding? withholding;
  final String? kdvExemptionReason;
  final bool? kdvDeductible;
  final InvoiceStatus? status;
  final String? dueDate;
  final String? customerId;
  final String? projectId;
  final String? note;
  final bool acceptMismatch;

  InvoiceInput copyWith({bool? acceptMismatch}) => InvoiceInput(
    direction: direction,
    issueDate: issueDate,
    amount: amount,
    basis: basis,
    invoiceType: invoiceType,
    invoiceNo: invoiceNo,
    ettn: ettn,
    counterparty: counterparty,
    counterpartyTaxId: counterpartyTaxId,
    kdvOran: kdvOran,
    documentKdv: documentKdv,
    withholding: withholding,
    kdvExemptionReason: kdvExemptionReason,
    kdvDeductible: kdvDeductible,
    status: status,
    dueDate: dueDate,
    customerId: customerId,
    projectId: projectId,
    note: note,
    acceptMismatch: acceptMismatch ?? this.acceptMismatch,
  );

  /// POST gövdesi (boş alan gönderilmez).
  Map<String, dynamic> toJson({bool forPatch = false}) {
    String? t(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final m = <String, dynamic>{
      'direction': direction.api,
      'issue_date': issueDate,
      if (basis == AmountBasis.exclusive)
        'matrah_kurus': amount.kurus
      else
        'tutar_kurus': amount.kurus,
      if (invoiceType != null) 'invoice_type': invoiceType!.api,
      if (t(invoiceNo) != null) 'invoice_no': t(invoiceNo),
      if (t(ettn) != null) 'ettn': t(ettn),
      if (t(counterparty) != null) 'counterparty': t(counterparty),
      if (t(counterpartyTaxId) != null)
        'counterparty_tax_id': counterpartyTaxId!.replaceAll(RegExp(r'\s'), ''),
      if (kdvOran != null) 'kdv_oran': kdvOran,
      if (documentKdv != null) 'kdv_kurus': documentKdv!.kurus,
      if (withholding != null && withholding!.valid)
        'tevkifat': withholding!.label,
      if (t(kdvExemptionReason) != null)
        'kdv_istisna_nedeni': t(kdvExemptionReason),
      if (kdvDeductible != null) 'kdv_indirilebilir': kdvDeductible,
      if (status != null) 'status': status!.api,
      if (t(dueDate) != null) 'due_date': t(dueDate),
      if (customerId != null) 'customer_id': customerId,
      if (projectId != null) 'project_id': projectId,
      if (t(note) != null) 'note': t(note),
      if (acceptMismatch) 'accept_mismatch': true,
    };
    if (forPatch) {
      // PATCH'te temizlenebilen alanlar açıkça null gönderilir.
      if (t(dueDate) == null) m['due_date'] = null;
      if (customerId == null) m['customer_id'] = null;
      if (projectId == null) m['project_id'] = null;
      if (t(note) == null) m['note'] = null;
      if (withholding == null || !withholding!.valid) m['tevkifat'] = null;
    }
    return m;
  }
}

/// Plan satırı oluşturma / düzenleme.
@immutable
class ScheduleInput {
  const ScheduleInput({
    required this.amount,
    required this.dueDate,
    this.projectId,
    this.offerId,
    this.invoiceId,
    this.kind = ScheduleKind.taksit,
    this.method,
    this.instrumentNo,
    this.bank,
    this.note,
  });
  final Money amount;
  final String dueDate;
  final String? projectId;
  final String? offerId;
  final String? invoiceId;
  final ScheduleKind kind;
  final ScheduleMethod? method;
  final String? instrumentNo;
  final String? bank;
  final String? note;

  Map<String, dynamic> toJson() {
    String? t(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return {
      if (projectId != null) 'project_id': projectId,
      if (projectId == null && offerId != null) 'offer_id': offerId,
      if (projectId == null && offerId == null && invoiceId != null)
        'invoice_id': invoiceId,
      'kind': kind.api,
      'amount_kurus': amount.kurus,
      'due_date': dueDate,
      if (method != null) 'method': method!.api,
      if (t(instrumentNo) != null) 'instrument_no': t(instrumentNo),
      if (t(bank) != null) 'bank': t(bank),
      if (t(note) != null) 'note': t(note),
    };
  }
}

/// `POST /payment-schedule/generate` isteği (sihirbaz).
@immutable
class PlanRequest {
  const PlanRequest({
    required this.projectId,
    required this.total,
    required this.count,
    required this.firstDue,
    this.kind = ScheduleKind.taksit,
    this.intervalDays = 30,
    this.method,
  });
  final String projectId;
  final Money total;
  final int count;
  final String firstDue;
  final ScheduleKind kind;
  final int intervalDays;
  final ScheduleMethod? method;

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'total_kurus': total.kurus,
    'count': count,
    'first_due': firstDue,
    'kind': kind.api,
    'interval_days': intervalDays,
    if (method != null) 'method': method!.api,
  };
}

/// Form doğrulama kuralları (Türkçe mesaj; null = geçerli).
abstract final class InvoiceRules {
  static String? amount(Money? m) {
    if (m == null) return 'Geçerli bir tutar girin (ör. 12.500,50).';
    if (!m.isPositive) return 'Tutar sıfırdan büyük olmalı.';
    if (m.kurus > 100000000000) return 'Tutar çok büyük.';
    return null;
  }

  static String? counterparty(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'Karşı taraf adı (unvan) gerekli.';
    if (s.length > 200) return 'Karşı taraf adı en çok 200 karakter olabilir.';
    return null;
  }

  static String? invoiceNo(String? raw) {
    final s = (raw ?? '').trim();
    if (s.length > 50) return 'Belge no en çok 50 karakter olabilir.';
    return null;
  }

  static String? taxId(String? raw) {
    switch (TaxIdCheck.check(raw)) {
      case TaxIdState.badLength:
        return 'VKN 10, TCKN 11 haneli olmalı (yalnız rakam).';
      default:
        return null;
    }
  }

  /// Sağlama toplamı tutmayan numara için UYARI (kaydı engellemez).
  static String? taxIdWarning(String? raw) =>
      TaxIdCheck.check(raw) == TaxIdState.checksumFailed
      ? 'Numara doğrulama kuralına uymuyor; yazımı kontrol edin.'
      : null;

  static String? note(String? raw) =>
      (raw ?? '').length > 500 ? 'Not en çok 500 karakter olabilir.' : null;

  static String? date(String? iso) =>
      (iso == null || parseDay(iso) == null) ? 'Tarih seçin.' : null;

  /// Vade, fatura tarihinden önce olamaz.
  static String? dueAfterIssue(String? issueIso, String? dueIso) {
    if (issueIso == null || dueIso == null) return null;
    final a = parseDay(issueIso), b = parseDay(dueIso);
    if (a == null || b == null) return null;
    return Ist.dayDiff(a, b) < 0
        ? 'Vade, fatura tarihinden önce olamaz.'
        : null;
  }

  static String? withholding(int? pay, int? payda) {
    if (pay == null && payda == null) return null;
    if (pay == null || payda == null || pay < 1 || payda < 1 || pay > payda) {
      return 'Tevkifat oranı geçersiz (ör. 4/10).';
    }
    return null;
  }

  // ---- Taksit sihirbazı ----
  static String? installmentCount(int? n) {
    if (n == null || n < 1) return 'Taksit sayısı en az 1 olmalı.';
    if (n > InstallmentPlanner.maxCount) {
      return 'Taksit sayısı en çok ${InstallmentPlanner.maxCount} olabilir.';
    }
    return null;
  }

  static String? interval(int? n) =>
      (n == null || n < 1 || n > 365) ? 'Aralık 1-365 gün olmalı.' : null;

  /// Tutar, taksit sayısına bölününce kuruşa sığmalı (her taksit ≥ 1 kuruş).
  static String? planTotal(Money? total, int? count) {
    final a = amount(total);
    if (a != null) return a;
    if (count != null && count > 0 && total!.kurus < count) {
      return 'Toplam, taksit sayısından küçük olamaz.';
    }
    return null;
  }
}
