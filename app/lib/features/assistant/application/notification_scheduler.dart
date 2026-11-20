// Sabah brifing özeti ve akşam kapanış hatırlatması: yerel bildirim içeriğini asistan verilerinden
// üretir ve core/notifications arayüzüyle kurar (core DEĞİŞTİRİLMEZ).
//
// Saatler/günler/sessiz saat sunucudaki tercihlerden gelir (GET /assistant/prefs). Tüm haftayı
// kapsayan seçimde günlük tekrar; bazı günler kapalıysa (ör. Pazar) sonraki 7 günün tek seferlik
// bildirimleri kurulur (her uygulama açılışında/ön plana dönüşte yenilenir).
// Bildirime dokununca rota: sabah `/assistant/briefing`, akşam `/assistant/closure`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/daily_scheduler.dart';
import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/util/dates.dart';
import '../data/assistant_repository.dart';
import '../data/briefing_models.dart';
import '../data/closure_models.dart';
import '../data/inbox_models.dart';
import 'access.dart';
import 'assistant_routes_paths.dart';

/// Tek seferlik (haftanın bazı günleri) bildirim numaraları: sabah 1011-1017, akşam 1021-1027.
abstract final class AssistantNotificationIds {
  static const int morningOneOffBase = 1010;
  static const int eveningOneOffBase = 1020;
}

/// Bildirim metinleri (saf işlevler; testlenebilir).
abstract final class AssistantNotificationTexts {
  static const NotificationContent genericMorning = NotificationContent(
    title: 'Günaydın! Sabah brifingi',
    body: 'Bugünün özeti hazır. Göz atmak için dokunun.',
  );
  static const NotificationContent genericEvening = NotificationContent(
    title: 'Gün kapanıyor',
    body: 'Birkaç kısa soruyla günü kapatın. Dokunup başlayın.',
  );

  /// [fireToday]: bildirim BUGÜN çalacaksa bugünün brifingi kullanılır; yarına kuruluyorsa yalnız
  /// bugünün verisinden bilinen "yarın N randevu" kullanılır (bayat sayı gösterilmez).
  static NotificationContent morning(
    Briefing? b, {
    required bool fireToday,
    required AssistantAccess access,
  }) {
    if (b == null) return genericMorning;
    final s = b.stats;
    if (!fireToday) {
      final n = s.tomorrowAppointments;
      return NotificationContent(
        title: 'Günaydın! Sabah brifingi',
        body: n > 0
            ? '$n randevunuz var. Brifingi açmak için dokunun.'
            : 'Bugünün özeti hazır. Göz atmak için dokunun.',
      );
    }
    final parts = <String>[
      if (s.appointments > 0) '${s.appointments} randevu',
      if (access.showFinance && s.lateCollections > 0)
        '${s.lateCollections} geciken tahsilat',
      if (s.followups > 0) '${s.followups} takip',
      if (access.showSales && s.newRequests > 0) '${s.newRequests} yeni talep',
      if (s.overdueJobs > 0) '${s.overdueJobs} geciken iş',
    ];
    final first = _firstAppointment(b);
    var body = parts.isEmpty
        ? 'Bugün sakin bir gün görünüyor.'
        : parts.join(' · ');
    if (first != null) body = '$body\nİlk: $first';
    return NotificationContent(
      title: b.title.isEmpty ? genericMorning.title : b.title,
      body: body,
    );
  }

  static String? _firstAppointment(Briefing b) {
    final block = b.block('appointments');
    if (block == null || block.items.isEmpty) return null;
    final it = block.items.first;
    final summary = it['summary'];
    return summary is String && summary.isNotEmpty ? summary : null;
  }

  static NotificationContent evening(ClosureState? c) {
    if (c == null) return genericEvening;
    if (c.isDone) {
      return const NotificationContent(
        title: 'Gün kapanıyor',
        body: 'Bugünün kapanışı tamamlanmış görünüyor. Özet için dokunun.',
      );
    }
    final n = c.questions.length;
    return NotificationContent(
      title: 'Gün kapanıyor',
      body: n > 0
          ? 'Bugün $n kısa soru var; 2 dakikada günü kapatın.'
          : 'Bugünün özetine göz atıp günü kapatın.',
    );
  }
}

/// Bir bildirim kurulum planı (saf; testlenebilir).
class PlannedFire {
  const PlannedFire({required this.when, required this.morning});
  final DateTime when;
  final bool morning;
}

abstract final class NotificationPlanner {
  /// [prefs]'e göre sonraki 7 günde çalacak (sabah/akşam) anları üretir; sessiz saate düşenler
  /// ve kapalı günler atlanır. Zamanlar UTC anlardır.
  static List<PlannedFire> oneOffs(AssistantPrefs prefs, DateTime now) {
    if (!prefs.enabled) return const [];
    final out = <PlannedFire>[];
    final today = Ist.wall(now);
    for (var d = 0; d < 7; d++) {
      final day = DateTime.utc(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: d));
      if (!prefs.weekdays.contains(day.weekday)) continue;
      for (final morning in [true, false]) {
        if (morning ? !prefs.morningEnabled : !prefs.eveningEnabled) continue;
        final t = AssistantPrefs.parseTime(
          morning ? prefs.morningTime : prefs.eveningTime,
        );
        if (prefs.isQuiet(t.hour, t.minute)) continue;
        final at = Ist.fromWall(day.year, day.month, day.day, t.hour, t.minute);
        if (at.isAfter(now)) out.add(PlannedFire(when: at, morning: morning));
      }
    }
    return out;
  }

  static bool coversWholeWeek(AssistantPrefs p) =>
      {1, 2, 3, 4, 5, 6, 7}.every(p.weekdays.contains);
}

class AssistantNotificationScheduler {
  AssistantNotificationScheduler({
    required AssistantRepository repo,
    required NotificationService service,
    required AssistantAccess access,
  }) : _repo = repo,
       _service = service,
       _access = access;

  final AssistantRepository _repo;
  final NotificationService _service;
  final AssistantAccess _access;

  /// Tercihlere ve güncel verilere göre sabah/akşam bildirimlerini kurar ya da iptal eder.
  /// Ağ hatasında genel metinle ve varsayılan tercihlerle kurulur (bildirim eksik kalmaz).
  Future<void> apply({DateTime? now}) async {
    final n = now ?? Ist.now();
    AssistantPrefs prefs;
    try {
      prefs = await _repo.prefs();
    } on Object {
      prefs = const AssistantPrefs();
    }
    await _cancelAll();
    if (!prefs.enabled) return;

    Briefing? briefing;
    ClosureState? closure;
    if (prefs.morningEnabled) {
      try {
        briefing = await _repo.briefingToday();
      } on Object {
        briefing = null;
      }
    }
    if (prefs.eveningEnabled) {
      try {
        closure = await _repo.closureToday();
      } on Object {
        closure = null;
      }
    }

    if (NotificationPlanner.coversWholeWeek(prefs)) {
      if (prefs.morningEnabled) {
        final t = AssistantPrefs.parseTime(prefs.morningTime);
        if (!prefs.isQuiet(t.hour, t.minute)) {
          final today = Ist.wall(n);
          final fireToday =
              today.hour * 60 + today.minute < t.hour * 60 + t.minute;
          await _service.scheduleDaily(
            DailyNotification(
              id: NotificationIds.morningBriefing,
              channel: NotificationChannelId.briefing,
              hour: t.hour,
              minute: t.minute,
              content: AssistantNotificationTexts.morning(
                briefing,
                fireToday: fireToday,
                access: _access,
              ),
              payload: AssistantPaths.briefing,
            ),
          );
        }
      }
      if (prefs.eveningEnabled) {
        final t = AssistantPrefs.parseTime(prefs.eveningTime);
        if (!prefs.isQuiet(t.hour, t.minute)) {
          await _service.scheduleDaily(
            DailyNotification(
              id: NotificationIds.eveningClosing,
              channel: NotificationChannelId.briefing,
              hour: t.hour,
              minute: t.minute,
              content: AssistantNotificationTexts.evening(closure),
              payload: AssistantPaths.closure,
            ),
          );
        }
      }
      return;
    }

    // Bazı günler kapalı: sonraki 7 günün tek seferlik bildirimleri.
    final fires = NotificationPlanner.oneOffs(prefs, n);
    final todayDay = Ist.wall(n);
    for (var i = 0; i < fires.length; i++) {
      final f = fires[i];
      final w = Ist.wall(f.when);
      final sameDay =
          w.year == todayDay.year &&
          w.month == todayDay.month &&
          w.day == todayDay.day;
      final dayIndex = Ist.dayDiff(n, f.when).clamp(0, 6);
      await _service.scheduleAt(
        id:
            (f.morning
                ? AssistantNotificationIds.morningOneOffBase
                : AssistantNotificationIds.eveningOneOffBase) +
            dayIndex +
            1,
        when: f.when,
        channel: NotificationChannelId.briefing,
        content: f.morning
            ? AssistantNotificationTexts.morning(
                briefing,
                fireToday: sameDay,
                access: _access,
              )
            : AssistantNotificationTexts.evening(closure),
        payload: f.morning ? AssistantPaths.briefing : AssistantPaths.closure,
      );
    }
  }

  Future<void> _cancelAll() async {
    await _service.cancel(NotificationIds.morningBriefing);
    await _service.cancel(NotificationIds.eveningClosing);
    for (var i = 1; i <= 7; i++) {
      await _service.cancel(AssistantNotificationIds.morningOneOffBase + i);
      await _service.cancel(AssistantNotificationIds.eveningOneOffBase + i);
    }
  }
}

final assistantNotificationSchedulerProvider =
    Provider<AssistantNotificationScheduler>((ref) {
      return AssistantNotificationScheduler(
        repo: ref.watch(assistantRepositoryProvider),
        service: ref.watch(notificationServiceProvider),
        access: ref.watch(assistantAccessProvider),
      );
    });

/// Core'un günlük zamanlayıcısı bu sağlayıcıyla `briefingContentProvider` üzerinden de beslenebilir:
/// ağ hatasında bile genel ama anlamlı metin döner. (Bkz. docs/CORE-REQUESTS.md)
class AssistantBriefingContent implements BriefingContentProvider {
  AssistantBriefingContent(this._repo, this._access);
  final AssistantRepository _repo;
  final AssistantAccess _access;

  @override
  Future<NotificationContent> morning() async {
    try {
      final b = await _repo.briefingToday();
      final w = Ist.wall(Ist.now());
      return AssistantNotificationTexts.morning(
        b,
        fireToday: w.hour < 8,
        access: _access,
      );
    } on Object {
      return AssistantNotificationTexts.genericMorning;
    }
  }

  @override
  Future<NotificationContent> evening() async {
    try {
      return AssistantNotificationTexts.evening(await _repo.closureToday());
    } on Object {
      return AssistantNotificationTexts.genericEvening;
    }
  }
}

final assistantBriefingContentProvider = Provider<BriefingContentProvider>(
  (ref) => AssistantBriefingContent(
    ref.watch(assistantRepositoryProvider),
    ref.watch(assistantAccessProvider),
  ),
);
