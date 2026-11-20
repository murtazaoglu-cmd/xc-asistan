// SAHİBİ: appointments ajanı. Randevu eylemlerinin ortak arayüz yardımcıları (Bugün, Randevular,
// Saha ekranı ve detay aynı davranışı paylaşır): durum değiştir + geri al, ertele, sil + geri al,
// tarih-saat seçici. Tüm zaman bileşenleri İSTANBUL duvar saatidir (cihaz dilimi kullanılmaz).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../application/appointment_providers.dart';
import '../data/appointment_logic.dart';
import '../data/appointment_models.dart';

/// Sunucuya giden panel değerleri (sözleşme §0): `beklemede onaylandı tamamlandı iptal`.
abstract final class AppointmentStatus {
  static const pending = 'beklemede';
  static const confirmed = 'onaylandı';
  static const done = 'tamamlandı';
  static const cancelled = 'iptal';
}

abstract final class AppointmentUi {
  static void error(BuildContext context, Object e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(AppException.from(e).message)));
  }

  /// Tek dokunuşla durum değiştirir; "Geri al" ile eski duruma döner.
  /// [context] kartın değil EKRANIN bağlamı olmalı (liste yenilenince kartlar yok olur).
  static Future<bool> changeStatus(
    BuildContext context,
    WidgetRef ref,
    Appointment a,
    String status,
  ) async {
    final actions = ref.read(appointmentActionsProvider);
    final previous = a.status;
    try {
      await actions.setStatus(a.id, status);
    } catch (e) {
      if (context.mounted) error(context, e);
      return false;
    }
    if (!context.mounted) return true;
    final message = switch (status) {
      AppointmentStatus.done => 'Tamamlandı olarak işaretlendi.',
      AppointmentStatus.cancelled => 'İptal edildi.',
      AppointmentStatus.confirmed => 'Onaylandı.',
      _ => 'Durum güncellendi.',
    };
    UndoSnackbar.show(
      context,
      message: message,
      onUndo: () async {
        try {
          await actions.setStatus(a.id, previous);
        } catch (e) {
          if (context.mounted) error(context, e);
        }
      },
    );
    return true;
  }

  static Future<bool> reschedule(
    BuildContext context,
    WidgetRef ref,
    Appointment a,
    DateTime at,
  ) async {
    final actions = ref.read(appointmentActionsProvider);
    final previous = a.scheduledAt;
    try {
      await actions.reschedule(a.id, at);
    } catch (e) {
      if (context.mounted) error(context, e);
      return false;
    }
    if (!context.mounted) return true;
    UndoSnackbar.show(
      context,
      message: 'Ertelendi: ${Fmt.relativeDateTime(at)}',
      onUndo: () async {
        if (previous == null) return;
        try {
          await actions.reschedule(a.id, previous);
        } catch (e) {
          if (context.mounted) error(context, e);
        }
      },
    );
    return true;
  }

  /// Ertele alt sayfası: hızlı seçenekler + "Tarih ve saat seç…".
  static Future<void> snooze(
    BuildContext context,
    WidgetRef ref,
    Appointment a,
  ) async {
    final base = a.scheduledAt ?? Ist.now();
    final options = snoozeOptions(base);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ertele', style: ctx.text.titleMedium),
              ),
            ),
            for (final o in options)
              ListTile(
                minTileHeight: Sizes.minTouch,
                leading: const Icon(Icons.update),
                title: Text(o.label),
                subtitle: Text(Fmt.relativeDateTime(o.at)),
                onTap: () => Navigator.of(ctx).pop(o.at),
              ),
            ListTile(
              minTileHeight: Sizes.minTouch,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Tarih ve saat seç…'),
              onTap: () => Navigator.of(ctx).pop('custom'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    DateTime? at;
    if (picked is DateTime) {
      at = picked;
    } else {
      at = await pickDateTime(context, initial: base);
    }
    if (at == null || !context.mounted) return;
    await reschedule(context, ref, a, at);
  }

  /// Silme: kayıt hemen listeden gizlenir, gerçek DELETE "Geri al" süresi dolunca gider.
  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    Appointment a,
  ) async {
    final actions = ref.read(appointmentActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    actions.hide(a.id);
    await UndoSnackbar.deferred(
      context,
      message: 'Randevu silindi.',
      onUndo: () => actions.unhide(a.id),
      onCommit: () async {
        try {
          await actions.delete(a.id);
        } catch (e) {
          actions.unhide(a.id);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(AppException.from(e).message)),
            );
        }
      },
    );
  }

  /// Gün + saat seçici. Dönüş: gerçek an (UTC) ya da null (vazgeçildi).
  static Future<DateTime?> pickDateTime(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final w = Ist.wall(initial ?? Ist.now());
    final date = await pickDate(context, initial: initial);
    if (date == null || !context.mounted) return null;
    final time = await pickTime(context, hour: w.hour, minute: w.minute);
    if (time == null) return null;
    final d = Ist.wall(date);
    return Ist.fromWall(d.year, d.month, d.day, time.hour, time.minute);
  }

  /// Yalnız gün seçici; dönüş günün başlangıcı (UTC an).
  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final w = Ist.wall(initial ?? Ist.now());
    final nowW = Ist.wall(Ist.now());
    final first = DateTime(nowW.year - 1);
    final last = DateTime(nowW.year + 3, 12, 31);
    var init = DateTime(w.year, w.month, w.day);
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      helpText: 'Tarih seç',
      cancelText: 'Vazgeç',
      confirmText: 'Tamam',
    );
    if (d == null) return null;
    return Ist.fromWall(d.year, d.month, d.day);
  }

  static Future<TimeOfDay?> pickTime(
    BuildContext context, {
    required int hour,
    required int minute,
  }) => showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: hour, minute: minute),
    helpText: 'Saat seç',
    cancelText: 'Vazgeç',
    confirmText: 'Tamam',
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}
