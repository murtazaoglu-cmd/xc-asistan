// SAHİBİ: jobs ajanı. Proje aşaması değiştirme: liste kartı ve proje detayı AYNI mantığı kullanır
// (onay, hata, Geri al, çift dokunuş koruması). Aşama sırası: ProjectStage.values.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_repository.dart';

/// Şu an aşama değişimi süren proje kimlikleri (çift dokunuşu ve yarışı engeller).
class StageBusy extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isBusy(String id) => state.contains(id);

  bool begin(String id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }

  void end(String id) => state = {...state}..remove(id);
}

final stageBusyProvider = NotifierProvider<StageBusy, Set<String>>(
  StageBusy.new,
);

/// Sıradaki aşama; son aşamada (Tamamlandı) ya da bilinmeyen aşamada null.
ProjectStage? nextStageOf(ProjectStage? s) {
  if (s == null || s == ProjectStage.values.last) return null;
  return ProjectStage.values[s.index + 1];
}

/// Aşama seçim alt sayfası (tüm aşamalar; ileri ya da geri). Seçilen aşamayı döner.
Future<ProjectStage?> showProjectStageSheet(
  BuildContext context,
  ProjectStage? current,
) {
  return showModalBottomSheet<ProjectStage>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Aşamayı değiştir', style: ctx.text.titleMedium),
              ),
            ),
            for (final s in ProjectStage.values)
              ListTile(
                minTileHeight: Sizes.minTouch,
                selected: s == current,
                leading: Icon(
                  s == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(s.label),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Birincil "Sonraki aşama: X →" düğmesi (≥48dp; dar ekranda/büyük yazıda satır kırar).
class StageNextButton extends StatelessWidget {
  const StageNextButton({
    super.key,
    required this.next,
    required this.onPressed,
    this.expand = false,
  });

  final ProjectStage next;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(Sizes.minTouch, Sizes.minTouch),
      ),
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward),
      label: Text(
        'Sonraki aşama: ${next.label}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Aşamayı [next] yapar. Tamamlandıya geçerken onay sorar; başarıda "Aşama: X" + Geri al.
/// [onChanged] ham aşama adıyla çağrılır: [optimistic] true ise HEMEN (hata olursa eski değerle
/// tekrar), false ise yalnız sunucu başarısından sonra. Döner: değişti mi.
/// Not: bu sırada çağıran widget ağaçtan çıkabilir; bu yüzden her şey `await` ÖNCESİ alınır.
Future<bool> changeProjectStage(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required ProjectStage? current,
  required ProjectStage next,
  required void Function(String stage) onChanged,
  bool optimistic = false,
}) async {
  if (current == next) return false;
  final terms = ref.read(brandProfileProvider).terms;
  final repo = ref.read(jobsRepositoryProvider);
  final busy = ref.read(stageBusyProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  if (busy.isBusy(projectId)) return false;

  void error(Object e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(AppException.from(e).message)),
    );
  }

  if (next == ProjectStage.tamamlandi) {
    final ok = await ConfirmDialog.show(
      context,
      title: '${terms.job} tamamlandı mı?',
      message: 'Bitiş tarihi bugün olarak kaydedilir.',
      confirmLabel: 'Tamamlandı',
    );
    if (!ok) return false;
  }
  if (!busy.begin(projectId)) return false;
  if (optimistic) onChanged(next.api);
  try {
    await repo.setStage(projectId, next);
  } catch (e) {
    busy.end(projectId);
    if (optimistic && current != null) onChanged(current.api);
    error(e);
    return false;
  }
  busy.end(projectId);
  if (!optimistic) onChanged(next.api);
  if (next != ProjectStage.tamamlandi && current != null) {
    UndoSnackbar.showOn(
      messenger,
      message: 'Aşama: ${next.label}',
      onUndo: () async {
        try {
          await repo.setStage(projectId, current);
          onChanged(current.api);
        } catch (e) {
          error(e);
        }
      },
    );
  }
  return true;
}
