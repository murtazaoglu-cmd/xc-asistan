// Brifing modelleri (sözleşme A2 §1). Bilinmeyen blok türleri yok sayılır.
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import 'insight_models.dart';
import 'model_utils.dart';

@immutable
class BriefingStats {
  const BriefingStats(this.values);
  final Map<String, int> values;

  int get appointments => values['appointments'] ?? 0;
  int get reminders => values['reminders'] ?? 0;
  int get followups => values['followups'] ?? 0;
  int get newRequests => values['new_requests'] ?? 0;
  int get overdueJobs => values['overdue_jobs'] ?? 0;
  int get lateCollections => values['late_collections'] ?? 0;
  int get lowStock => values['low_stock'] ?? 0;
  int get attention => values['attention'] ?? 0;
  int get tomorrowAppointments => values['tomorrow_appointments'] ?? 0;

  factory BriefingStats.fromJson(JsonMap? j) {
    final out = <String, int>{};
    j?.forEach((k, v) {
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n != null) out[k] = n;
    });
    return BriefingStats(out);
  }
}

/// Brifing bloğu. Ayrıntı düz haritadır (`raw`); ekran türüne göre okur.
@immutable
class BriefingBlock {
  const BriefingBlock({
    required this.id,
    required this.type,
    required this.title,
    required this.count,
    required this.raw,
  });
  final String id;
  final String type;
  final String title;
  final int count;
  final JsonMap raw;

  List<JsonMap> get items => raw.list('items');

  factory BriefingBlock.fromJson(JsonMap j) => BriefingBlock(
    id: j.strOrNull('id') ?? j.strOr('type'),
    type: j.strOr('type'),
    title: j.strOr('title'),
    count: j.intOr('count'),
    raw: j,
  );

  /// Ekranın bildiği blok türleri (bilinmeyen tür çizilmez).
  static const Set<String> knownTypes = {
    'appointments',
    'reminders',
    'attention',
    'new_requests',
    'overdue_jobs',
    'collections',
    'low_stock',
    'money',
    'question',
    'missed_closure',
  };

  /// Saha/personel için istemci tarafı savunma süzgeci (sunucu zaten süzer).
  static const Set<String> financeTypes = {'money', 'collections'};
  static const Set<String> managerTypes = {'attention', 'question'};
  static const Set<String> salesTypes = {'new_requests', 'low_stock'};
}

enum BriefingKind {
  morning('morning', 'Sabah brifingi'),
  evening('evening', 'Gün sonu'),
  weekly('weekly', 'Haftalık rapor'),
  monthly('monthly', 'Aylık rapor'),
  unknown('', 'Brifing');

  const BriefingKind(this.api, this.label);
  final String api;
  final String label;
  static BriefingKind fromApi(String? v) {
    for (final k in values) {
      if (k.api == v) return k;
    }
    return unknown;
  }

  bool get isReport => this == weekly || this == monthly;
}

@immutable
class Briefing {
  const Briefing({
    required this.id,
    required this.kind,
    required this.date,
    required this.title,
    required this.text,
    required this.data,
    this.generatedBy,
    this.generatedAt,
    this.readAt,
    this.live = false,
  });

  final String id;
  final BriefingKind kind;

  /// İstanbul takvim günü `YYYY-MM-DD`.
  final String date;
  final String title;
  final String text;
  final JsonMap data;
  final String? generatedBy;
  final DateTime? generatedAt;
  final DateTime? readAt;
  final bool live;

  bool get isRead => readAt != null;
  bool get isEmptyDay => data.boolOr('empty');
  String? get dayKind => data.strOrNull('day_kind');
  String? get holiday => data.strOrNull('holiday');
  String get greeting => data.strOr('greeting');
  BriefingStats get stats => BriefingStats.fromJson(data.mapOrNull('stats'));

  List<BriefingBlock> get blocks => [
    for (final b in data.list('blocks'))
      if (BriefingBlock.knownTypes.contains(b.str('type')))
        BriefingBlock.fromJson(b),
  ];

  BriefingBlock? block(String type) {
    for (final b in blocks) {
      if (b.type == type) return b;
    }
    return null;
  }

  /// Rapor (haftalık/aylık) ayrıntısı; sabah brifinginde null.
  ManagerReport? get report =>
      kind.isReport ? ManagerReport.fromJson(data) : null;

  Briefing copyWith({DateTime? readAt}) => Briefing(
    id: id,
    kind: kind,
    date: date,
    title: title,
    text: text,
    data: data,
    generatedBy: generatedBy,
    generatedAt: generatedAt,
    readAt: readAt ?? this.readAt,
    live: live,
  );

  factory Briefing.fromJson(JsonMap j) => Briefing(
    id: j.strOr('id'),
    kind: BriefingKind.fromApi(j.str('kind')),
    date: j.strOr('date'),
    title: j.strOr('title'),
    text: j.strOr('text'),
    data: j.mapOrNull('data') ?? const {},
    generatedBy: j.strOrNull('generated_by'),
    generatedAt: j.dateTime('generated_at'),
    readAt: j.dateTime('read_at'),
    live: j.boolOr('live'),
  );
}

@immutable
class ReportMoney {
  const ReportMoney({
    required this.collected,
    required this.expense,
    required this.net,
    this.prevNet,
    this.netChange,
    this.note,
  });
  final Money collected;
  final Money expense;
  final Money net;
  final Money? prevNet;
  final Money? netChange;
  final String? note;

  factory ReportMoney.fromJson(JsonMap? j) {
    final m = j ?? const <String, dynamic>{};
    return ReportMoney(
      collected: kurus(m, 'collected_kurus'),
      expense: kurus(m, 'expense_kurus'),
      net: kurus(m, 'net_kurus'),
      prevNet: kurusOrNull(m, 'prev_net_kurus'),
      netChange: kurusOrNull(m, 'net_change_kurus'),
      note: m.strOrNull('note'),
    );
  }
}

@immutable
class ReportOffers {
  const ReportOffers({
    this.created = 0,
    this.quoted = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.conversionBp,
  });
  final int created;
  final int quoted;
  final int accepted;
  final int rejected;

  /// Baz puan (10000 = %100).
  final int? conversionBp;

  factory ReportOffers.fromJson(JsonMap? j) {
    final m = j ?? const <String, dynamic>{};
    return ReportOffers(
      created: m.intOr('new'),
      quoted: m.intOr('quoted'),
      accepted: m.intOr('accepted'),
      rejected: m.intOr('rejected'),
      conversionBp: m.intOrNull('conversion_recent_bp'),
    );
  }
}

/// Haftalık/aylık müdür raporu (gelir / gider / kâr, tahsilat, en çok 3 öneri).
@immutable
class ManagerReport {
  const ManagerReport({
    required this.kind,
    required this.periodLabel,
    required this.money,
    required this.offers,
    required this.lateCount,
    required this.lateTotal,
    required this.topActions,
  });
  final BriefingKind kind;
  final String periodLabel;
  final ReportMoney money;
  final ReportOffers offers;
  final int lateCount;
  final Money lateTotal;
  final List<Insight> topActions;

  factory ManagerReport.fromJson(JsonMap data) {
    final period = data.mapOrNull('period');
    final late =
        data.mapOrNull('late_collections') ?? const <String, dynamic>{};
    final receivables = data.mapOrNull('receivables');
    return ManagerReport(
      kind: BriefingKind.fromApi(data.str('kind')),
      periodLabel: period?.strOr('label') ?? '',
      money: ReportMoney.fromJson(data.mapOrNull('money')),
      offers: ReportOffers.fromJson(data.mapOrNull('offers')),
      lateCount: late.intOr('count'),
      lateTotal: late.containsKey('total_kurus')
          ? kurus(late, 'total_kurus')
          : (receivables == null
                ? Money.zero
                : kurus(receivables, 'total_kurus')),
      topActions: [
        for (final t in data.list('top_actions')) Insight.fromJson(t),
      ].take(3).toList(),
    );
  }
}
