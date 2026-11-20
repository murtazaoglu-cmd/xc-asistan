// SAHİBİ: appointments ajanı. Saf (widget'sız) randevu mantığı: çakışma, takvim aralıkları,
// ertele seçenekleri, form doğrulaması. Hepsi İstanbul gününe göre çalışır.
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/phone.dart';
import 'appointment_models.dart';

/// Aynı kişiye atanmış, [window] içinde başka AÇIK randevular.
List<Appointment> findConflicts(
  Iterable<Appointment> existing, {
  required DateTime at,
  required String? assigneeId,
  String? excludeId,
  Duration window = const Duration(minutes: 60),
}) {
  if (assigneeId == null) return const [];
  return existing.where((a) {
    final t = a.scheduledAt;
    if (t == null || !a.isOpen || a.id == excludeId) return false;
    if (a.assignedUserId != assigneeId) return false;
    return t.difference(at).abs() < window;
  }).toList();
}

/// [instant]'ın haftasının 7 günü (Pzt..Paz), her biri günün başlangıcı (UTC an).
List<DateTime> weekDays(DateTime instant) {
  final r = Ist.weekRange(instant);
  final w = Ist.wall(r.start);
  return [for (var i = 0; i < 7; i++) Ist.fromWall(w.year, w.month, w.day + i)];
}

/// Ay görünümü ızgarası: ayın 1'ini içeren haftanın Pazartesi'sinden ayın son gününü
/// içeren haftanın Pazar'ına. 5 ya da 6 hafta.
InstantRange monthGridRange(DateTime instant) {
  final month = Ist.monthRange(instant);
  final first = weekDays(month.start).first;
  final lastDay = Ist.fromWall(
    Ist.wall(month.end).year,
    Ist.wall(month.end).month,
    Ist.wall(month.end).day - 1,
  );
  final lastWeekStart = weekDays(lastDay).first;
  final lw = Ist.wall(lastWeekStart);
  return InstantRange(first, Ist.fromWall(lw.year, lw.month, lw.day + 7));
}

/// Izgaradaki tüm günler (Pzt başlangıçlı), satır satır.
List<DateTime> monthGridDays(DateTime instant) {
  final r = monthGridRange(instant);
  final n = Ist.dayDiff(r.start, r.end);
  final w = Ist.wall(r.start);
  return [for (var i = 0; i < n; i++) Ist.fromWall(w.year, w.month, w.day + i)];
}

/// Günün başlangıcı → o gündeki randevular (sıralı değil; çağıran sıralar).
Map<DateTime, List<Appointment>> groupByDay(Iterable<Appointment> items) {
  final m = <DateTime, List<Appointment>>{};
  for (final a in items) {
    final t = a.scheduledAt;
    if (t == null) continue;
    (m[Ist.startOfDay(t)] ??= []).add(a);
  }
  return m;
}

@immutable
class SnoozeOption {
  const SnoozeOption(this.label, this.at);
  final String label;
  final DateTime at;
}

/// "Ertele" hızlı seçenekleri. Saatler İstanbul duvar saatine göredir.
List<SnoozeOption> snoozeOptions(DateTime scheduledAt, [DateTime? now]) {
  final n = now ?? Ist.now();
  final w = Ist.wall(scheduledAt);
  DateTime plusDays(int d) =>
      Ist.fromWall(w.year, w.month, w.day + d, w.hour, w.minute);
  final base = scheduledAt.isBefore(n) ? n : scheduledAt;
  return [
    SnoozeOption('1 saat sonra', base.add(const Duration(hours: 1))),
    SnoozeOption('Yarın aynı saat', plusDays(1)),
    SnoozeOption('Gelecek hafta aynı gün', plusDays(7)),
  ];
}

/// Form doğrulama sonucu: alan → hata metni (yoksa alan geçerli).
@immutable
class AppointmentFormErrors {
  const AppointmentFormErrors(this.byField);
  final Map<String, String> byField;
  bool get isValid => byField.isEmpty;
  String? operator [](String field) => byField[field];
}

/// [restricted]: saha rolü (yalnız durum, not, zaman). Kurallar sözleşme §9'dandır.
AppointmentFormErrors validateAppointmentForm({
  required String type,
  required DateTime? scheduledAt,
  required bool hasLink,
  required String customerName,
  required String customerPhone,
  required String address,
  required String notes,
  bool restricted = false,
}) {
  final e = <String, String>{};
  if (scheduledAt == null) e['scheduledAt'] = 'Tarih ve saat seçin.';
  if (notes.trim().length > 1000) {
    e['notes'] = 'Not en çok 1000 karakter olabilir.';
  }
  if (restricted) return AppointmentFormErrors(e);
  final t = type.trim();
  if (t.isEmpty) e['type'] = 'Tür seçin.';
  if (t.length > 40) e['type'] = 'Tür en çok 40 karakter olabilir.';
  if (!hasLink && customerName.trim().isEmpty) {
    e['customer'] = 'Müşteri seçin ya da ad girin.';
  }
  final p = customerPhone.trim();
  if (p.isNotEmpty && PhoneUtil.toInternational(p) == null) {
    e['phone'] = 'Geçerli bir telefon numarası girin.';
  }
  if (address.trim().length > 500) {
    e['address'] = 'Adres en çok 500 karakter olabilir.';
  }
  return AppointmentFormErrors(e);
}
