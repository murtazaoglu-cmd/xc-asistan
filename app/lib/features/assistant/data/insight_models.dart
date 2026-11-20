// Müdür önerileri (insight) ve kural ayarları (sözleşme A2 §3).
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';

enum InsightSeverity {
  info('info', 'Bilgi'),
  warn('warn', 'Uyarı'),
  critical('critical', 'Kritik');

  const InsightSeverity(this.api, this.label);
  final String api;
  final String label;
  static InsightSeverity fromApi(String? v) {
    for (final s in values) {
      if (s.api == v) return s;
    }
    return info;
  }
}

/// UI etiketi: Uyarı / Fırsat / Bilgi.
enum InsightTag { warning, opportunity, info }

@immutable
class EvidenceMetric {
  const EvidenceMetric({
    required this.key,
    required this.label,
    required this.display,
    this.value,
    this.unit,
  });
  final String key;
  final String label;
  final Object? value;
  final String? unit;
  final String display;

  factory EvidenceMetric.fromJson(JsonMap j) => EvidenceMetric(
    key: j.strOr('key'),
    label: j.strOrNull('label') ?? j.strOr('key'),
    value: j['value'],
    unit: j.strOrNull('unit'),
    display: j.strOrNull('display') ?? (j['value']?.toString() ?? ''),
  );
}

@immutable
class InsightRef {
  const InsightRef({required this.type, required this.id, required this.label});
  final String type;
  final String id;
  final String label;
}

@immutable
class InsightEvidence {
  const InsightEvidence({
    this.why,
    this.metrics = const [],
    this.refs = const [],
  });
  final String? why;
  final List<EvidenceMetric> metrics;
  final List<InsightRef> refs;
  bool get isEmpty => why == null && metrics.isEmpty;

  factory InsightEvidence.fromJson(JsonMap? j) => j == null
      ? const InsightEvidence()
      : InsightEvidence(
          why: j.strOrNull('why'),
          metrics: [
            for (final m in j.list('metrics')) EvidenceMetric.fromJson(m),
          ],
          refs: [
            for (final r in j.list('refs'))
              InsightRef(
                type: r.strOr('type'),
                id: r.strOr('id'),
                label: r.strOr('label'),
              ),
          ],
        );
}

/// Aksiyon tipleri (sözleşme): reminder.create, call, whatsapp.template, appointment.create,
/// call_list, open, screen. Bilinmeyen tip [InsightActionType.unknown] olur ve çizilmez.
enum InsightActionType {
  reminderCreate('reminder.create'),
  call('call'),
  whatsappTemplate('whatsapp.template'),
  appointmentCreate('appointment.create'),
  callList('call_list'),
  open('open'),
  screen('screen'),
  unknown('');

  const InsightActionType(this.api);
  final String api;
  static InsightActionType fromApi(String? v) {
    for (final t in values) {
      if (t.api == v) return t;
    }
    return unknown;
  }
}

@immutable
class InsightAction {
  const InsightAction({
    required this.type,
    required this.label,
    required this.raw,
  });
  final InsightActionType type;
  final String label;
  final JsonMap raw;

  String? get phone => raw.strOrNull('phone');
  String? get telUri => raw.strOrNull('tel_uri');
  String? get text => raw.strOrNull('text');
  String? get url => raw.strOrNull('url');
  String? get templateCode => raw.strOrNull('template_code');
  JsonMap get body => raw.mapOrNull('body') ?? const {};
  JsonMap get endpoint => raw.mapOrNull('endpoint') ?? const {};
  String? get entityType => raw.strOrNull('entity_type');
  String? get id => raw.strOrNull('id');
  String? get screen => raw.strOrNull('screen');
  JsonMap get params => raw.mapOrNull('params') ?? const {};
  List<String> get suggestedDates => raw.stringList('suggested_dates');
  List<JsonMap> get items => raw.list('items');

  factory InsightAction.fromJson(JsonMap j) => InsightAction(
    type: InsightActionType.fromApi(j.str('type')),
    label: j.strOrNull('label') ?? '',
    raw: j,
  );
}

@immutable
class Insight {
  const Insight({
    required this.id,
    required this.ruleKey,
    required this.severity,
    required this.title,
    this.ruleTitle,
    this.status = 'acik',
    this.snoozedUntil,
    this.body = '',
    this.entityType,
    this.entityId,
    this.evidence = const InsightEvidence(),
    this.actions = const [],
    this.feedback,
    this.firstSeenAt,
  });

  final String id;
  final String ruleKey;
  final String? ruleTitle;
  final InsightSeverity severity;
  final String status;
  final DateTime? snoozedUntil;
  final String title;
  final String body;
  final String? entityType;
  final String? entityId;
  final InsightEvidence evidence;

  /// Yalnız bilinen aksiyon tipleri.
  final List<InsightAction> actions;
  final String? feedback;
  final DateTime? firstSeenAt;

  bool get isOpen => status == 'acik';

  Insight withFeedback(String verdict) => Insight(
    id: id,
    ruleKey: ruleKey,
    ruleTitle: ruleTitle,
    severity: severity,
    status: status,
    snoozedUntil: snoozedUntil,
    title: title,
    body: body,
    entityType: entityType,
    entityId: entityId,
    evidence: evidence,
    actions: actions,
    feedback: verdict,
    firstSeenAt: firstSeenAt,
  );

  /// Etiket: kritik/uyarı → Uyarı; bilgi → Fırsat (M4 boş takvim, M6 bekleyen teklif, M12 hat,
  /// M13 mevsim) ya da Bilgi (diğer).
  InsightTag get tag {
    if (severity != InsightSeverity.info) return InsightTag.warning;
    const opportunity = {'M4', 'M5', 'M6', 'M6b', 'M6c', 'M12'};
    return opportunity.contains(ruleKey)
        ? InsightTag.opportunity
        : InsightTag.info;
  }

  factory Insight.fromJson(JsonMap j) {
    final entity = j.mapOrNull('entity');
    return Insight(
      id: j.strOr('id', j.strOr('insight_id')),
      ruleKey: j.strOr('rule_key'),
      ruleTitle: j.strOrNull('rule_title'),
      severity: InsightSeverity.fromApi(j.str('severity')),
      status: j.strOr('status', 'acik'),
      snoozedUntil: j.dateTime('snoozed_until'),
      title: j.strOr('title'),
      body: j.strOrNull('body') ?? j.strOr('text'),
      entityType: entity?.strOrNull('type'),
      entityId: entity?.strOrNull('id'),
      evidence: InsightEvidence.fromJson(
        j.mapOrNull('evidence') ??
            (j['why'] is List ? {'metrics': j['why']} : null),
      ),
      actions: [
        for (final a in j.list('actions'))
          if (InsightActionType.fromApi(a.str('type')) !=
              InsightActionType.unknown)
            InsightAction.fromJson(a),
      ],
      feedback: j.strOrNull('feedback'),
      firstSeenAt: j.dateTime('first_seen_at'),
    );
  }
}

/// Kural durumu: aktif | kapali | bagimli.
@immutable
class InsightRule {
  const InsightRule({
    required this.key,
    required this.title,
    required this.description,
    required this.group,
    required this.enabled,
    required this.status,
    this.params = const {},
    this.defaults = const {},
  });
  final String key;
  final String title;
  final String description;
  final String group;
  final bool enabled;
  final String status;
  final Map<String, int> params;
  final Map<String, int> defaults;

  /// Bağımlılığı karşılanmayan kural kullanıcıya gösterilmez.
  bool get isDependent => status == 'bagimli';

  static Map<String, int> _ints(Object? v) {
    final out = <String, int>{};
    asJsonMap(v).forEach((k, val) {
      final n = val is num ? val.toInt() : int.tryParse('$val');
      if (n != null) out[k] = n;
    });
    return out;
  }

  factory InsightRule.fromJson(JsonMap j) => InsightRule(
    key: j.strOr('rule_key'),
    title: j.strOr('title'),
    description: j.strOr('description'),
    group: j.strOr('group'),
    enabled: j.boolOr('enabled'),
    status: j.strOr('status', 'aktif'),
    params: _ints(j['params']),
    defaults: _ints(j['defaults']),
  );
}

@immutable
class InsightRulesConfig {
  const InsightRulesConfig({
    this.calibrationMode = false,
    this.rules = const [],
  });
  final bool calibrationMode;
  final List<InsightRule> rules;

  /// Kullanıcıya gösterilecek (bağımlı olmayan) kurallar.
  List<InsightRule> get visible => [
    for (final r in rules)
      if (!r.isDependent) r,
  ];

  factory InsightRulesConfig.fromJson(JsonMap j) => InsightRulesConfig(
    calibrationMode: j.boolOr('calibration_mode'),
    rules: [for (final r in j.list('rules')) InsightRule.fromJson(r)],
  );
}

/// Erteleme süresi seçenekleri (gün).
const List<({int days, String label})> snoozeChoices = [
  (days: 1, label: '1 gün'),
  (days: 3, label: '3 gün'),
  (days: 7, label: '1 hafta'),
];

DateTime? parseIsoDay(String? s) => Ist.tryParse(s);
