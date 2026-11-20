// SAHİBİ: jobs ajanı. Teklif/proje ekranlarının ortak yardımcıları.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_models.dart';
import '../data/jobs_repository.dart';

/// Hata → kısa Türkçe bildirim (sunucu ayrıntısı AppException tarafından maskelenir).
void showJobsError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(AppException.from(error).message)));
}

void showJobsInfo(BuildContext context, String message) {
  if (!context.mounted) return;
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message)));
}

/// Durum seçim alt sayfası: 6 büyük satır (tek dokunuş). Seçilen durumu döner.
Future<OfferStatus?> showOfferStatusSheet(
  BuildContext context,
  String currentStatus,
) {
  return showModalBottomSheet<OfferStatus>(
    context: context,
    showDragHandle: true,
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
                child: Text('Durumu değiştir', style: ctx.text.titleMedium),
              ),
            ),
            for (final s in OfferStatus.values)
              ListTile(
                minTileHeight: Sizes.minTouch,
                selected: s.api == currentStatus,
                leading: Icon(
                  s.api == currentStatus
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

/// Teklif durumunu değiştirir: "Kabul Edildi" öncesi onay (proje oluşur), sonrası "Geri al".
/// Başarılıysa [onApplied] yeni ham durumla çağrılır. Döner: değişti mi.
Future<bool> changeOfferStatus(
  BuildContext context,
  WidgetRef ref,
  Offer offer,
  OfferStatus next, {
  required void Function(String status) onApplied,
}) async {
  if (offer.statusEnum == next) return false;
  final terms = ref.read(brandProfileProvider).terms;
  final repo = ref.read(jobsRepositoryProvider);
  if (next == OfferStatus.kabulEdildi) {
    final amount = offer.amount;
    final ok = await ConfirmDialog.show(
      context,
      title: '${terms.offer} kabul edildi mi?',
      message: amount == null || !amount.isPositive
          ? '${terms.job} oluşturulacak ancak ${terms.offer.toLowerCase()} tutarı yok '
                '(${terms.job.toLowerCase()} 0 TL ile açılır). Önce kalem girmeniz önerilir. Devam edilsin mi?'
          : '${terms.job} oluşturulacak (${amount.format()}). Devam edilsin mi?',
      confirmLabel: 'Kabul et',
    );
    if (!ok) return false;
  }
  final previous = offer.statusEnum;
  try {
    await repo.setOfferStatus(offer.id, next);
  } catch (e) {
    if (context.mounted) showJobsError(context, e);
    return false;
  }
  onApplied(next.api);
  if (!context.mounted) return true;
  if (next == OfferStatus.kabulEdildi) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text('Kabul edildi · ${terms.job} oluşturuldu'),
        action: SnackBarAction(
          label: '${terms.job} aç',
          onPressed: () => openOfferProject(
            context,
            ref,
            offer.withStatus(OfferStatus.kabulEdildi.api),
          ),
        ),
      ),
    );
  } else if (previous != null) {
    UndoSnackbar.show(
      context,
      message: 'Durum: ${next.label}',
      onUndo: () async {
        try {
          await repo.setOfferStatus(offer.id, previous);
          onApplied(previous.api);
        } catch (e) {
          if (context.mounted) showJobsError(context, e);
        }
      },
    );
  }
  return true;
}

/// "Projeye çevir": teklifin projesi varsa ona gider, yoksa Kabul Edildi ile oluşturup açar.
Future<void> openOfferProject(
  BuildContext context,
  WidgetRef ref,
  Offer offer,
) async {
  final terms = ref.read(brandProfileProvider).terms;
  try {
    final r = await ref.read(jobsRepositoryProvider).offerToProject(offer);
    if (!context.mounted) return;
    final id = r.projectId;
    if (id != null) {
      context.push(Routes.project(id));
    } else {
      showJobsInfo(
        context,
        '${terms.job} oluşturuldu; ${terms.jobs} sekmesinden açabilirsiniz.',
      );
    }
  } catch (e) {
    showJobsError(context, e);
  }
}

/// Başlık + değer satırı (ayrıntı ekranları).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, this.value, this.child});
  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  child ??
                  Text(
                    value ?? '-',
                    textAlign: TextAlign.end,
                    style: context.text.bodyLarge,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
