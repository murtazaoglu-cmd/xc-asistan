// SAHİBİ: jobs ajanı. Tekliflerde çoklu seçim: üst çubuklar + toplu durum / toplu silme akışları.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_bulk.dart';
import '../data/jobs_models.dart';
import '../data/jobs_repository.dart';
import 'jobs_common.dart';
import 'jobs_lists.dart' show offersListProvider;

/// Seçim kipi kapalıyken liste üstü: "18 KAYIT" + Seç düğmesi (eski panel başlığı).
class OfferListHeader extends StatelessWidget {
  const OfferListHeader({
    super.key,
    required this.total,
    required this.canSelect,
    required this.onSelect,
  });
  final int total;
  final bool canSelect;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.sm, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total KAYIT',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (canSelect)
            TextButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.checklist),
              label: const Text('Seç'),
            ),
        ],
      ),
    );
  }
}

/// Seçim kipi çubuğu: görünenleri seç, sayaç, temizle, kapat + toplu işlem düğmeleri.
class OfferSelectionBar extends StatelessWidget {
  const OfferSelectionBar({
    super.key,
    required this.selectedCount,
    required this.visibleCount,
    required this.total,
    required this.canStatus,
    required this.canDelete,
    required this.busy,
    required this.onToggleAll,
    required this.onClear,
    required this.onExit,
    required this.onStatus,
    required this.onDelete,
  });

  final int selectedCount;
  final int visibleCount;
  final int total;
  final bool canStatus;
  final bool canDelete;
  final bool busy;
  final VoidCallback onToggleAll;
  final VoidCallback onClear;
  final VoidCallback onExit;
  final VoidCallback onStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final all = visibleCount > 0 && selectedCount >= visibleCount;
    final any = selectedCount > 0;
    final scheme = context.colors;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.sm,
          Space.xs,
          Space.sm,
          Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: busy ? null : onToggleAll,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Sizes.minTouch,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            tristate: true,
                            value: all ? true : (any ? null : false),
                            onChanged: busy ? null : (_) => onToggleAll(),
                          ),
                          Expanded(
                            child: Text(
                              any
                                  ? '$selectedCount seçili'
                                  : 'Görünenleri seç ($visibleCount)',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (any)
                  TextButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Temizle'),
                  ),
                IconButton(
                  tooltip: 'Seçim kipinden çık',
                  onPressed: busy ? null : onExit,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (visibleCount < total && all)
              Padding(
                padding: const EdgeInsets.only(
                  left: Space.md,
                  bottom: Space.xs,
                ),
                child: Text(
                  'Yalnız yüklü $visibleCount kayıt seçildi (toplam $total).',
                  style: context.text.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  if (canStatus)
                    FilledButton.tonalIcon(
                      onPressed: any && !busy ? onStatus : null,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Durum değiştir'),
                    ),
                  if (canDelete)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(
                          color: any && !busy
                              ? scheme.error
                              : scheme.outlineVariant,
                        ),
                      ),
                      onPressed: any && !busy ? onDelete : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Sil'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Akışlar
// ---------------------------------------------------------------------------

String _label(Offer o) => '${o.code} · ${o.name}';

/// İlerleme penceresi: kapatmak için döndürülen işlevi çağırın. Rota doğrudan itilir/kaldırılır; yanıt
/// pencere çizilmeden gelse bile (hızlı ağ) pencere takılı kalmaz.
VoidCallback _showProgress(
  BuildContext context,
  String title,
  ValueNotifier<(int, int)> progress,
) {
  final nav = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
              const SizedBox(height: Space.md),
              Text('İşleniyor… ${v.$1}/${v.$2}'),
            ],
          ),
        ),
      ),
    ),
  );
  nav.push(route);
  return () {
    if (route.isActive) nav.removeRoute(route);
  };
}

/// Sonuç özeti: "5 işlem: 4 başarılı, 1 hatalı" + hatalı kayıtlar ve nedenleri.
Future<void> showBulkSummary(
  BuildContext context, {
  required String title,
  required BulkOutcome outcome,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(outcome.summary, style: ctx.text.titleSmall),
              if (outcome.failures.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text('Hatalı olanlar', style: ctx.text.labelLarge),
                const SizedBox(height: Space.xs),
                for (final f in outcome.failures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.target.label, style: ctx.text.bodyMedium),
                        Text(
                          f.reason,
                          style: ctx.text.bodySmall?.copyWith(
                            color: ctx.colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Space.xs),
                Text(
                  'Hatalı kayıtlar seçili bırakıldı; düzeltip yeniden deneyebilirsiniz.',
                  style: ctx.text.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}

/// Toplu durum değiştirme. Döner: sonuç (iptalde null). Çağıran liste/seçimi günceller.
Future<BulkOutcome?> bulkChangeOfferStatus(
  BuildContext context,
  WidgetRef ref,
  List<Offer> selected,
  OfferStatus next, {
  required void Function(Set<String> ids, String status) onApplied,
  required Future<void> Function() onRefresh,
}) async {
  final terms = ref.read(brandProfileProvider).terms;
  final repo = ref.read(jobsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (next == OfferStatus.kabulEdildi) {
    final ok = await ConfirmDialog.show(
      context,
      title:
          '${selected.length} ${terms.offer.toLowerCase()} kabul edilsin mi?',
      message:
          'Her biri için ${terms.job.toLowerCase()} oluşturulacak; bu işlem toplu geri alınamaz. Devam edilsin mi?',
      confirmLabel: 'Kabul et',
    );
    if (!ok || !context.mounted) return null;
  }
  final previous = {for (final o in selected) o.id: o.status};
  final progress = ValueNotifier<(int, int)>((0, selected.length));
  final close = _showProgress(context, 'Durum değiştiriliyor', progress);
  BulkOutcome outcome;
  try {
    outcome = await runBulk(
      targets: [for (final o in selected) BulkTarget(o.id, _label(o))],
      bulkCall: (ids) => repo.bulkSetOfferStatus(ids, next),
      single: (id) async {
        await repo.setOfferStatus(id, next);
      },
      isDone: (id) async => (await repo.offer(id)).status == next.api,
      skippedReason: 'Atlandı: erişiminiz yok ya da kabul edilmiş kaydın durumunu yalnız yönetici değiştirebilir.',
      onProgress: (d, t) => progress.value = (d, t),
    );
  } finally {
    close();
  }
  if (outcome.ok > 0) onApplied(outcome.succeededIds.toSet(), next.api);
  if (!context.mounted) {
    if (outcome.allOk) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${outcome.summary} · ${next.label}')),
        );
    }
    return outcome;
  }
  if (outcome.allOk) {
    final msg = '${outcome.ok} ${terms.offer.toLowerCase()}: ${next.label}';
    if (next == OfferStatus.kabulEdildi) {
      showJobsInfo(context, '$msg · ${terms.job.toLowerCase()} oluşturuldu');
    } else {
      UndoSnackbar.show(
        context,
        message: msg,
        onUndo: () async {
          // Eski durumlara göre grupla: her grup tek toplu çağrı.
          final groups = <String, List<String>>{};
          for (final id in outcome.succeededIds) {
            final prev = previous[id];
            if (OfferStatus.fromApi(prev) != null) {
              (groups[prev!] ??= []).add(id);
            }
          }
          try {
            for (final e in groups.entries) {
              await repo.bulkSetOfferStatus(
                e.value,
                OfferStatus.fromApi(e.key)!,
              );
            }
          } catch (e) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(AppException.from(e).message)),
              );
          }
          await onRefresh();
        },
      );
    }
  } else {
    await showBulkSummary(
      context,
      title: 'Toplu durum değiştirme',
      outcome: outcome,
    );
  }
  return outcome;
}

/// Toplu silme: onay → listeden gizle → "Geri al" süresi → gerçek DELETE (parça parça).
/// [onHide] kayıtları listeden anında çıkarır; [onRefresh] listeyi sunucudan yeniler (geri al / bitiş);
/// [onFailed] silinemeyenleri (varsa) seçili bırakmak için çağrılır.
Future<void> bulkDeleteOffers(
  BuildContext context,
  WidgetRef ref,
  List<Offer> selected, {
  required void Function(Set<String> ids) onHide,
  required Future<void> Function() onRefresh,
  required void Function(Set<String> failedIds) onFailed,
  Duration undoWindow = UndoSnackbar.defaultDuration,
}) async {
  final terms = ref.read(brandProfileProvider).terms;
  final repo = ref.read(jobsRepositoryProvider);
  final n = selected.length;
  final preview = selected.take(3).map((o) => o.code).join(', ');
  final ok = await ConfirmDialog.show(
    context,
    title: '$n ${terms.offer.toLowerCase()} silinsin mi?',
    message:
        '$preview${n > 3 ? ' ve ${n - 3} kayıt daha' : ''}. '
        'Silme geri alınamaz; yalnız kendi oluşturduğunuz kayıtlar silinebilir (yönetici hepsini silebilir).',
    confirmLabel: 'Sil',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final container = ProviderScope.containerOf(context);
  final navigatorContext = context;
  final targets = [for (final o in selected) BulkTarget(o.id, _label(o))];
  onHide({for (final o in selected) o.id});
  await UndoSnackbar.deferred(
    context,
    message: '$n ${terms.offer.toLowerCase()} silindi',
    duration: undoWindow,
    onUndo: () async {
      await onRefresh();
    },
    onCommit: () async {
      final progress = ValueNotifier<(int, int)>((0, n));
      final close = navigatorContext.mounted
          ? _showProgress(navigatorContext, 'Siliniyor', progress)
          : () {};
      BulkOutcome outcome;
      try {
        outcome = await runBulk(
          targets: targets,
          bulkCall: (ids) => repo.bulkDeleteOffers(ids),
          single: (id) async {
            try {
              await repo.deleteOffer(id);
            } on AppException catch (e) {
              if (e.code != AppErrorCode.notFound) rethrow;
            }
          },
          isDone: (id) async {
            try {
              await repo.offer(id);
              return false;
            } on AppException catch (e) {
              if (e.code == AppErrorCode.notFound) return true;
              rethrow;
            }
          },
          skippedReason: 'Silinemedi: yalnız kendi oluşturduğunuz kayıtları silebilirsiniz.',
          onProgress: (d, t) => progress.value = (d, t),
        );
      } finally {
        close();
      }
      container.invalidate(offersListProvider);
      if (!outcome.allOk) {
        onFailed({for (final f in outcome.failures) f.target.id});
        if (navigatorContext.mounted) {
          await showBulkSummary(
            navigatorContext,
            title: 'Toplu silme',
            outcome: outcome,
          );
        }
      }
      await onRefresh();
    },
  );
}
