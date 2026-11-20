// "Sabah brifingi" (varsayılan 08:00) ve "akşam kapanış" (varsayılan 19:00)
// günlük bildirimlerini ayarlara göre kurar/iptal eder. İçerik metni DIŞARIDAN
// verilir ([BriefingContentProvider]); asistan özelliği kendi sağlayıcısını
// `briefingContentProvider`'ı override ederek bağlar.
//
// Not: Zamanlanmış bildirimin metni kurulduğu andaki içeriktir. Güncel içerik
// için uygulama açılışında/ön plana dönüşte ve ayar değişince [apply] çağrılır.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show TimeOfDay;

import '../storage/prefs.dart';
import '../storage/storage_providers.dart';
import 'notification_providers.dart';
import 'notification_models.dart';
import 'notification_service.dart';

abstract class BriefingContentProvider {
  Future<NotificationContent> morning();
  Future<NotificationContent> evening();
}

class DefaultBriefingContent implements BriefingContentProvider {
  const DefaultBriefingContent();
  @override
  Future<NotificationContent> morning() async => const NotificationContent(
    title: 'Günaydın! Sabah brifingi',
    body:
        'Bugünkü randevuların ve bekleyen işlerin hazır. Göz atmak için dokun.',
  );
  @override
  Future<NotificationContent> evening() async => const NotificationContent(
    title: 'Gün kapanıyor',
    body: 'Bugün neler yapıldı? Kısa bir özet için asistanı aç.',
  );
}

class DailyNotificationScheduler {
  DailyNotificationScheduler({
    required NotificationService service,
    required AppPrefs prefs,
    required BriefingContentProvider content,
  }) : _service = service,
       _prefs = prefs,
       _content = content;

  final NotificationService _service;
  final AppPrefs _prefs;
  final BriefingContentProvider _content;

  /// Tercihlere göre iki günlük bildirimi kurar ya da iptal eder.
  Future<void> apply() async {
    if (_prefs.morningEnabled) {
      final t = _prefs.morningTime;
      await _service.scheduleDaily(
        DailyNotification(
          id: NotificationIds.morningBriefing,
          channel: NotificationChannelId.briefing,
          hour: t.hour,
          minute: t.minute,
          content: await _content.morning(),
          payload: NotificationPayloads.morning,
        ),
      );
    } else {
      await _service.cancel(NotificationIds.morningBriefing);
    }
    if (_prefs.eveningEnabled) {
      final t = _prefs.eveningTime;
      await _service.scheduleDaily(
        DailyNotification(
          id: NotificationIds.eveningClosing,
          channel: NotificationChannelId.briefing,
          hour: t.hour,
          minute: t.minute,
          content: await _content.evening(),
          payload: NotificationPayloads.evening,
        ),
      );
    } else {
      await _service.cancel(NotificationIds.eveningClosing);
    }
  }

  Future<void> setMorning({bool? enabled, TimeOfDay? time}) async {
    if (enabled != null) await _prefs.setMorningEnabled(enabled);
    if (time != null) await _prefs.setMorningTime(time);
    await apply();
  }

  Future<void> setEvening({bool? enabled, TimeOfDay? time}) async {
    if (enabled != null) await _prefs.setEveningEnabled(enabled);
    if (time != null) await _prefs.setEveningTime(time);
    await apply();
  }

  @visibleForTesting
  AppPrefs get prefs => _prefs;
}

final briefingContentProvider = Provider<BriefingContentProvider>(
  (ref) => const DefaultBriefingContent(),
);

final dailySchedulerProvider = Provider<DailyNotificationScheduler>((ref) {
  return DailyNotificationScheduler(
    service: ref.watch(notificationServiceProvider),
    prefs: ref.watch(appPrefsProvider),
    content: ref.watch(briefingContentProvider),
  );
});
