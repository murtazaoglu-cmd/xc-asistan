// Yerel bildirim altyapısı (flutter_local_notifications + timezone).
// Saat dilimi HER ZAMAN Europe/Istanbul'dur (cihaz saat dilimi ne olursa olsun).
//
// Tam zamanlı alarm (SCHEDULE_EXACT_ALARM) KULLANILMAZ: "inexactAllowWhileIdle"
// ile 08:00 brifingi Android'in pil optimizasyonuna göre birkaç dakika kayabilir;
// karşılığında özel izin ve mağaza gerekçesi gerekmez. Dakikası dakikasına gerekli
// bir bildirim çıkarsa (ör. randevu alarmı) docs/ARCHITECTURE.md "Bildirimler"deki
// adımlar uygulanmalı.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_models.dart';

/// Eklentiye ince arayüz: testte sahte (fake) ile değiştirilir.
abstract class LocalNotificationsGateway {
  Future<void> initialize(void Function(String? payload) onTap);
  Future<void> createChannel(NotificationChannelId channel);
  Future<bool> requestPermission();
  Future<bool> areEnabled();
  Future<void> scheduleDaily(DailyNotification n, tz.TZDateTime first);
  Future<void> scheduleAt({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    required tz.TZDateTime when,
    String? payload,
  });
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    String? payload,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();

  /// Uygulama bir bildirime dokunularak açıldıysa onun payload'ı.
  Future<String?> launchPayload();
}

/// Web'de yerel bildirim eklentisi desteklenmez: hiçbir şey yapmayan (güvenli) uygulama.
/// Web ajanı ileride tarayıcı bildirimi isterse bu sınıfı değiştirir.
class NoopNotificationsGateway implements LocalNotificationsGateway {
  @override
  Future<void> initialize(void Function(String? payload) onTap) async {}
  @override
  Future<void> createChannel(NotificationChannelId channel) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> areEnabled() async => false;
  @override
  Future<void> scheduleDaily(DailyNotification n, tz.TZDateTime first) async {}
  @override
  Future<void> scheduleAt({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    required tz.TZDateTime when,
    String? payload,
  }) async {}
  @override
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    String? payload,
  }) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<String?> launchPayload() async => null;
}

class PluginNotificationsGateway implements LocalNotificationsGateway {
  PluginNotificationsGateway([FlutterLocalNotificationsPlugin? plugin])
    : _p = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _p;

  AndroidFlutterLocalNotificationsPlugin? get _android => _p
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  IOSFlutterLocalNotificationsPlugin? get _ios => _p
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    await _p.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // İzin, açılışta değil kullanıcı istediğinde (requestPermission) istenir.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
  }

  @override
  Future<void> createChannel(NotificationChannelId c) async {
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        c.id,
        c.label,
        description: c.description,
        importance: c == NotificationChannelId.general
            ? Importance.defaultImportance
            : Importance.high,
      ),
    );
  }

  NotificationDetails _details(NotificationChannelId c) => NotificationDetails(
    android: AndroidNotificationDetails(
      c.id,
      c.label,
      channelDescription: c.description,
      importance: c == NotificationChannelId.general
          ? Importance.defaultImportance
          : Importance.high,
      priority: c == NotificationChannelId.general
          ? Priority.defaultPriority
          : Priority.high,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  @override
  Future<bool> requestPermission() async {
    final a = await _android?.requestNotificationsPermission();
    if (a != null) return a;
    final i = await _ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return i ?? false;
  }

  @override
  Future<bool> areEnabled() async {
    final a = await _android?.areNotificationsEnabled();
    if (a != null) return a;
    final i = await _ios?.checkPermissions();
    return i?.isEnabled ?? false;
  }

  @override
  Future<void> scheduleDaily(DailyNotification n, tz.TZDateTime first) =>
      _p.zonedSchedule(
        id: n.id,
        scheduledDate: first,
        notificationDetails: _details(n.channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.content.title,
        body: n.content.body,
        payload: n.payload,
        // Yalnız saat bileşeni eşleşir → her gün tekrarlanır.
        matchDateTimeComponents: DateTimeComponents.time,
      );

  @override
  Future<void> scheduleAt({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    required tz.TZDateTime when,
    String? payload,
  }) => _p.zonedSchedule(
    id: id,
    scheduledDate: when,
    notificationDetails: _details(channel),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: content.title,
    body: content.body,
    payload: payload,
  );

  @override
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    String? payload,
  }) => _p.show(
    id: id,
    title: content.title,
    body: content.body,
    notificationDetails: _details(channel),
    payload: payload,
  );

  @override
  Future<void> cancel(int id) => _p.cancel(id: id);

  @override
  Future<void> cancelAll() => _p.cancelAll();

  @override
  Future<String?> launchPayload() async {
    final d = await _p.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }
}

class NotificationService {
  NotificationService(this._gateway);
  final LocalNotificationsGateway _gateway;

  final StreamController<String> _taps = StreamController<String>.broadcast();
  bool _initialized = false;

  static const String timezoneName = 'Europe/Istanbul';

  /// Bildirime dokunulunca payload (rota) akışı.
  Stream<String> get taps => _taps.stream;

  /// Saat dilimi verisi + kanallar. Birden çok çağrı güvenlidir.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    initTimezone();
    await _gateway.initialize((payload) {
      if (payload != null && payload.isNotEmpty) _taps.add(payload);
    });
    for (final c in NotificationChannelId.values) {
      await _gateway.createChannel(c);
    }
  }

  static bool _tzReady = false;

  /// Saat dilimi veritabanını yükler ve yerel dilimi İstanbul yapar (testte de çağrılabilir).
  static void initTimezone() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(timezoneName));
    _tzReady = true;
  }

  /// Soğuk açılışta bildirime dokunularak açıldıysa payload'ı verir (bir kez).
  Future<String?> takeLaunchPayload() => _gateway.launchPayload();

  /// Android 13+ POST_NOTIFICATIONS / iOS izin akışı. Verildi → true.
  Future<bool> requestPermission() => _gateway.requestPermission();
  Future<bool> areEnabled() => _gateway.areEnabled();

  /// [hour]:[minute] (İstanbul) için bir sonraki an. Saat geçmişse yarın.
  @visibleForTesting
  static tz.TZDateTime nextInstanceOf(
    int hour,
    int minute, {
    tz.TZDateTime? now,
  }) {
    initTimezone();
    final loc = tz.getLocation(timezoneName);
    final n = now ?? tz.TZDateTime.now(loc);
    var t = tz.TZDateTime(loc, n.year, n.month, n.day, hour, minute);
    if (!t.isAfter(n)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Günlük tekrarlayan bildirimi kurar (aynı numara varsa yerine geçer).
  Future<void> scheduleDaily(DailyNotification n, {tz.TZDateTime? now}) async {
    await init();
    await _gateway.scheduleDaily(n, nextInstanceOf(n.hour, n.minute, now: now));
  }

  /// Tek seferlik bildirim (ör. randevu hatırlatması). [when] geçmişteyse kurulmaz.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required NotificationContent content,
    NotificationChannelId channel = NotificationChannelId.reminder,
    String? payload,
  }) async {
    await init();
    final loc = tz.getLocation(timezoneName);
    final at = tz.TZDateTime.from(when, loc);
    if (!at.isAfter(tz.TZDateTime.now(loc))) return;
    await _gateway.scheduleAt(
      id: id,
      channel: channel,
      content: content,
      when: at,
      payload: payload,
    );
  }

  Future<void> showNow({
    required int id,
    required NotificationContent content,
    NotificationChannelId channel = NotificationChannelId.general,
    String? payload,
  }) async {
    await init();
    await _gateway.show(
      id: id,
      channel: channel,
      content: content,
      payload: payload,
    );
  }

  Future<void> cancel(int id) => _gateway.cancel(id);
  Future<void> cancelAll() => _gateway.cancelAll();

  void dispose() => _taps.close();
}
