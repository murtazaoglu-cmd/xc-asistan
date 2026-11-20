// SAHİBİ: home ajanı. Saha ekranının büyük düğme akışları: konum/yol tarifi, fotoğraf yükle
// (kamera/galeri → POST /documents/...), iş tamamla. Hepsi bugünkü işler listesinden çalışır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../../appointments/data/appointment_models.dart';
import '../../appointments/presentation/appointment_ui.dart';
import '../data/home_repository.dart';
import '../data/photo_source.dart';

abstract final class FieldActions {
  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _jobLabel(Appointment a, String typeLabel) {
    final t = a.scheduledAt == null ? '' : '${Fmt.time(a.scheduledAt!)} ';
    return '$t$typeLabel${a.displayName == null ? '' : ' · ${a.displayName}'}';
  }

  /// Birden çok aday varsa seçtirir; tek adayda doğrudan döner.
  static Future<Appointment?> _choose(
    BuildContext context, {
    required List<Appointment> candidates,
    required String title,
    required String Function(Appointment) label,
  }) async {
    if (candidates.length == 1) return candidates.first;
    return showModalBottomSheet<Appointment>(
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
                child: Text(title, style: ctx.text.titleMedium),
              ),
            ),
            for (final a in candidates)
              ListTile(
                minTileHeight: Sizes.minTouch + 8,
                title: Text(label(a)),
                subtitle: a.address == null ? null : Text(a.address!),
                onTap: () => Navigator.of(ctx).pop(a),
              ),
          ],
        ),
      ),
    );
  }

  /// Sıradaki adresli açık iş için harita yol tarifi.
  static Future<void> directions(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> jobs,
    String Function(String type) typeLabel,
  ) async {
    final withPlace = jobs
        .where(
          (a) =>
              a.isOpen &&
              ((a.lat != null && a.lng != null) ||
                  (a.address != null && a.address!.trim().isNotEmpty)),
        )
        .toList();
    if (withPlace.isEmpty) {
      _snack(context, 'Bugün adresi olan açık iş yok.');
      return;
    }
    final job = await _choose(
      context,
      candidates: withPlace,
      title: 'Hangi işe gidiyorsunuz?',
      label: (a) => _jobLabel(a, typeLabel(a.type)),
    );
    if (job == null || !context.mounted) return;
    final ok = await ref
        .read(contactLauncherProvider)
        .directions(address: job.address, lat: job.lat, lng: job.lng);
    if (!ok && context.mounted) _snack(context, 'Harita uygulaması açılamadı.');
  }

  /// "İş tamamla": açık işlerden birini onaylayıp `tamamlandı` yapar (geri al'lı).
  static Future<void> complete(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> jobs,
    String Function(String type) typeLabel,
  ) async {
    final open = jobs.where((a) => a.isOpen).toList();
    if (open.isEmpty) {
      _snack(context, 'Tamamlanacak açık iş yok.');
      return;
    }
    final job = await _choose(
      context,
      candidates: open,
      title: 'Hangi işi tamamladınız?',
      label: (a) => _jobLabel(a, typeLabel(a.type)),
    );
    if (job == null || !context.mounted) return;
    final yes = await ConfirmDialog.show(
      context,
      title: 'İş tamamlandı mı?',
      message: _jobLabel(job, typeLabel(job.type)),
      confirmLabel: 'Tamamlandı',
    );
    if (!yes || !context.mounted) return;
    await AppointmentUi.changeStatus(context, ref, job, AppointmentStatus.done);
  }

  /// Fotoğraf yükleme. [target] verilmezse bağlı kaydı olan işlerden seçtirilir.
  static Future<void> uploadPhoto(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> jobs,
    String Function(String type) typeLabel, {
    Appointment? target,
  }) async {
    var job = target;
    if (job == null) {
      final linked = jobs.where((a) => a.hasLink && !a.isCancelled).toList();
      if (linked.isEmpty) {
        _snack(
          context,
          'Fotoğraf eklemek için bir teklif ya da projeye bağlı iş gerekir.',
        );
        return;
      }
      job = await _choose(
        context,
        candidates: linked,
        title: 'Fotoğraf hangi işe eklensin?',
        label: (a) => _jobLabel(a, typeLabel(a.type)),
      );
    }
    if (job == null || !context.mounted) return;
    final origin = await showModalBottomSheet<PhotoOrigin>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: Sizes.minTouch + 8,
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.of(ctx).pop(PhotoOrigin.camera),
            ),
            ListTile(
              minTileHeight: Sizes.minTouch + 8,
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.of(ctx).pop(PhotoOrigin.gallery),
            ),
          ],
        ),
      ),
    );
    if (origin == null || !context.mounted) return;
    PickedPhoto? photo;
    try {
      photo = await ref.read(photoSourceProvider).pick(origin);
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'Kamera ya da galeriye erişilemedi. İzinleri kontrol edin.',
        );
      }
      return;
    }
    if (photo == null || !context.mounted) return;
    await _upload(context, ref, job, photo);
  }

  static Future<void> _upload(
    BuildContext context,
    WidgetRef ref,
    Appointment job,
    PickedPhoto photo,
  ) async {
    final repo = ref.read(homeRepositoryProvider);
    final type = job.projectId != null ? 'project' : 'offer';
    final id = (job.projectId ?? job.offerId)!;
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double?>(null);
    // Yükleme sürerken kapatılamayan küçük ilerleme penceresi.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Fotoğraf yükleniyor'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, v, _) => LinearProgressIndicator(value: v),
          ),
        ),
      ),
    );
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      await repo.uploadDocument(
        resourceType: type,
        resourceId: id,
        filePath: photo.path,
        fileName: photo.name,
        onProgress: (s, t) => progress.value = t > 0 ? s / t : null,
      );
      nav.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fotoğraf yüklendi.')));
    } catch (e) {
      nav.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppException.from(e).message),
            action: SnackBarAction(
              label: 'Tekrar dene',
              onPressed: () {
                if (context.mounted) _upload(context, ref, job, photo);
              },
            ),
          ),
        );
    } finally {
      progress.dispose();
    }
  }
}
