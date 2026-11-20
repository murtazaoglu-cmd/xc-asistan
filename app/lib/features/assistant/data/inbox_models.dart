// Bildirim kutusu (sözleşme A1 §4) ve bildirim tercihleri (A1 §3).
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';

@immutable
class InboxItem {
  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.priority,
    this.status,
    this.availableAt,
    this.createdAt,
    this.readAt,
    this.ackedAt,
  });
  final String id;
  final String type;
  final String title;
  final String body;
  final JsonMap data;
  final String? priority;
  final String? status;
  final DateTime? availableAt;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? ackedAt;

  bool get isRead => readAt != null;

  InboxItem copyWith({DateTime? readAt, DateTime? ackedAt}) => InboxItem(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    priority: priority,
    status: status,
    availableAt: availableAt,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
    ackedAt: ackedAt ?? this.ackedAt,
  );

  factory InboxItem.fromJson(JsonMap j) {
    // `data` bazen JSON metni olarak gelir (push yükü); harita değilse boş say.
    return InboxItem(
      id: j.strOr('id'),
      type: j.strOr('type'),
      title: j.strOr('title'),
      body: j.strOr('body'),
      data: j.mapOrNull('data') ?? const {},
      priority: j.strOrNull('priority'),
      status: j.strOrNull('status'),
      availableAt: j.dateTime('available_at'),
      createdAt: j.dateTime('created_at'),
      readAt: j.dateTime('read_at'),
      ackedAt: j.dateTime('acked_at'),
    );
  }
}

@immutable
class InboxPage {
  const InboxPage({
    required this.items,
    required this.unreadCount,
    this.nextBefore,
  });
  final List<InboxItem> items;
  final int unreadCount;

  /// Sonraki sayfa için `before` değeri; null ise son sayfa.
  final String? nextBefore;

  factory InboxPage.fromJson(JsonMap j) => InboxPage(
    items: [for (final i in j.list('items')) InboxItem.fromJson(i)],
    unreadCount: j.intOr('unread_count'),
    nextBefore: j.strOrNull('next_before'),
  );
}

/// `GET|PUT /assistant/prefs`.
@immutable
class AssistantPrefs {
  const AssistantPrefs({
    this.enabled = true,
    this.tz = 'Europe/Istanbul',
    this.morningEnabled = true,
    this.eveningEnabled = true,
    this.morningTime = '07:30',
    this.eveningTime = '18:30',
    this.quietEnabled = true,
    this.quietStart = '21:30',
    this.quietEnd = '07:00',
    this.weekdays = const [1, 2, 3, 4, 5, 6],
    this.pushChannel = true,
    this.inboxChannel = true,
    this.maxProactivePerDay = 5,
    this.criticalInQuiet = false,
    this.isDefault = true,
  });

  final bool enabled;
  final String tz;
  final bool morningEnabled;
  final bool eveningEnabled;
  final String morningTime;
  final String eveningTime;
  final bool quietEnabled;
  final String quietStart;
  final String quietEnd;

  /// 1 = Pzt ... 7 = Paz
  final List<int> weekdays;
  final bool pushChannel;
  final bool inboxChannel;
  final int maxProactivePerDay;
  final bool criticalInQuiet;
  final bool isDefault;

  static String _hhmm(String? v, String fallback) {
    if (v == null) return fallback;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
    if (m == null) return fallback;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return fallback;
    return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
  }

  factory AssistantPrefs.fromJson(JsonMap j) {
    final ch = j.mapOrNull('channels');
    final days = <int>[
      for (final d
          in (j['weekdays'] is List ? j['weekdays'] as List : const []))
        if (d is num && d >= 1 && d <= 7) d.toInt(),
    ];
    return AssistantPrefs(
      enabled: j.boolOr('enabled', true),
      tz: j.strOr('tz', 'Europe/Istanbul'),
      morningEnabled: j.boolOr('morning_enabled', true),
      eveningEnabled: j.boolOr('evening_enabled', true),
      morningTime: _hhmm(j.str('morning_time'), '07:30'),
      eveningTime: _hhmm(j.str('evening_time'), '18:30'),
      quietEnabled: j.boolOr('quiet_enabled', true),
      quietStart: _hhmm(j.str('quiet_start'), '21:30'),
      quietEnd: _hhmm(j.str('quiet_end'), '07:00'),
      weekdays: days.isEmpty && j['weekdays'] == null
          ? const [1, 2, 3, 4, 5, 6]
          : days,
      pushChannel: ch?.boolOr('push', true) ?? true,
      inboxChannel: ch?.boolOr('inbox', true) ?? true,
      maxProactivePerDay: j.intOr('max_proactive_per_day', 5),
      criticalInQuiet: j.boolOr('critical_in_quiet'),
      isDefault: j.boolOr('is_default'),
    );
  }

  AssistantPrefs copyWith({
    bool? enabled,
    bool? morningEnabled,
    bool? eveningEnabled,
    String? morningTime,
    String? eveningTime,
    bool? quietEnabled,
    String? quietStart,
    String? quietEnd,
    List<int>? weekdays,
    bool? criticalInQuiet,
  }) => AssistantPrefs(
    enabled: enabled ?? this.enabled,
    tz: tz,
    morningEnabled: morningEnabled ?? this.morningEnabled,
    eveningEnabled: eveningEnabled ?? this.eveningEnabled,
    morningTime: morningTime ?? this.morningTime,
    eveningTime: eveningTime ?? this.eveningTime,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    weekdays: weekdays ?? this.weekdays,
    pushChannel: pushChannel,
    inboxChannel: inboxChannel,
    maxProactivePerDay: maxProactivePerDay,
    criticalInQuiet: criticalInQuiet ?? this.criticalInQuiet,
    isDefault: false,
  );

  /// "07:30" → (7, 30)
  static ({int hour, int minute}) parseTime(String hhmm) {
    final p = hhmm.split(':');
    return (
      hour: int.tryParse(p.first) ?? 0,
      minute: int.tryParse(p.last) ?? 0,
    );
  }

  static String formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Verilen saat sessiz aralıkta mı (gece yarısını aşan aralık dahil)?
  bool isQuiet(int hour, int minute) {
    if (!quietEnabled) return false;
    final t = hour * 60 + minute;
    final s = parseTime(quietStart);
    final e = parseTime(quietEnd);
    final a = s.hour * 60 + s.minute;
    final b = e.hour * 60 + e.minute;
    if (a == b) return false;
    return a < b ? (t >= a && t < b) : (t >= a || t < b);
  }
}
