import 'package:flutter/foundation.dart';

/// Android bildirim kanalları (kullanıcı sistem ayarlarında ayrı ayrı kapatabilir).
enum NotificationChannelId {
  briefing(
    'xc_brifing',
    'Sabah brifingi ve akşam kapanış',
    'Günlük sabah özeti ve akşam kapanış hatırlatması',
  ),
  reminder('xc_hatirlatma', 'Hatırlatmalar', 'Randevu ve iş hatırlatmaları'),
  general('xc_genel', 'Genel', 'Diğer bildirimler');

  const NotificationChannelId(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;
}

/// Sabit bildirim numaraları. Hatırlatmalar 2000'den başlar.
abstract final class NotificationIds {
  static const int morningBriefing = 1001;
  static const int eveningClosing = 1002;
  static const int reminderBase = 2000;
}

/// Bildirimin dokununca açacağı rota (payload). Sözleşme: router yolu ("/today").
abstract final class NotificationPayloads {
  static const String morning = '/today';
  static const String evening = '/assistant/closure';
}

@immutable
class NotificationContent {
  const NotificationContent({required this.title, required this.body});
  final String title;
  final String body;
}

/// Günlük tekrarlayan bildirimin tanımı.
@immutable
class DailyNotification {
  const DailyNotification({
    required this.id,
    required this.channel,
    required this.hour,
    required this.minute,
    required this.content,
    required this.payload,
  });
  final int id;
  final NotificationChannelId channel;
  final int hour;
  final int minute;
  final NotificationContent content;
  final String payload;
}
