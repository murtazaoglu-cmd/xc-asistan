// Fatura / KDV / vergi takvimi / tahsilat planı veri erişimi. Uçlar: mobile-api-contract-B.md.
// Tüm metotlar AppException fırlatır. personel/saha 403 alır (arayüz de göstermez).
// POST'larda `Idempotency-Key` gönderilir (sözleşme): aynı kayıt çift yazılmaz.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import 'invoices_vat_input.dart';
import 'invoices_vat_models.dart';

/// Fatura listesi sorgusu (sözleşme: GET /invoices).
class InvoiceQuery {
  const InvoiceQuery({
    this.direction,
    this.statuses = const {},
    this.period,
    this.from,
    this.to,
    this.overdueOnly = false,
    this.q,
    this.limit = 50,
    this.offset = 0,
  });
  final InvoiceDirection? direction;
  final Set<InvoiceStatus> statuses;

  /// `YYYY` | `YYYY-AA` | `YYYY-Qn`
  final String? period;
  final String? from;
  final String? to;
  final bool overdueOnly;
  final String? q;
  final int limit;
  final int offset;

  Map<String, dynamic> toQuery() {
    final text = (q ?? '').trim();
    return {
      if (direction != null) 'direction': direction!.api,
      if (statuses.isNotEmpty)
        'status': (statuses.map((e) => e.api).toList()..sort()).join(','),
      if (period != null) 'period': period,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (overdueOnly) 'overdue': 1,
      if (text.isNotEmpty)
        'q': text.length > 100 ? text.substring(0, 100) : text,
      'limit': limit,
      'offset': offset,
    };
  }

  InvoiceQuery copyWith({int? offset}) => InvoiceQuery(
    direction: direction,
    statuses: statuses,
    period: period,
    from: from,
    to: to,
    overdueOnly: overdueOnly,
    q: q,
    limit: limit,
    offset: offset ?? this.offset,
  );

  @override
  bool operator ==(Object other) =>
      other is InvoiceQuery &&
      other.direction == direction &&
      other.period == period &&
      other.from == from &&
      other.to == to &&
      other.overdueOnly == overdueOnly &&
      other.q == q &&
      other.limit == limit &&
      other.offset == offset &&
      other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    direction,
    period,
    from,
    to,
    overdueOnly,
    q,
    limit,
    offset,
    statuses.length,
  );
}

class MarkPaidResult {
  const MarkPaidResult({this.scheduleItemsClosed = 0});
  final int scheduleItemsClosed;
}

abstract class InvoicesVatRepository {
  // ---- Faturalar ----
  Future<Paged<Invoice>> listInvoices(InvoiceQuery query);
  Future<Invoice> invoice(String id);
  Future<Invoice> createInvoice(InvoiceInput input, {String? idempotencyKey});
  Future<Invoice> updateInvoice(String id, InvoiceInput input);
  Future<void> deleteInvoice(String id);
  Future<MarkPaidResult> markInvoicePaid(
    String id, {
    String? paidAt,
    ScheduleMethod? method,
    bool createPayment = false,
  });
  Future<InvoiceFile> uploadInvoiceFile(
    String invoiceId,
    String filePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  });
  Future<void> deleteInvoiceFile(String invoiceId, String fileId);
  Future<InvoiceSummary> invoiceSummary(String period);
  Future<ExportFile> exportInvoices({
    required String period,
    required String format,
    InvoiceDirection? direction,
    bool includeAll = false,
  });

  // ---- KDV ----
  Future<VatRates> vatRates();
  Future<List<VatPeriod>> vatPeriods({
    required int year,
    String type = 'aylik',
  });
  Future<VatPeriod> vatPeriod(String ym);
  Future<VatPeriod> calculateVatPeriod(String ym);
  Future<VatPeriod> updateVatPeriod(
    String ym, {
    Money? manualCarryIn,
    String? note,
  });
  Future<void> lockVatPeriod(String ym);
  Future<void> unlockVatPeriod(String ym);
  Future<ExportFile> exportVatPeriod(String ym, {required String format});

  // ---- Vergi takvimi ----
  Future<TaxCalendar> taxCalendar({
    String? asOf,
    int? days,
    String? from,
    String? to,
  });
  Future<TaxSettings> taxSettings();
  Future<TaxItem> createTaxItem({
    required String title,
    required String dueDate,
    String? note,
  });
  Future<TaxItem> updateTaxItem(
    String id, {
    String? title,
    String? dueDate,
    String? note,
  });
  Future<void> deleteTaxItem(String id);

  // ---- Tahsilat planı ----
  Future<List<ScheduleItem>> schedule({
    String? projectId,
    String? offerId,
    String? status,
  });
  Future<ScheduleItem> createScheduleItem(
    ScheduleInput input, {
    String? idempotencyKey,
  });
  Future<List<ScheduleItem>> generateSchedule(
    PlanRequest req, {
    String? idempotencyKey,
  });
  Future<ScheduleItem> updateScheduleItem(String id, ScheduleInput input);
  Future<void> deleteScheduleItem(String id);
  Future<void> markSchedulePaid(
    String id, {
    String? paidAt,
    bool createPayment = false,
    String? paymentId,
    ScheduleMethod? method,
  });
  Future<AgingReport> aging({String? asOf, String? projectId});

  // ---- Mesaj şablonları ----
  Future<List<MessageTemplate>> templates({
    String category = 'odeme',
    String? tone,
  });
  Future<RenderedMessage> renderTemplate(
    String templateId, {
    String? scheduleId,
    String? invoiceId,
    String? projectId,
    String? phone,
    Map<String, String>? vars,
  });

  // ---- Seçiciler ----
  Future<List<RefItem>> searchProjects(String? query);
  Future<List<RefItem>> searchCustomers(String? query);
}

class HttpInvoicesVatRepository implements InvoicesVatRepository {
  HttpInvoicesVatRepository(this.api);
  final ApiClient api;

  static final Random _rng = Random.secure();

  /// Her kayıt girişimi için benzersiz anahtar (aynı girişimin tekrarında aynı kalır).
  static String newIdempotencyKey() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  Options _idem(String? key) =>
      Options(headers: {'Idempotency-Key': key ?? newIdempotencyKey()});

  Future<JsonMap> _postMap(String path, Object? body, {String? key}) async =>
      asJsonMap(
        (await api.send('POST', path, data: body, options: _idem(key))).data,
      );

  // ================================================================ Faturalar

  @override
  Future<Paged<Invoice>> listInvoices(InvoiceQuery query) async {
    final res = await api.getPaged('/invoices', query: query.toQuery());
    return Paged(res.items.map(Invoice.fromJson).toList(), res.total);
  }

  @override
  Future<Invoice> invoice(String id) async =>
      Invoice.fromJson(await api.getMap('/invoices/$id'));

  @override
  Future<Invoice> createInvoice(
    InvoiceInput input, {
    String? idempotencyKey,
  }) async => Invoice.fromJson(
    await _postMap('/invoices', input.toJson(), key: idempotencyKey),
  );

  @override
  Future<Invoice> updateInvoice(String id, InvoiceInput input) async =>
      Invoice.fromJson(
        asJsonMap(
          await api.patch('/invoices/$id', data: input.toJson(forPatch: true)),
        ),
      );

  @override
  Future<void> deleteInvoice(String id) async {
    await api.delete('/invoices/$id');
  }

  @override
  Future<MarkPaidResult> markInvoicePaid(
    String id, {
    String? paidAt,
    ScheduleMethod? method,
    bool createPayment = false,
  }) async {
    final j = await _postMap('/invoices/$id/mark-paid', {
      if (paidAt != null) 'paid_at': paidAt,
      if (method != null) 'method': method.api,
      if (createPayment) 'create_payment': true,
    });
    return MarkPaidResult(
      scheduleItemsClosed: j.intOr('schedule_items_closed'),
    );
  }

  @override
  Future<InvoiceFile> uploadInvoiceFile(
    String invoiceId,
    String filePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async => InvoiceFile.fromJson(
    await api.upload(
      '/invoices/$invoiceId/files',
      field: 'file',
      filePath: filePath,
      fileName: fileName,
      onProgress: onProgress,
    ),
  );

  @override
  Future<void> deleteInvoiceFile(String invoiceId, String fileId) async {
    await api.delete('/invoices/$invoiceId/files/$fileId');
  }

  @override
  Future<InvoiceSummary> invoiceSummary(String period) async =>
      InvoiceSummary.fromJson(
        await api.getMap('/invoices/summary', query: {'period': period}),
      );

  @override
  Future<ExportFile> exportInvoices({
    required String period,
    required String format,
    InvoiceDirection? direction,
    bool includeAll = false,
  }) => _download(
    '/invoices/export',
    {
      'period': period,
      'format': format,
      if (direction != null) 'direction': direction.api,
      if (includeAll) 'include': 'all',
    },
    fallbackName: 'faturalar-$period.$format',
    format: format,
  );

  // ================================================================ KDV

  @override
  Future<VatRates> vatRates() async =>
      VatRates.fromJson(await api.getMap('/vat/rates'));

  @override
  Future<List<VatPeriod>> vatPeriods({
    required int year,
    String type = 'aylik',
  }) async {
    final data = await api.get(
      '/vat/periods',
      query: {'year': year, 'type': type},
    );
    // Dizi ya da {periods:[...]} kabul edilir.
    final rows = data is Map
        ? asJsonList(asJsonMap(data)['periods'])
        : asJsonList(data);
    return rows.map(VatPeriod.fromJson).toList();
  }

  @override
  Future<VatPeriod> vatPeriod(String ym) async =>
      VatPeriod.fromJson(await api.getMap('/vat/periods/$ym'));

  @override
  Future<VatPeriod> calculateVatPeriod(String ym) async => VatPeriod.fromJson(
    await _postMap('/vat/periods/$ym/calculate', const {}),
  );

  @override
  Future<VatPeriod> updateVatPeriod(
    String ym, {
    Money? manualCarryIn,
    String? note,
  }) async => VatPeriod.fromJson(
    asJsonMap(
      await api.patch(
        '/vat/periods/$ym',
        data: {
          if (manualCarryIn != null)
            'manual_carry_in_kurus': manualCarryIn.kurus,
          if (note != null) 'note': note,
        },
      ),
    ),
  );

  @override
  Future<void> lockVatPeriod(String ym) async {
    await _postMap('/vat/periods/$ym/lock', const {});
  }

  @override
  Future<void> unlockVatPeriod(String ym) async {
    await _postMap('/vat/periods/$ym/unlock', const {});
  }

  @override
  Future<ExportFile> exportVatPeriod(String ym, {required String format}) =>
      _download(
        '/vat/periods/$ym/export',
        {'format': format},
        fallbackName: 'kdv-$ym.$format',
        format: format,
      );

  // ================================================================ Vergi takvimi

  @override
  Future<TaxCalendar> taxCalendar({
    String? asOf,
    int? days,
    String? from,
    String? to,
  }) async => TaxCalendar.fromJson(
    await api.getMap(
      '/tax-calendar',
      query: {'asOf': asOf, 'days': days, 'from': from, 'to': to},
    ),
  );

  @override
  Future<TaxSettings> taxSettings() async =>
      TaxSettings.fromJson(await api.getMap('/tax-calendar/settings'));

  @override
  Future<TaxItem> createTaxItem({
    required String title,
    required String dueDate,
    String? note,
  }) async => TaxItem.fromJson(
    await _postMap('/tax-calendar/items', {
      'title': title.trim(),
      'kind': 'ozel',
      'due_date': dueDate,
      'source': 'kullanici',
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }),
  );

  @override
  Future<TaxItem> updateTaxItem(
    String id, {
    String? title,
    String? dueDate,
    String? note,
  }) async => TaxItem.fromJson(
    asJsonMap(
      await api.patch(
        '/tax-calendar/items/$id',
        data: {
          if (title != null) 'title': title.trim(),
          if (dueDate != null) 'due_date': dueDate,
          if (note != null) 'note': note.trim().isEmpty ? null : note.trim(),
        },
      ),
    ),
  );

  @override
  Future<void> deleteTaxItem(String id) async {
    await api.delete('/tax-calendar/items/$id');
  }

  // ================================================================ Tahsilat planı

  @override
  Future<List<ScheduleItem>> schedule({
    String? projectId,
    String? offerId,
    String? status,
  }) async => (await api.getList(
    '/payment-schedule',
    query: {'project_id': projectId, 'offer_id': offerId, 'status': status},
  )).map(ScheduleItem.fromJson).toList();

  @override
  Future<ScheduleItem> createScheduleItem(
    ScheduleInput input, {
    String? idempotencyKey,
  }) async => ScheduleItem.fromJson(
    await _postMap('/payment-schedule', input.toJson(), key: idempotencyKey),
  );

  @override
  Future<List<ScheduleItem>> generateSchedule(
    PlanRequest req, {
    String? idempotencyKey,
  }) async {
    final res = await api.send(
      'POST',
      '/payment-schedule/generate',
      data: req.toJson(),
      options: _idem(idempotencyKey),
    );
    final d = res.data;
    final rows = d is Map ? asJsonList(asJsonMap(d)['items']) : asJsonList(d);
    return rows.map(ScheduleItem.fromJson).toList();
  }

  @override
  Future<ScheduleItem> updateScheduleItem(
    String id,
    ScheduleInput input,
  ) async => ScheduleItem.fromJson(
    asJsonMap(await api.patch('/payment-schedule/$id', data: input.toJson())),
  );

  @override
  Future<void> deleteScheduleItem(String id) async {
    await api.delete('/payment-schedule/$id');
  }

  @override
  Future<void> markSchedulePaid(
    String id, {
    String? paidAt,
    bool createPayment = false,
    String? paymentId,
    ScheduleMethod? method,
  }) async {
    await _postMap('/payment-schedule/$id/mark-paid', {
      if (paidAt != null) 'paid_at': paidAt,
      if (createPayment) 'create_payment': true,
      if (paymentId != null) 'payment_id': paymentId,
      if (method != null) 'method': method.api,
    });
  }

  @override
  Future<AgingReport> aging({String? asOf, String? projectId}) async =>
      AgingReport.fromJson(
        await api.getMap(
          '/receivables/aging',
          query: {'asOf': asOf, 'project_id': projectId},
        ),
      );

  // ================================================================ Şablonlar

  @override
  Future<List<MessageTemplate>> templates({
    String category = 'odeme',
    String? tone,
  }) async => (await api.getList(
    '/message-templates',
    query: {'category': category, 'tone': tone},
  )).map(MessageTemplate.fromJson).toList();

  @override
  Future<RenderedMessage> renderTemplate(
    String templateId, {
    String? scheduleId,
    String? invoiceId,
    String? projectId,
    String? phone,
    Map<String, String>? vars,
  }) async => RenderedMessage.fromJson(
    await _postMap('/message-templates/$templateId/render', {
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (scheduleId == null && invoiceId != null) 'invoice_id': invoiceId,
      if (scheduleId == null && invoiceId == null && projectId != null)
        'project_id': projectId,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (vars != null && vars.isNotEmpty) 'vars': vars,
    }),
  );

  // ================================================================ Seçiciler

  @override
  Future<List<RefItem>> searchProjects(String? query) async {
    final q = (query ?? '').trim();
    final rows = await api.getList(
      '/projects',
      query: {'q': q.length > 100 ? q.substring(0, 100) : q, 'limit': 30},
    );
    return [
      for (final r in rows)
        RefItem(
          id: r.strOr('id'),
          label: [
            r.strOrNull('code'),
            r.strOrNull('customer_name'),
          ].whereType<String>().join(' · '),
          sub: r.strOrNull('service'),
        ),
    ];
  }

  @override
  Future<List<RefItem>> searchCustomers(String? query) async {
    final q = (query ?? '').trim();
    final rows = await api.getList(
      '/customers',
      query: {'q': q.length > 100 ? q.substring(0, 100) : q, 'limit': 30},
    );
    return [
      for (final r in rows)
        if (r.strOrNull('id') != null)
          RefItem(
            id: r.strOr('id'),
            label: r.strOr('name', 'Müşteri'),
            sub: r.strOrNull('phone'),
          ),
    ];
  }

  // ================================================================ İndirme

  Future<ExportFile> _download(
    String path,
    Map<String, dynamic> query, {
    required String fallbackName,
    required String format,
  }) async {
    final res = await api.send(
      'GET',
      path,
      query: query,
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = res.data;
    var bytes = raw is Uint8List
        ? raw
        : Uint8List.fromList(raw is List ? raw.cast<int>() : <int>[]);
    // DEMO sahte API düz metni JSON dizgesi olarak sarar; gerçek sunucuda bu dala girilmez.
    if (format == 'csv' && bytes.isNotEmpty && bytes.first == 0x22) {
      try {
        final s = jsonDecode(utf8.decode(bytes));
        if (s is String) bytes = Uint8List.fromList(utf8.encode(s));
      } catch (_) {}
    }
    final headers = res.headers;
    String? h(String k) => headers[k]?.firstOrNull;
    return ExportFile(
      bytes: bytes,
      filename:
          filenameFromDisposition(h('content-disposition')) ?? fallbackName,
      mime: h('content-type')?.split(';').first.trim() ?? mimeForFormat(format),
      needsConfirmation:
          (h('x-needs-confirmation') ?? '').toLowerCase() == 'true',
    );
  }

  static String mimeForFormat(String f) => f == 'xlsx'
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : 'text/csv';

  /// `attachment; filename="a.csv"` / `filename*=UTF-8''a%20b.csv`; güvenli dosya adı döndürür.
  static String? filenameFromDisposition(String? header) {
    if (header == null) return null;
    final star = RegExp(
      r"filename\*\s*=\s*[^']*'[^']*'([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    final plain = RegExp(
      r'filename\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    var name = star != null
        ? Uri.decodeComponent(star.group(1)!.trim())
        : plain?.group(1)?.trim();
    if (name == null || name.isEmpty) return null;
    // Yol ayırıcı ve denetim karakterleri temizlenir (yol kaçışı engeli).
    name = name
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f]'), '');
    return name.isEmpty ? null : name;
  }
}

final invoicesVatRepositoryProvider = Provider<InvoicesVatRepository>(
  (ref) => HttpInvoicesVatRepository(ref.watch(apiClientProvider)),
);
