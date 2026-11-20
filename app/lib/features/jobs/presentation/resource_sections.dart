// SAHİBİ: jobs ajanı. Teklif ve projede ortak bölümler: Belgeler (/documents), Paylaşım (/shares),
// Aktivite (/activity). Dosya adresleri 10 dk geçerli imzalıdır: saklanmaz, açarken liste yenilenir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart' show currentUserProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/document_picker.dart';
import '../data/jobs_access.dart';
import '../data/jobs_project_models.dart';
import '../data/jobs_repository.dart';
import 'jobs_common.dart';

/// "Yeniden dene" düğmeli satır içi hata (kart içinde tam ekran hata yerine).
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppException.from(error).message,
          style: context.text.bodyMedium?.copyWith(color: context.colors.error),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      ],
    );
  }
}

class InlineSkeleton extends StatelessWidget {
  const InlineSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SkeletonBox(height: 48),
      SizedBox(height: Space.sm),
      SkeletonBox(height: 48),
    ],
  );
}

/// Seç → doğrula (izin listesi, 15 MB) → yükle → belge listesini yenile. Döner: yüklendi mi.
/// [onProgress]: null = bitti, 0 = başladı, 0..1 ilerleme.
Future<bool> pickAndUploadDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String type,
  required String id,
  required Future<PickedDocument?> Function() pick,
  void Function(double? progress)? onProgress,
}) async {
  PickedDocument? file;
  try {
    file = await pick();
  } catch (e) {
    if (context.mounted) showJobsError(context, e);
    return false;
  }
  if (file == null || !context.mounted) return false;
  final problem = DocumentRules.validate(file.name, file.size);
  if (problem != null) {
    showJobsInfo(context, problem);
    return false;
  }
  onProgress?.call(0);
  try {
    await ref
        .read(jobsRepositoryProvider)
        .uploadDocument(
          type,
          id,
          filePath: file.path,
          fileName: file.name,
          onProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
        );
    ref.invalidate(documentsProvider((type: type, id: id)));
    ref.invalidate(activityProvider((type: type, id: id)));
    if (context.mounted) showJobsInfo(context, '${file.name} yüklendi.');
    return true;
  } catch (e) {
    if (context.mounted) showJobsError(context, e);
    return false;
  } finally {
    onProgress?.call(null);
  }
}

// ---------------------------------------------------------------------------
// Belgeler
// ---------------------------------------------------------------------------

class DocumentsSection extends ConsumerStatefulWidget {
  const DocumentsSection({
    super.key,
    required this.type,
    required this.id,
    this.title = 'Belgeler',
  });

  /// `offer` | `project`
  final String type;
  final String id;
  final String title;

  @override
  ConsumerState<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends ConsumerState<DocumentsSection> {
  double? _progress;
  final Set<String> _hidden = {};

  ResourceKey get _key => (type: widget.type, id: widget.id);

  Future<void> _upload(Future<PickedDocument?> Function() pick) async {
    if (_progress != null) return;
    await pickAndUploadDocument(
      context: context,
      ref: ref,
      type: widget.type,
      id: widget.id,
      pick: pick,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
  }

  Future<void> _open(DocumentItem d) async {
    try {
      // İmzalı bağlantı 10 dk geçerli: açmadan önce listeyi yenile.
      final fresh = await ref.refresh(documentsProvider(_key).future);
      final cur = fresh.where((e) => e.id == d.id).firstOrNull ?? d;
      if (!mounted) return;
      if (cur.isImage) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    child: Image.network(
                      cur.fileUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text('Görsel yüklenemedi. Kapatıp tekrar açın.'),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: 'Kapat',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final ok = await ref
            .read(linkLauncherProvider)
            .open(Uri.parse(cur.fileUrl));
        if (!ok && mounted) showJobsInfo(context, 'Dosya açılamadı.');
      }
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  void _delete(DocumentItem d) {
    final repo = ref.read(jobsRepositoryProvider);
    setState(() => _hidden.add(d.id));
    UndoSnackbar.deferred(
      context,
      message: '${d.fileName} silindi',
      onUndo: () {
        if (mounted) setState(() => _hidden.remove(d.id));
      },
      onCommit: () async {
        try {
          await repo.deleteDocument(d.id);
        } catch (e) {
          if (mounted) {
            setState(() => _hidden.remove(d.id));
            showJobsError(context, e);
          }
        }
        if (mounted) ref.invalidate(documentsProvider(_key));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider(_key));
    return SectionCard(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _progress != null
                    ? null
                    : () => _upload(ref.read(documentPickerProvider).takePhoto),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Fotoğraf çek'),
              ),
              OutlinedButton.icon(
                onPressed: _progress != null
                    ? null
                    : () => _upload(ref.read(documentPickerProvider).pickPhoto),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeriden'),
              ),
              OutlinedButton.icon(
                onPressed: _progress != null
                    ? null
                    : () => _upload(ref.read(documentPickerProvider).pickFile),
                icon: const Icon(Icons.attach_file),
                label: const Text('Belge seç'),
              ),
            ],
          ),
          if (_progress != null) ...[
            const SizedBox(height: Space.md),
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              semanticsLabel: 'Yükleniyor',
            ),
          ],
          const SizedBox(height: Space.md),
          docs.when(
            loading: () => const InlineSkeleton(),
            error: (e, _) => InlineError(
              error: e,
              onRetry: () => ref.invalidate(documentsProvider(_key)),
            ),
            data: (list) {
              final shown = list.where((d) => !_hidden.contains(d.id)).toList();
              if (shown.isEmpty) {
                return Text(
                  'Henüz belge ya da fotoğraf yok.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: [
                  for (final d in shown)
                    _DocumentTile(
                      doc: d,
                      onOpen: () => _open(d),
                      onDelete: () => _delete(d),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.onOpen,
    required this.onDelete,
  });
  final DocumentItem doc;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget leading = doc.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xs),
            child: Image.network(
              doc.fileUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.image_outlined),
              ),
            ),
          )
        : SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              doc.isPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.description_outlined,
            ),
          );
    return ListTile(
      minTileHeight: Sizes.minTouch + Space.sm,
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (doc.uploadedByName != null) doc.uploadedByName!,
          DateText.format(doc.createdAt, DateTextMode.date),
        ].join(' · '),
      ),
      onTap: onOpen,
      trailing: IconButton(
        tooltip: 'Sil',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paylaşım
// ---------------------------------------------------------------------------

class SharesSection extends ConsumerWidget {
  const SharesSection({super.key, required this.type, required this.id});
  final String type;
  final String id;

  ResourceKey get _key => (type: type, id: id);

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<ShareItem> current,
  ) async {
    final access = ref.read(jobsAccessProvider);
    if (!access.canListUsers) {
      showJobsInfo(
        context,
        'Kullanıcı listesine erişiminiz yok. Paylaşımı yönetici yapabilir.',
      );
      return;
    }
    final picked = await showModalBottomSheet<PersonRef>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final users = ref.watch(shareCandidatesProvider);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
              ),
              child: users.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.lg),
                  child: InlineSkeleton(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: InlineError(
                    error: e,
                    onRetry: () => ref.invalidate(shareCandidatesProvider),
                  ),
                ),
                data: (list) {
                  // Kendisi aday olmaz (GET /users artık oturum sahibini de döner).
                  final me = ref.watch(currentUserProvider)?.id;
                  final taken = {...current.map((e) => e.userId), ?me};
                  final avail = list
                      .where((u) => !taken.contains(u.id))
                      .toList();
                  if (avail.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: Text('Paylaşılabilecek başka kullanıcı yok.'),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in avail)
                        ListTile(
                          minTileHeight: Sizes.minTouch,
                          leading: const Icon(Icons.person_outline),
                          title: Text(u.name),
                          subtitle: u.role == null ? null : Text(u.role!),
                          onTap: () => Navigator.of(ctx).pop(u),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref.read(jobsRepositoryProvider).addShare(type, id, picked.id);
      ref.invalidate(sharesProvider(_key));
      if (context.mounted)
        showJobsInfo(context, '${picked.name} ile paylaşıldı.');
    } catch (e) {
      if (context.mounted) showJobsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(sharesProvider(_key));
    final access = ref.watch(jobsAccessProvider);
    return SectionCard(
      title: 'Paylaşım',
      trailing: access.canShare
          ? TextButton.icon(
              onPressed: () => _add(context, ref, shares.value ?? const []),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Paylaş'),
            )
          : null,
      child: shares.when(
        loading: () => const InlineSkeleton(),
        error: (e, _) => InlineError(
          error: e,
          onRetry: () => ref.invalidate(sharesProvider(_key)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Text(
              'Kimseyle paylaşılmadı.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            );
          }
          return Column(
            children: [
              for (final s in list)
                ListTile(
                  minTileHeight: Sizes.minTouch,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(s.userName ?? 'Kullanıcı'),
                  subtitle: s.userEmail == null ? null : Text(s.userEmail!),
                  trailing: access.canShare
                      ? IconButton(
                          tooltip: 'Paylaşımı kaldır',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () async {
                            final ok = await ConfirmDialog.show(
                              context,
                              title: 'Paylaşım kaldırılsın mı?',
                              message:
                                  '${s.userName ?? 'Kullanıcı'} bu kayda erişemeyecek.',
                              confirmLabel: 'Kaldır',
                              destructive: true,
                            );
                            if (!ok || !context.mounted) return;
                            try {
                              await ref
                                  .read(jobsRepositoryProvider)
                                  .removeShare(s.id);
                              ref.invalidate(sharesProvider(_key));
                            } catch (e) {
                              if (context.mounted) showJobsError(context, e);
                            }
                          },
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aktivite
// ---------------------------------------------------------------------------

class ActivityList extends ConsumerWidget {
  const ActivityList({super.key, required this.type, required this.id});
  final String type;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (type: type, id: id);
    final async = ref.watch(activityProvider(key));
    return async.when(
      loading: () => const InlineSkeleton(),
      error: (e, _) => InlineError(
        error: e,
        onRetry: () => ref.invalidate(activityProvider(key)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            'Henüz kayıtlı hareket yok.',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          );
        }
        return Column(
          children: [
            for (final a in list)
              ListTile(
                minTileHeight: Sizes.minTouch,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(
                  a.details == null || a.details!.isEmpty
                      ? a.label
                      : '${a.label}: ${a.details}',
                ),
                subtitle: Text(
                  [
                    if (a.userName != null) a.userName!,
                    DateText.format(a.createdAt, DateTextMode.dateTime),
                  ].join(' · '),
                ),
              ),
          ],
        );
      },
    );
  }
}
