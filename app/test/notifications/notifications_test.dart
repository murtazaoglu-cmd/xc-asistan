import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:xc_asistan/core/notifications/daily_scheduler.dart';
import 'package:xc_asistan/core/notifications/notification_models.dart';
import 'package:xc_asistan/core/notifications/notification_providers.dart';
import 'package:xc_asistan/core/notifications/notification_service.dart';

import '../helpers/fakes.dart';

void main() {
  NotificationService.initTimezone();
  final loc = tz.getLocation('Europe/Istanbul');

  group('nextInstanceOf', () {
    test('saat geçmediyse bugün', () {
      final now = tz.TZDateTime(loc, 2026, 11, 20, 7, 0);
      final t = NotificationService.nextInstanceOf(8, 0, now: now);
      expect(t, tz.TZDateTime(loc, 2026, 11, 20, 8, 0));
    });
    test('saat geçtiyse yarın; tam saatte de yarın', () {
      final now = tz.TZDateTime(loc, 2026, 11, 20, 8, 0);
      expect(
        NotificationService.nextInstanceOf(8, 0, now: now),
        tz.TZDateTime(loc, 2026, 11, 21, 8, 0),
      );
      final late = tz.TZDateTime(loc, 2026, 11, 20, 19, 30);
      expect(
        NotificationService.nextInstanceOf(19, 0, now: late),
        tz.TZDateTime(loc, 2026, 11, 21, 19, 0),
      );
    });
    test('ay sonu devri', () {
      final now = tz.TZDateTime(loc, 2026, 11, 30, 20, 0);
      expect(
        NotificationService.nextInstanceOf(8, 0, now: now),
        tz.TZDateTime(loc, 2026, 12, 1, 8, 0),
      );
    });
    test('İstanbul UTC+3 sabit', () {
      final t = NotificationService.nextInstanceOf(
        8,
        0,
        now: tz.TZDateTime(loc, 2026, 7, 1, 1, 0),
      );
      expect(t.timeZoneOffset, const Duration(hours: 3));
    });
  });

  group('DailyNotificationScheduler', () {
    Future<(ProviderContainer, FakeNotificationsGateway)> make([
      Map<String, Object> prefs = const {},
    ]) async {
      final gw = FakeNotificationsGateway();
      final c = ProviderContainer(
        overrides: await baseOverrides(gateway: gw, prefsValues: prefs),
      );
      addTearDown(c.dispose);
      return (c, gw);
    }

    test('varsayılan: sabah 08:00 ve akşam 19:00 kurulur', () async {
      final (c, gw) = await make();
      await c.read(dailySchedulerProvider).apply();
      expect(gw.daily.keys.toSet(), {
        NotificationIds.morningBriefing,
        NotificationIds.eveningClosing,
      });
      expect(gw.daily[NotificationIds.morningBriefing]!.hour, 8);
      expect(gw.daily[NotificationIds.eveningClosing]!.hour, 19);
      expect(
        gw.daily[NotificationIds.morningBriefing]!.payload,
        NotificationPayloads.morning,
      );
      // kanallar bir kez oluşturulur
      expect(
        gw.log.where((e) => e.startsWith('channel:')).length,
        NotificationChannelId.values.length,
      );
    });

    test('kapatılınca iptal edilir, saat değişince yeniden kurulur', () async {
      final (c, gw) = await make();
      final s = c.read(dailySchedulerProvider);
      await s.apply();
      await s.setMorning(enabled: false);
      expect(gw.daily.containsKey(NotificationIds.morningBriefing), isFalse);
      expect(gw.daily.containsKey(NotificationIds.eveningClosing), isTrue);
      await s.setEvening(time: const TimeOfDay(hour: 18, minute: 30));
      expect(gw.daily[NotificationIds.eveningClosing]!.hour, 18);
      expect(gw.daily[NotificationIds.eveningClosing]!.minute, 30);
      // tercih kalıcı
      expect(c.read(dailySchedulerProvider).prefs.morningEnabled, isFalse);
    });

    test('aynı id iki kez kurulunca çoğalmaz', () async {
      final (c, gw) = await make();
      final s = c.read(dailySchedulerProvider);
      await s.apply();
      await s.apply();
      expect(gw.daily.length, 2);
    });
  });

  group('NotificationService', () {
    test(
      'dokunma payload akışı; boş payload yok sayılır; init tek sefer',
      () async {
        final gw = FakeNotificationsGateway();
        final c = ProviderContainer(
          overrides: await baseOverrides(gateway: gw),
        );
        addTearDown(c.dispose);
        final svc = c.read(notificationServiceProvider);
        final got = <String>[];
        svc.taps.listen(got.add);
        await svc.init();
        await svc.init();
        expect(gw.log.where((e) => e == 'init').length, 1);
        gw.onTap!('/jobs/offers/5');
        gw.onTap!(null);
        gw.onTap!('');
        await Future<void>.delayed(Duration.zero);
        expect(got, ['/jobs/offers/5']);
      },
    );

    test('soğuk açılış payload ve izin', () async {
      final gw = FakeNotificationsGateway()..launch = '/today';
      final c = ProviderContainer(overrides: await baseOverrides(gateway: gw));
      addTearDown(c.dispose);
      final svc = c.read(notificationServiceProvider);
      expect(await svc.takeLaunchPayload(), '/today');
      gw.permission = false;
      expect(await svc.requestPermission(), isFalse);
    });
  });
}
