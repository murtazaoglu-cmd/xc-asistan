// SAHİBİ: home ajanı. "Asistan Özeti": /mobile/home verisinden İSTEMCİ TARAFLI, kural tabanlı
// cümleler. Sayılar kodla hesaplanır (yapay zekâ kullanılmaz); sektör terimleri sözlükten gelir.
import 'package:flutter/foundation.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../appointments/data/appointment_models.dart';
import '../../appointments/data/tr_text.dart';
import 'home_models.dart';

enum InsightKind {
  appointments,
  nextUp,
  late,
  tomorrow,
  offers,
  awaiting,
  overdueProjects,
  receivables,
  reminders,
  lowStock,
  calm,
}

enum InsightLevel { info, attention, urgent }

@immutable
class InsightLine {
  const InsightLine(this.kind, this.level, this.text, {this.route});
  final InsightKind kind;
  final InsightLevel level;
  final String text;

  /// Dokununca gidilecek yol (yoksa null).
  final String? route;
}

/// Önem sırasına göre sıralı özet satırları. [caps] hangi bölümlerin anlatılacağını belirler
/// (saha: finans/teklif/iş yok).
List<InsightLine> buildInsights(
  HomeSummary s, {
  required AppCapabilities caps,
  required Glossary terms,
  DateTime? now,
}) {
  final n = now ?? Ist.now();
  final appt = trLower(terms.appointment);
  final lines = <InsightLine>[];

  // 1) Bugünün randevuları
  final today = s.today.where((a) => !a.isCancelled).toList();
  final late = today.where((a) => a.isOverdue(n)).toList();
  final open = today.where((a) => a.isOpen).toList();
  final done = today.where((a) => a.isDone).length;
  if (today.isEmpty) {
    lines.add(
      InsightLine(
        InsightKind.appointments,
        InsightLevel.info,
        'Bugün $appt yok.',
        route: Routes.appointments,
      ),
    );
  } else {
    lines.add(
      InsightLine(
        InsightKind.appointments,
        InsightLevel.info,
        'Bugün ${today.length} $appt var'
        '${done > 0 ? ' ($done tamamlandı)' : ''}.',
        route: Routes.appointments,
      ),
    );
    final upcoming = open.where((a) => !a.isOverdue(n)).toList()
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    if (upcoming.isNotEmpty) {
      final a = upcoming.first;
      final who = a.displayName == null ? '' : ', ${a.displayName}';
      lines.add(
        InsightLine(
          InsightKind.nextUp,
          InsightLevel.info,
          'Sıradaki: ${Fmt.time(a.scheduledAt!)} '
          '${terms.appointmentTypeLabel(a.type)}$who.',
          route: Routes.appointment(a.id),
        ),
      );
    }
  }
  if (late.isNotEmpty) {
    lines.add(
      InsightLine(
        InsightKind.late,
        InsightLevel.urgent,
        '${late.length} $appt zamanı geçti ama hâlâ açık.',
        route: Routes.appointments,
      ),
    );
  }
  final tomorrow = s.tomorrow.where((a) => !a.isCancelled).length;
  if (tomorrow > 0) {
    lines.add(
      InsightLine(
        InsightKind.tomorrow,
        InsightLevel.info,
        'Yarın $tomorrow $appt var.',
        route: Routes.appointments,
      ),
    );
  }

  // 2) Teklif talepleri (saha ve teklif yetkisiz roller görmez)
  final newOffers = s.newOfferCount;
  if (caps.offers && newOffers != null && newOffers > 0) {
    lines.add(
      InsightLine(
        InsightKind.offers,
        InsightLevel.attention,
        '$newOffers yeni ${trLower(terms.offer)} talebi yanıt bekliyor.',
        route: Routes.jobs,
      ),
    );
  }
  final waiting = s.offerStats?.awaitingResponse ?? 0;
  if (caps.offers && waiting > 0) {
    lines.add(
      InsightLine(
        InsightKind.awaiting,
        InsightLevel.info,
        '$waiting ${trLower(terms.offer)} müşterinin yanıtını bekliyor.',
        route: Routes.jobs,
      ),
    );
  }

  // 3) Geciken işler
  if (caps.projects && s.overdueProjectCount > 0) {
    final worst = s.overdueProjects.fold<int>(
      0,
      (m, p) => p.daysOverdue > m ? p.daysOverdue : m,
    );
    lines.add(
      InsightLine(
        InsightKind.overdueProjects,
        InsightLevel.urgent,
        '${s.overdueProjectCount} ${trLower(terms.job)} bitiş tarihini geçti'
        '${worst > 0 ? ' (en çok $worst gün)' : ''}.',
        route: Routes.jobs,
      ),
    );
  }

  // 4) Tahsilat (yalnız finans verisi gelen roller: A/M/O)
  final fin = s.finance;
  if (caps.homeFinance && fin != null) {
    if (fin.receivableTotal.isPositive) {
      lines.add(
        InsightLine(
          InsightKind.receivables,
          InsightLevel.attention,
          'Toplam alacak ${fin.receivableTotal.format(hideZeroKurus: true)}'
          '${fin.receivableProjectCount > 0 ? ' (${fin.receivableProjectCount} ${trLower(terms.job)})' : ''}.',
          route: Routes.finance,
        ),
      );
    }
  }

  // 5) Hatırlatıcılar
  if (s.remindersOverdue.isNotEmpty) {
    lines.add(
      InsightLine(
        InsightKind.reminders,
        InsightLevel.urgent,
        '${s.remindersOverdue.length} gecikmiş hatırlatıcı var.',
      ),
    );
  }
  if (s.remindersToday.isNotEmpty) {
    lines.add(
      InsightLine(
        InsightKind.reminders,
        InsightLevel.info,
        'Bugün ${s.remindersToday.length} hatırlatıcı var.',
      ),
    );
  }

  // 6) Düşük stok
  if (caps.materials && s.lowStockCount > 0) {
    lines.add(
      InsightLine(
        InsightKind.lowStock,
        InsightLevel.attention,
        '${s.lowStockCount} kalem ${trLower(terms.stock)} azaldı ya da bitti.',
        route: Routes.stock,
      ),
    );
  }

  // Hiçbir dikkat gerektiren şey yoksa sakin gün cümlesi.
  final onlyBasics = lines.every(
    (l) =>
        l.kind == InsightKind.appointments ||
        l.kind == InsightKind.nextUp ||
        l.kind == InsightKind.tomorrow,
  );
  if (onlyBasics) {
    lines.add(
      const InsightLine(
        InsightKind.calm,
        InsightLevel.info,
        'Bekleyen başka bir iş, hatırlatıcı ya da yeni talep görünmüyor.',
      ),
    );
  }
  return lines;
}

/// Bugün ekranı "boş gün" mü? (randevu, talep, gecikme, hatırlatıcı, stok: hepsi sıfır).
bool isQuietDay(HomeSummary s, AppCapabilities caps) {
  return s.today.every((a) => a.isCancelled) &&
      s.tomorrow.every((a) => a.isCancelled) &&
      (!caps.offers || (s.newOfferCount ?? 0) == 0) &&
      (!caps.projects || s.overdueProjectCount == 0) &&
      s.reminderCount == 0 &&
      (!caps.materials || s.lowStockCount == 0);
}

/// Saha: sıradaki işlem yapılabilir (açık, adresi olan) bugünkü randevular.
List<Appointment> fieldJobs(HomeSummary s) =>
    s.today.where((a) => !a.isCancelled).toList()..sort(
      (a, b) => (a.scheduledAt ?? DateTime.utc(0)).compareTo(
        b.scheduledAt ?? DateTime.utc(0),
      ),
    );

/// Hatırlatıcı erteleme seçenekleri (İstanbul duvar saati). [now] verilir.
List<SnoozeChoice> reminderSnoozeChoices(DateTime now) {
  final w = Ist.wall(now);
  DateTime at9(int plusDays) =>
      Ist.fromWall(w.year, w.month, w.day + plusDays, 9);
  return [
    SnoozeChoice('1 saat sonra', now.add(const Duration(hours: 1))),
    SnoozeChoice('Yarın 09:00', at9(1)),
    SnoozeChoice('3 gün sonra 09:00', at9(3)),
    SnoozeChoice('Gelecek hafta 09:00', at9(7)),
  ];
}

@immutable
class SnoozeChoice {
  const SnoozeChoice(this.label, this.at);
  final String label;
  final DateTime at;
}
