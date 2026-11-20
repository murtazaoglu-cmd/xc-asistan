// DEMO uçları (sözleşme B): fatura, KDV, vergi takvimi, tahsilat planı, yaşlandırma, mesaj şablonları.
// Hesaplar istemci VatCalc/InstallmentPlanner ile yapılır (sunucu davranışının örneği; veri uydurma
// değildir ama oranlar DEMO için `verified:false` işaretlidir). Rol: admin/muhasebe/ortak; diğerleri 403.
import 'package:dio/dio.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import '../../../core/util/phone.dart';
import 'invoices_vat_models.dart';
import 'vat_calc.dart';

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
DemoResponse _invalid([String? m]) =>
    DemoResponse.error(400, m ?? 'Geçersiz veya eksik değer girildi.');
DemoResponse _notFound() => DemoResponse.error(404, 'Kayıt bulunamadı.');

bool _allowed(DemoRequest r) =>
    r.role == UserRole.admin ||
    r.role == UserRole.muhasebe ||
    r.role == UserRole.ortak;
bool _full(DemoRequest r) =>
    r.role == UserRole.admin || r.role == UserRole.muhasebe;

String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(int y, int m, int d) {
  final dt = DateTime.utc(y, m, d);
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
}

List<DemoRoute> invoicesVatDemoRoutes(DemoDb db) {
  final now = Ist.wall(Ist.now());
  final today = dayKey(Ist.now());
  var seq = 0;
  String id(String p) => '$p-demo-${++seq}';

  // ---- Oranlar ----
  const reasonRate = 'Oran mali müşavirle doğrulanmadı.';
  final rates = <JsonMap>[
    {
      'id': 'rate-20',
      'rate': 20,
      'label': 'Genel oran %20',
      'is_default': true,
      'verified': true,
    },
    {
      'id': 'rate-10',
      'rate': 10,
      'label': 'İndirimli %10',
      'verified': false,
      'needs_confirmation': true,
      'confirmation_reasons': [reasonRate],
    },
    {
      'id': 'rate-1',
      'rate': 1,
      'label': 'İndirimli %1',
      'verified': false,
      'needs_confirmation': true,
      'confirmation_reasons': [reasonRate],
    },
    {
      'id': 'rate-0',
      'rate': 0,
      'label': 'İstisna %0',
      'verified': false,
      'needs_confirmation': true,
      'confirmation_reasons': ['İstisna nedeni mali müşavirle doğrulanmalı.'],
    },
  ];
  final withholdings = <JsonMap>[
    {
      'id': 'wh-4-10',
      'label': 'Yapım işleri 4/10',
      'pay': 4,
      'payda': 10,
      'verified': false,
      'needs_confirmation': true,
      'confirmation_reasons': [
        'Tevkifat oranı ve kapsamı mali müşavirle doğrulanmalı.',
      ],
    },
    {
      'id': 'wh-7-10',
      'label': 'Makine bakım/onarım 7/10',
      'pay': 7,
      'payda': 10,
      'verified': false,
      'needs_confirmation': true,
      'confirmation_reasons': [
        'Tevkifat oranı ve kapsamı mali müşavirle doğrulanmalı.',
      ],
    },
  ];

  // ---- Faturalar ----
  final invoices = <JsonMap>[];
  final lockedPeriods = <String>{};
  final carryOverrides = <String, int>{};

  String periodOfDate(String d) => d.substring(0, 7);

  JsonMap buildInvoice(JsonMap b, {JsonMap? base}) {
    final rate = (b['kdv_oran'] ?? base?['kdv_oran'] ?? 20) as num;
    final w = Withholding.parse(
      b['tevkifat'] ?? b['tevkifat_oran'] ?? base?['tevkifat_oran'],
    );
    final VatPreview p;
    if (b.containsKey('tutar_kurus')) {
      p = VatCalc.fromGross(
        Money.fromKurus((b['tutar_kurus'] as num).round()),
        rate,
        withholding: w,
      );
    } else {
      p = VatCalc.fromMatrah(
        Money.fromKurus(
          ((b['matrah_kurus'] ?? base?['matrah_kurus'] ?? 0) as num).round(),
        ),
        rate,
        withholding: w,
      );
    }
    final merged = <String, dynamic>{...?base, ...b};
    final unverified = rate != 20 || w != null;
    final status = merged['status'] ?? 'kesildi';
    final due = merged['due_date'] as String?;
    return {
      ...merged,
      'matrah_kurus': p.matrah.kurus,
      'kdv_oran': rate,
      'kdv_kurus': p.kdv.kurus,
      'tevkifat_kurus': p.tevkifat.kurus,
      'tevkifat_oran': w?.label,
      'tutar_kurus': p.tutar.kurus,
      'odenecek_kurus': p.odenecek.kurus,
      'status': status,
      'overdue':
          due != null &&
          due.compareTo(today) < 0 &&
          status != 'odendi' &&
          status != 'iptal',
      'kdv_indirilebilir': merged['kdv_indirilebilir'] ?? true,
      'period': periodOfDate(merged['issue_date'] as String),
      'invoice_type_label': InvoiceType.fromApi(
        merged['invoice_type'] as String?,
      )?.label,
      'files': merged['files'] ?? <Object?>[],
      'warnings': <Object?>[],
      'confirmation': {
        'needed': unverified,
        'reasons': [
          if (rate != 20) reasonRate,
          if (w != null) 'Tevkifat oranı mali müşavirle doğrulanmalı.',
        ],
      },
    };
  }

  void seedInvoice(JsonMap b) =>
      invoices.add(buildInvoice({'id': id('inv'), ...b}));

  String dayOffset(int off) => dayKey(Ist.now().add(Duration(days: off)));
  seedInvoice({
    'direction': 'giden',
    'issue_date': dayOffset(-1),
    'invoice_type': 'e-arsiv',
    'invoice_no': 'FT-024',
    'counterparty': 'Zeynep Arslan',
    'counterparty_tax_id': '11111111111',
    'matrah_kurus': 5333333,
    'status': 'gonderildi',
    'due_date': dayOffset(14),
    'project_id': 'prj-1',
    'project_code': 'PRJ-501',
    'customer_name': 'Zeynep Arslan',
  });
  seedInvoice({
    'direction': 'gelen',
    'issue_date': dayOffset(-3),
    'invoice_type': 'e-fatura',
    'invoice_no': 'FT-023',
    'counterparty': 'Demir Çelik Ticaret',
    'counterparty_tax_id': '1234567890',
    'matrah_kurus': 2375000,
    'status': 'odendi',
    'paid_at': dayOffset(-2),
    'kdv_indirilebilir': true,
  });
  seedInvoice({
    'direction': 'giden',
    'issue_date': dayOffset(-20),
    'invoice_type': 'e-fatura',
    'invoice_no': 'FT-021',
    'counterparty': 'Ahmet Şahin',
    'matrah_kurus': 1000000,
    'status': 'kesildi',
    'due_date': dayOffset(-6),
    'project_id': 'prj-2',
    'project_code': 'PRJ-502',
    'customer_name': 'Ahmet Şahin',
  });
  seedInvoice({
    'direction': 'gelen',
    'issue_date': dayOffset(-8),
    'invoice_type': 'kagit',
    'invoice_no': 'KG-118',
    'counterparty': 'Yıldız Nakliyat',
    'matrah_kurus': 450000,
    'kdv_oran': 10,
    'status': 'kesildi',
    'due_date': dayOffset(5),
  });
  seedInvoice({
    'direction': 'giden',
    'issue_date': dayOffset(-5),
    'invoice_type': 'e-arsiv',
    'counterparty': 'Burak Aydın',
    'matrah_kurus': 800000,
    'status': 'taslak',
  });

  JsonMap? invById(String? i) =>
      invoices.where((e) => e['id'] == i).firstOrNull;

  // ---- KDV dönemi ----
  JsonMap periodJson(String key) {
    final quarterly = key.contains('Q');
    final year = int.parse(key.substring(0, 4));
    List<String> monthsOf(String k) {
      if (!k.contains('Q')) return [k];
      final q = int.parse(k.substring(6));
      return [
        for (var m = (q - 1) * 3 + 1; m <= q * 3; m++) '$year-${_two(m)}',
      ];
    }

    // Devir zinciri: yıl başından önceki döneme kadar.
    Money carryBefore(String k) {
      var carry = Money.zero;
      final steps = <String>[];
      if (quarterly) {
        final q = int.parse(k.substring(6));
        for (var i = 1; i < q; i++) {
          steps.add('$year-Q$i');
        }
      } else {
        final m = int.parse(k.substring(5, 7));
        for (var i = 1; i < m; i++) {
          steps.add('$year-${_two(i)}');
        }
      }
      for (final s in steps) {
        final pv = VatCalc.periodPreview(
          invoices
              .where((i) => monthsOf(s).contains(i['period']))
              .map(Invoice.fromJson),
          previousCarry: carry,
        );
        carry = carryOverrides.containsKey(s)
            ? Money.fromKurus(carryOverrides[s]!)
            : pv.devreden;
      }
      return carry;
    }

    final inPeriod = invoices
        .where((i) => monthsOf(key).contains(i['period']))
        .toList();
    final prev = carryOverrides[key] != null
        ? Money.fromKurus(carryOverrides[key]!)
        : carryBefore(key);
    final models = inPeriod.map(Invoice.fromJson).toList();
    final pv = VatCalc.periodPreview(models, previousCarry: prev);
    final giden = models.where(
      (i) =>
          i.direction == InvoiceDirection.giden &&
          !i.isCancelled &&
          i.status != InvoiceStatus.taslak,
    );
    final byRate = <num, List<Invoice>>{};
    for (final i in giden) {
      byRate.putIfAbsent(i.kdvOran ?? 20, () => []).add(i);
    }
    final lastMonth = monthsOf(key).last;
    final lm = int.parse(lastMonth.substring(5, 7));
    var due = DateTime.utc(year, lm + 1, 28);
    if (due.weekday == DateTime.saturday)
      due = due.add(const Duration(days: 2));
    if (due.weekday == DateTime.sunday) due = due.add(const Duration(days: 1));
    final unverified = models.any((i) => i.confirmation.needed);
    return {
      'period': key,
      'hesaplanan_toplam_kurus': Money.sum(giden.map((i) => i.kdv)).kurus,
      'tevkifat_giden_kurus': Money.sum(giden.map((i) => i.tevkifat)).kurus,
      'hesaplanan_kurus': pv.hesaplanan.kurus,
      'indirilecek_kurus': pv.indirilecek.kurus,
      'indirilemeyen_kurus': pv.indirilemeyen.kurus,
      'kdv2_kurus': 0,
      'onceki_devreden_kurus': prev.kurus,
      'net_kurus': pv.net.kurus,
      'odenecek_kurus': pv.odenecek.kurus,
      'devreden_kurus': pv.devreden.kurus,
      'due_date': _ymd(due.year, due.month, due.day),
      'status': lockedPeriods.contains(key) ? 'kilitli' : 'acik',
      'tahmini': true,
      'needs_confirmation': true,
      'confirmation_reasons': [
        'Dönem tutarları tahminidir; beyan öncesi mali müşavirle kontrol edin.',
        if (unverified) 'Doğrulanmamış oran/tevkifat içeren belge var.',
      ],
      'belge_sayisi': inPeriod.length,
      'oran_kirilimi': [
        for (final e in byRate.entries)
          {
            'oran': e.key,
            'matrah_kurus': Money.sum(e.value.map((i) => i.matrah)).kurus,
            'kdv_kurus': Money.sum(e.value.map((i) => i.kdv)).kurus,
          },
      ],
    };
  }

  String? lockedFor(String issueDate) {
    final ym = periodOfDate(issueDate);
    final q =
        '${ym.substring(0, 4)}-Q${((int.parse(ym.substring(5, 7)) - 1) ~/ 3) + 1}';
    if (lockedPeriods.contains(ym) || lockedPeriods.contains(q)) return ym;
    return null;
  }

  DemoResponse lockedError() => DemoResponse(409, {
    'error': 'Bu KDV dönemi kilitli; değişiklik yapılamaz.',
    'code': 'vat_period_locked',
  });

  // ---- Vergi takvimi ----
  final customItems = <JsonMap>[];
  JsonMap taxItem(
    String key,
    String title,
    String kind,
    String label,
    int day, {
    int monthOffset = 0,
    bool verified = false,
  }) {
    var due = DateTime.utc(now.year, now.month + monthOffset, day);
    if (due.isBefore(DateTime.utc(now.year, now.month, now.day))) {
      due = DateTime.utc(now.year, now.month + monthOffset + 1, day);
    }
    final shifted = due.weekday >= 6;
    final eff = shifted ? due.add(Duration(days: 8 - due.weekday)) : due;
    final effKey = _ymd(eff.year, eff.month, eff.day);
    return {
      'key': '$key-${eff.year}-${_two(eff.month)}',
      'title': title,
      'kind': kind,
      'period_label': label,
      'nominal_date': _ymd(due.year, due.month, due.day),
      'due_date': effKey,
      'shifted': shifted,
      'shift_reasons': shifted
          ? ['Hafta sonuna denk geldiği için sonraki iş gününe kaydırıldı.']
          : <String>[],
      'days_until': Ist.dayDiff(Ist.now(), Ist.tryParse(effKey)!),
      'needs_confirmation': !verified,
      'confirmation_reasons': verified
          ? <String>[]
          : ['Tarih resmî takvimle doğrulanmadı.'],
    };
  }

  // ---- Tahsilat planı ----
  final schedule = <JsonMap>[];
  JsonMap? projectOf(String? pid) =>
      db.projects.where((p) => p['id'] == pid).firstOrNull;

  JsonMap scheduleRow(JsonMap b) {
    final p = projectOf(b['project_id'] as String?);
    final status = (b['status'] ?? 'bekliyor') as String;
    final due = b['due_date'] as String;
    return {
      ...b,
      'status': status,
      'customer_name': p?['customer_name'],
      'customer_phone': p?['customer_phone'],
      'project_code': p?['code'],
      'effective_status': status == 'bekliyor' && due.compareTo(today) < 0
          ? 'gecikti'
          : status,
    };
  }

  void seedSchedule(
    String pid,
    String due,
    int kurus, {
    String kind = 'taksit',
    String? method,
    String status = 'bekliyor',
    String? no,
    String? bank,
  }) {
    schedule.add(
      scheduleRow({
        'id': id('sch'),
        'project_id': pid,
        'kind': kind,
        'amount_kurus': kurus,
        'due_date': due,
        'method': method,
        'instrument_no': no,
        'bank': bank,
        'status': status,
      }),
    );
  }

  seedSchedule(
    'prj-1',
    dayOffset(-45),
    1500000,
    status: 'odendi',
    method: 'Havale',
  );
  seedSchedule('prj-1', dayOffset(-15), 1500000, method: 'Havale');
  seedSchedule(
    'prj-1',
    dayOffset(15),
    1500000,
    kind: 'cek',
    method: 'Çek',
    no: 'ÇK-004512',
    bank: 'Örnek Bank',
  );
  seedSchedule('prj-2', dayOffset(-70), 800000);
  seedSchedule(
    'prj-2',
    dayOffset(-3),
    1200000,
    kind: 'senet',
    method: 'Senet',
    no: 'SN-77',
  );
  seedSchedule('prj-2', dayOffset(30), 1200000);

  AgingReport agingReport(String? projectId) {
    final b = {for (final k in agingBucketKeys) k: <AgingItem>[]};
    final overdue = <AgingItem>[];
    for (final r in schedule) {
      if (projectId != null && r['project_id'] != projectId) continue;
      if (r['status'] != 'bekliyor') continue;
      final item = ScheduleItem.fromJson(r);
      final d = item.overdueDays();
      final ai = AgingItem(
        amount: item.amount,
        scheduleId: item.id,
        customerName: item.customerName,
        customerPhone: item.customerPhone,
        projectCode: item.projectCode,
        dueDate: item.dueDate,
        daysOverdue: d,
        source: 'schedule',
      );
      final key = d <= 0
          ? 'notDue'
          : d <= 30
          ? '0-30'
          : d <= 60
          ? '31-60'
          : d <= 90
          ? '61-90'
          : '90+';
      b[key]!.add(ai);
      if (d > 0) overdue.add(ai);
    }
    return AgingReport(
      buckets: {
        for (final e in b.entries)
          e.key: AgingBucket(
            count: e.value.length,
            total: Money.sum(e.value.map((x) => x.amount)),
            items: e.value,
          ),
      },
      total: Money.sum(b.values.expand((x) => x).map((x) => x.amount)),
      overdue: Money.sum(overdue.map((x) => x.amount)),
      overdueCount: overdue.length,
      overdueItems: overdue,
    );
  }

  JsonMap agingJson(AgingReport r) {
    JsonMap it(AgingItem x) => {
      'schedule_id': x.scheduleId,
      'amount_kurus': x.amount.kurus,
      'customer_name': x.customerName,
      'customer_phone': x.customerPhone,
      'project_code': x.projectCode,
      'due_date': x.dueDate == null ? null : dayKey(x.dueDate!),
      'days_overdue': x.daysOverdue,
      'source': x.source,
    };
    return {
      'buckets': {
        for (final e in r.buckets.entries)
          e.key: {
            'count': e.value.count,
            'totalKurus': e.value.total.kurus,
            'items': e.value.items.map(it).toList(),
          },
      },
      'totalKurus': r.total.kurus,
      'overdueKurus': r.overdue.kurus,
      'overdueCount': r.overdueCount,
      'overdueItems': r.overdueItems.map(it).toList(),
      'sources': ['schedule'],
    };
  }

  // ---- Mesaj şablonları ----
  const templates = <JsonMap>[
    {
      'id': 'tpl-odeme-nazik',
      'key': 'odeme_nazik',
      'name': 'Ödeme hatırlatma (nazik)',
      'category': 'odeme',
      'tone': 'nazik',
      'system': true,
    },
    {
      'id': 'tpl-odeme-orta',
      'key': 'odeme_orta',
      'name': 'Ödeme hatırlatma (orta)',
      'category': 'odeme',
      'tone': 'orta',
      'system': true,
    },
    {
      'id': 'tpl-odeme-kesin',
      'key': 'odeme_kesin',
      'name': 'Ödeme hatırlatma (kesin)',
      'category': 'odeme',
      'tone': 'kesin',
      'system': true,
    },
  ];

  return [
    // ================= Faturalar =================
    DemoRoute('GET', '/invoices/summary', (req) {
      if (!_allowed(req)) return _forbidden();
      final period = req.query['period'];
      final rows = invoices.where(
        (i) =>
            period == null ||
            '${i['period']}'.startsWith(
              period.substring(0, period.length.clamp(0, 7)),
            ),
      );
      Money sum(String dir, String k) => Money.sum(
        rows
            .where(
              (i) =>
                  i['direction'] == dir &&
                  i['status'] != 'iptal' &&
                  i['status'] != 'taslak',
            )
            .map((i) => kurusOf(i, k)),
      );
      return DemoResponse.json({
        'giden': {
          'matrah_kurus': sum('giden', 'matrah_kurus').kurus,
          'kdv_kurus': sum('giden', 'kdv_kurus').kurus,
        },
        'gelen': {
          'matrah_kurus': sum('gelen', 'matrah_kurus').kurus,
          'kdv_kurus': sum('gelen', 'kdv_kurus').kurus,
        },
        'needs_confirmation': true,
      });
    }),
    DemoRoute('GET', '/invoices/export', (req) {
      if (!_allowed(req)) return _forbidden();
      final b = StringBuffer(
        '﻿Tarih;Belge Türü;Belge No;Yön;Karşı Taraf Unvan;Matrah;KDV;Genel Toplam;Durum\r\n',
      );
      for (final i in invoices) {
        String t(String k) => (i[k] ?? '').toString().replaceAll(';', ',');
        b.write(
          '${t('issue_date')};${t('invoice_type')};${t('invoice_no')};${t('direction')};${t('counterparty')};'
          '${Money.fromKurus(kurusOf(i, 'matrah_kurus').kurus).toApiString().replaceAll('.', ',')};'
          '${kurusOf(i, 'kdv_kurus').toApiString().replaceAll('.', ',')};'
          '${kurusOf(i, 'tutar_kurus').toApiString().replaceAll('.', ',')};${t('status')}\r\n',
        );
      }
      return DemoResponse.json(
        b.toString(),
        headers: {
          'content-type': 'text/csv; charset=utf-8',
          'content-disposition':
              'attachment; filename="faturalar-${req.query['period'] ?? 'tum'}.csv"',
          'x-needs-confirmation': 'true',
        },
      );
    }),
    DemoRoute('GET', '/invoices', (req) {
      if (!_allowed(req)) return _forbidden();
      final q = req.query;
      var rows = invoices.toList();
      if (q['direction'] != null)
        rows = rows.where((i) => i['direction'] == q['direction']).toList();
      if (q['status'] != null) {
        final st = q['status']!.split(',');
        rows = rows.where((i) => st.contains(i['status'])).toList();
      }
      final period = q['period'];
      if (period != null)
        rows = rows
            .where((i) => '${i['issue_date']}'.startsWith(period))
            .toList();
      if (q['overdue'] == '1')
        rows = rows.where((i) => i['overdue'] == true).toList();
      final s = (q['q'] ?? '').toLowerCase();
      if (s.isNotEmpty) {
        rows = rows
            .where(
              (i) => [
                'counterparty',
                'invoice_no',
                'note',
              ].any((k) => '${i[k] ?? ''}'.toLowerCase().contains(s)),
            )
            .toList();
      }
      rows.sort((a, b) => '${b['issue_date']}'.compareTo('${a['issue_date']}'));
      final total = rows.length;
      final limit = int.tryParse(q['limit'] ?? '') ?? 50;
      final offset = int.tryParse(q['offset'] ?? '') ?? 0;
      final page = rows.skip(offset).take(limit).toList();
      return DemoResponse.json(page, headers: {'X-Total-Count': '$total'});
    }),
    DemoRoute('POST', '/invoices', (req) {
      if (!_allowed(req)) return _forbidden();
      final b = req.bodyMap;
      final dir = b.str('direction');
      final date = b.str('issue_date');
      if ((dir != 'giden' && dir != 'gelen') ||
          date == null ||
          parseDay(date) == null)
        return _invalid();
      if (!b.containsKey('matrah_kurus') && !b.containsKey('tutar_kurus'))
        return _invalid();
      if (lockedFor(date) != null) return lockedError();
      final built = buildInvoice({'id': id('inv'), ...b});
      if (b.containsKey('kdv_kurus') && !b.boolOr('accept_mismatch')) {
        final diff =
            ((b['kdv_kurus'] as num).round() - (built['kdv_kurus'] as int))
                .abs();
        if (diff > VatCalc.mismatchToleranceKurus) {
          return DemoResponse(400, {
            'error': 'Belgedeki KDV hesaplanan tutarla uyuşmuyor.',
            'code': 'kdv_mismatch',
            'expectedKdvKurus': built['kdv_kurus'],
          });
        }
      }
      invoices.add(built);
      return DemoResponse.json(built, status: 201);
    }),
    DemoRoute('GET', '/invoices/:id', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      return i == null ? _notFound() : DemoResponse.json(i);
    }),
    DemoRoute('PATCH', '/invoices/:id', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      if (i == null) return _notFound();
      if (lockedFor(i['issue_date'] as String) != null) return lockedError();
      final b = req.bodyMap;
      final merged = <String, dynamic>{...i, ...b};
      // Tutar alanları değiştiyse yeniden hesaplanır: eski türetilmiş alanlar atılır.
      if (b.containsKey('matrah_kurus') || b.containsKey('tutar_kurus')) {
        merged.remove(
          b.containsKey('tutar_kurus') ? 'matrah_kurus' : 'tutar_kurus',
        );
      }
      final idx = invoices.indexOf(i);
      final built = buildInvoice(merged);
      invoices[idx] = built;
      return DemoResponse.json(built);
    }),
    DemoRoute('DELETE', '/invoices/:id', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      if (i == null) return _notFound();
      if (i['status'] != 'taslak' && i['status'] != 'iptal') {
        return DemoResponse.error(
          409,
          'Yalnızca taslak veya iptal faturalar silinebilir.',
        );
      }
      invoices.remove(i);
      return DemoResponse.json({'message': 'Fatura silindi.'});
    }),
    DemoRoute('POST', '/invoices/:id/mark-paid', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      if (i == null) return _notFound();
      i['status'] = 'odendi';
      i['paid_at'] = req.bodyMap.str('paid_at') ?? today;
      i['overdue'] = false;
      var closed = 0;
      for (final s in schedule.where(
        (s) => s['invoice_id'] == i['id'] && s['status'] == 'bekliyor',
      )) {
        s['status'] = 'odendi';
        s['effective_status'] = 'odendi';
        closed++;
      }
      return DemoResponse.json({'invoice': i, 'schedule_items_closed': closed});
    }),
    DemoRoute('POST', '/invoices/:id/files', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      if (i == null) return _notFound();
      final files = (i['files'] as List).cast<Object?>();
      if (files.length >= attachmentLimit)
        return _invalid('En çok $attachmentLimit dosya eklenebilir.');
      var name = 'ek-${files.length + 1}.jpg';
      final body = req.body;
      if (body is FormData && body.files.isNotEmpty) {
        name = body.files.first.value.filename ?? name;
      }
      final f = {
        'id': id('file'),
        'file_name': name,
        'file_url':
            'https://demo.invalid/uploads/${Uri.encodeComponent(name)}?exp=1&sig=demo',
        'mime': name.toLowerCase().endsWith('.pdf')
            ? 'application/pdf'
            : 'image/jpeg',
      };
      files.add(f);
      return DemoResponse.json(f, status: 201);
    }),
    DemoRoute('DELETE', '/invoices/:id/files/:fileId', (req) {
      if (!_allowed(req)) return _forbidden();
      final i = invById(req.params['id']);
      if (i == null) return _notFound();
      (i['files'] as List).removeWhere(
        (f) => f is Map && f['id'] == req.params['fileId'],
      );
      return DemoResponse.json({'message': 'Dosya silindi.'});
    }),

    // ================= KDV =================
    DemoRoute('GET', '/vat/rates', (req) {
      if (!_allowed(req)) return _forbidden();
      return DemoResponse.json({
        'rates': rates,
        'withholding_types': withholdings,
        'disclaimer': 'Oran ve tevkifat bilgileri bilgilendirme amaçlıdır; hukuki/mali tavsiye değildir. Mali müşavirinize teyit edin.',
      });
    }),
    DemoRoute('GET', '/vat/periods', (req) {
      if (!_allowed(req)) return _forbidden();
      final year = int.tryParse(req.query['year'] ?? '') ?? now.year;
      final quarterly = req.query['type'] == 'uc_aylik';
      final keys = quarterly
          ? [for (var q = 1; q <= 4; q++) '$year-Q$q']
          : [for (var m = 1; m <= 12; m++) '$year-${_two(m)}'];
      return DemoResponse.json([for (final k in keys) periodJson(k)]);
    }),
    DemoRoute('GET', '/vat/periods/:ym', (req) {
      if (!_allowed(req)) return _forbidden();
      return DemoResponse.json(periodJson(req.params['ym']!));
    }),
    DemoRoute('POST', '/vat/periods/:ym/calculate', (req) {
      if (!_allowed(req)) return _forbidden();
      return DemoResponse.json(periodJson(req.params['ym']!));
    }),
    DemoRoute('PATCH', '/vat/periods/:ym', (req) {
      if (!_full(req)) return _forbidden();
      final ym = req.params['ym']!;
      if (lockedPeriods.contains(ym)) return lockedError();
      final c = req.bodyMap.intOrNull('manual_carry_in_kurus');
      if (c != null) carryOverrides[ym] = c;
      return DemoResponse.json(periodJson(ym));
    }),
    DemoRoute('POST', '/vat/periods/:ym/lock', (req) {
      if (!_full(req)) return _forbidden();
      final ym = req.params['ym']!;
      if (lockedPeriods.contains(ym))
        return DemoResponse.error(409, 'Dönem zaten kilitli.');
      lockedPeriods.add(ym);
      return DemoResponse.json(periodJson(ym));
    }),
    DemoRoute('POST', '/vat/periods/:ym/unlock', (req) {
      if (!_full(req)) return _forbidden();
      final ym = req.params['ym']!;
      if (!lockedPeriods.contains(ym))
        return DemoResponse.error(409, 'Dönem zaten açık.');
      lockedPeriods.remove(ym);
      return DemoResponse.json(periodJson(ym));
    }),
    DemoRoute('GET', '/vat/periods/:ym/export', (req) {
      if (!_allowed(req)) return _forbidden();
      final p = periodJson(req.params['ym']!);
      String m(String k) =>
          Money.fromKurus(p[k] as int).toApiString().replaceAll('.', ',');
      final csv =
          '﻿Dönem;Hesaplanan KDV;İndirilecek KDV;Önceki Devreden;Ödenecek KDV;Devreden KDV\r\n'
          '${p['period']};${m('hesaplanan_kurus')};${m('indirilecek_kurus')};${m('onceki_devreden_kurus')};${m('odenecek_kurus')};${m('devreden_kurus')}\r\n';
      return DemoResponse.json(
        csv,
        headers: {
          'content-type': 'text/csv; charset=utf-8',
          'content-disposition':
              'attachment; filename="kdv-${p['period']}.csv"',
          'x-needs-confirmation': 'true',
        },
      );
    }),

    // ================= Vergi takvimi =================
    DemoRoute('GET', '/tax-calendar/settings', (req) {
      if (!_allowed(req)) return _forbidden();
      return DemoResponse.json({
        'tax_status': 'sahis',
        'vat_period_type': 'aylik',
      });
    }),
    DemoRoute('GET', '/tax-calendar', (req) {
      if (!_allowed(req)) return _forbidden();
      final items = <JsonMap>[
        taxItem('kdv1', 'KDV beyanı ve ödemesi', 'kdv', 'Önceki ay', 28),
        taxItem('kdv2', 'KDV-2 (tevkifat) beyanı', 'kdv', 'Önceki ay', 25),
        taxItem(
          'muhtasar',
          'Muhtasar ve prim hizmet beyannamesi',
          'muhtasar',
          'Önceki ay',
          26,
        ),
        taxItem(
          'gecici',
          'Geçici vergi',
          'gecici',
          'Dönem sonu',
          17,
          monthOffset: 1,
        ),
        ...customItems,
      ]..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
      return DemoResponse.json({
        'items': items,
        'statu': 'sahis',
        'statu_source': 'ayar',
        'disclaimer': 'Tarihler bilgilendirme amaçlıdır; resmî takvimi ve mali müşavirinizi esas alın.',
        'needs_confirmation_count': items
            .where((i) => i['needs_confirmation'] == true)
            .length,
      });
    }),
    DemoRoute('POST', '/tax-calendar/items', (req) {
      if (!_full(req)) return _forbidden();
      final b = req.bodyMap;
      final title = b.strOrNull('title');
      final due = b.str('due_date');
      if (title == null || due == null || parseDay(due) == null)
        return _invalid();
      final row = <String, dynamic>{
        'id': id('tax'),
        'key': id('ozel'),
        'title': title,
        'kind': 'ozel',
        'source': 'kullanici',
        'due_date': due,
        'nominal_date': due,
        'shifted': false,
        'days_until': Ist.dayDiff(Ist.now(), Ist.tryParse(due)!),
        'note': b['note'],
        'needs_confirmation': false,
      };
      customItems.add(row);
      return DemoResponse.json(row, status: 201);
    }),
    DemoRoute('PATCH', '/tax-calendar/items/:id', (req) {
      if (!_full(req)) return _forbidden();
      final row = customItems
          .where((e) => e['id'] == req.params['id'])
          .firstOrNull;
      if (row == null) return _notFound();
      final b = req.bodyMap;
      if (b.containsKey('title')) row['title'] = b['title'];
      if (b.containsKey('note')) row['note'] = b['note'];
      if (b.containsKey('due_date')) {
        row['due_date'] = b['due_date'];
        row['nominal_date'] = b['due_date'];
        row['days_until'] = Ist.dayDiff(
          Ist.now(),
          Ist.tryParse(b['due_date'] as String)!,
        );
      }
      return DemoResponse.json(row);
    }),
    DemoRoute('DELETE', '/tax-calendar/items/:id', (req) {
      if (!_full(req)) return _forbidden();
      customItems.removeWhere((e) => e['id'] == req.params['id']);
      return DemoResponse.json({'message': 'Silindi.'});
    }),

    // ================= Tahsilat planı =================
    DemoRoute('GET', '/payment-schedule', (req) {
      if (!_allowed(req)) return _forbidden();
      final q = req.query;
      var rows = schedule.map(scheduleRow).toList();
      if (q['project_id'] != null)
        rows = rows.where((r) => r['project_id'] == q['project_id']).toList();
      if (q['offer_id'] != null)
        rows = rows.where((r) => r['offer_id'] == q['offer_id']).toList();
      if (q['status'] != null)
        rows = rows.where((r) => r['status'] == q['status']).toList();
      rows.sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
      return DemoResponse.json(rows);
    }),
    DemoRoute('POST', '/payment-schedule/generate', (req) {
      if (!_allowed(req)) return _forbidden();
      final b = req.bodyMap;
      final pid = b.strOrNull('project_id');
      final total = b.intOrNull('total_kurus');
      final count = b.intOrNull('count');
      final first = b.str('first_due');
      if (pid == null ||
          total == null ||
          count == null ||
          first == null ||
          projectOf(pid) == null)
        return _invalid();
      final plan = InstallmentPlanner.generate(
        total: Money.fromKurus(total),
        count: count,
        firstDue: first,
        intervalDays: b.intOr('interval_days', 30),
      );
      if (plan.isEmpty) return _invalid('Taksit planı oluşturulamadı.');
      final rows = [
        for (final p in plan)
          scheduleRow({
            'id': id('sch'),
            'project_id': pid,
            'kind': b.str('kind') ?? 'taksit',
            'amount_kurus': p.amount.kurus,
            'due_date': p.dueDate,
            'method': b['method'],
            'status': 'bekliyor',
            'seq': p.index,
          }),
      ];
      schedule.addAll(rows);
      return DemoResponse.json({
        'items': rows,
        'count': rows.length,
      }, status: 201);
    }),
    DemoRoute('POST', '/payment-schedule', (req) {
      if (!_allowed(req)) return _forbidden();
      final b = req.bodyMap;
      final due = b.str('due_date');
      final amount = b.intOrNull('amount_kurus');
      if (due == null || parseDay(due) == null || amount == null || amount <= 0)
        return _invalid();
      final row = scheduleRow({'id': id('sch'), ...b, 'status': 'bekliyor'});
      schedule.add(row);
      return DemoResponse.json(row, status: 201);
    }),
    DemoRoute('PATCH', '/payment-schedule/:id', (req) {
      if (!_allowed(req)) return _forbidden();
      final r = schedule.where((e) => e['id'] == req.params['id']).firstOrNull;
      if (r == null) return _notFound();
      final idx = schedule.indexOf(r);
      schedule[idx] = scheduleRow({...r, ...req.bodyMap});
      return DemoResponse.json(schedule[idx]);
    }),
    DemoRoute('DELETE', '/payment-schedule/:id', (req) {
      if (!_allowed(req)) return _forbidden();
      schedule.removeWhere((e) => e['id'] == req.params['id']);
      return DemoResponse.json({'message': 'Silindi.'});
    }),
    DemoRoute('POST', '/payment-schedule/:id/mark-paid', (req) {
      if (!_allowed(req)) return _forbidden();
      final r = schedule.where((e) => e['id'] == req.params['id']).firstOrNull;
      if (r == null) return _notFound();
      r['status'] = 'odendi';
      r['effective_status'] = 'odendi';
      r['paid_at'] = req.bodyMap.str('paid_at') ?? today;
      if (req.bodyMap.boolOr('create_payment')) {
        final p = projectOf(r['project_id'] as String?);
        final payId = id('pay');
        db.payments.add({
          'id': payId,
          'project_id': r['project_id'],
          'amount': Money.fromKurus(kurusOf(r, 'amount_kurus').kurus).toTl(),
          'method': req.bodyMap.str('method') ?? r['method'] ?? 'Havale',
          'note': 'Tahsilat planından',
          'paid_at': db.iso(Ist.now()),
          'owner_id': 'u-${(req.role ?? UserRole.admin).api}',
          'customer_name': p?['customer_name'],
          'project_code': p?['code'],
        });
        r['payment_id'] = payId;
      }
      return DemoResponse.json(r);
    }),
    DemoRoute('GET', '/receivables/aging', (req) {
      if (!_allowed(req)) return _forbidden();
      return DemoResponse.json(agingJson(agingReport(req.query['project_id'])));
    }),

    // ================= Mesaj şablonları =================
    DemoRoute('GET', '/message-templates', (req) {
      if (!_allowed(req)) return _forbidden();
      final tone = req.query['tone'];
      return DemoResponse.json(
        templates.where((t) => tone == null || t['tone'] == tone).toList(),
      );
    }),
    DemoRoute('POST', '/message-templates/:id/render', (req) {
      if (!_allowed(req)) return _forbidden();
      final t = templates.where((e) => e['id'] == req.params['id']).firstOrNull;
      if (t == null) return _notFound();
      final b = req.bodyMap;
      final s = schedule.where((e) => e['id'] == b['schedule_id']).firstOrNull;
      final p = projectOf((s?['project_id'] ?? b['project_id']) as String?);
      final name = (p?['customer_name'] ?? 'Müşterimiz') as String;
      final amount = s == null
          ? ''
          : Money.fromKurus(kurusOf(s, 'amount_kurus').kurus).format();
      final due = (s?['due_date'] ?? '') as String;
      final tone = t['tone'];
      final text = switch (tone) {
        'nazik' =>
          'Merhaba $name, $amount tutarındaki ödemenizin vadesi $due. Ödeme yaptıysanız bu mesajı dikkate almayın, teşekkür ederiz.',
        'orta' =>
          'Merhaba $name, $amount tutarındaki ödemenin vadesi $due tarihinde dolmuştur. Ödeme durumunu paylaşabilir misiniz?',
        _ =>
          'Sayın $name, $due vadeli $amount tutarındaki ödeme bakiyesi görünmektedir. Bu hafta içinde ödeme planı için dönüş yapmanızı rica ederiz.',
      };
      final phone = (b['phone'] ?? p?['customer_phone']) as String?;
      final web = phone == null
          ? null
          : PhoneUtil.whatsappWebUri(phone, text: text);
      final app = phone == null
          ? null
          : PhoneUtil.whatsappAppUri(phone, text: text);
      return DemoResponse.json({
        'text': text,
        'whatsappUrl': web?.toString(),
        'whatsappAppUrl': app?.toString(),
        'phone': phone,
        'missing': phone == null ? ['telefon'] : <String>[],
        'complete': phone != null,
        'urlTooLong': false,
        'warnings': <Object?>[],
      });
    }),
  ];
}

/// Fatura başına en çok ek sayısı (sözleşme: 10).
const int attachmentLimit = 10;
