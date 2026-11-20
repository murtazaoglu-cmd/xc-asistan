// SAHİBİ: jobs ajanı. Liste kartları (tasarım ekran 5: kod, müşteri, hizmet, tutar, durum, bekleme yaşı).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_access.dart';
import '../data/jobs_logic.dart';
import '../data/jobs_models.dart';
import '../data/jobs_project_models.dart';
import 'stage_actions.dart';

class OfferCard extends ConsumerWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.onTap,
    this.onStatusTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final Offer offer;
  final VoidCallback onTap;

  /// Uzun basınca seçim kipine girer (null: kapalı).
  final VoidCallback? onLongPress;

  /// Seçim kipi: kartın başında onay kutusu; dokunmak seçimi değiştirir ([onTap] çağıran tarafından).
  final bool selecting;
  final bool selected;

  /// Durum rozetine dokununca (alt sayfa ile hızlı değiştirme).
  final VoidCallback? onStatusTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final x = context.xc;
    final amount = offer.amount;
    final wait = waitingLabel(offer);
    final stale = isWaitingStale(offer);
    final subtitle = [
      if ((offer.service ?? '').isNotEmpty) offer.service!,
      if ((offer.region ?? '').isNotEmpty) offer.region!,
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? context.colors.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selecting)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: Semantics(
                          checked: selected,
                          label: 'Seç: ${offer.code}',
                          child: ExcludeSemantics(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: selected,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) => onTap(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.code,
                            style: context.text.labelMedium?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            offer.name,
                            style: context.text.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Flexible(
                      child: amount == null
                          ? Text(
                              '${terms.offer} yok',
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            )
                          : MoneyText(
                              amount,
                              hideZeroKurus: true,
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      button: onStatusTap != null,
                      hint: onStatusTap != null ? 'Durumu değiştir' : null,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        onTap: selecting ? null : onStatusTap,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: Sizes.minTouch,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusChip.offer(offer.status),
                              if (onStatusTap != null)
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: context.colors.onSurfaceVariant,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (offer.quote != null && offer.quote!.sendStatus != null)
                      StatusChip.send(offer.quote!.lastSendStatus),
                    if (wait != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: Sizes.iconSm - 4,
                            color: stale
                                ? x.warning
                                : context.colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: Space.xs),
                          Flexible(
                            child: Text(
                              wait,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: stale
                                    ? x.warning
                                    : context.colors.onSurfaceVariant,
                                fontWeight: stale ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectCard extends ConsumerWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    this.showMoney = true,
    this.onStageChanged,
  });

  final Project project;
  final VoidCallback onTap;

  /// Aşama değişince ham aşama adıyla (anında; hata olursa eski değerle tekrar). Null: kartta aşama
  /// düğmeleri yok. Yetki ayrıca `JobsAccess.canChangeStage` ile denetlenir (detaydakiyle aynı).
  final ValueChanged<String>? onStageChanged;

  /// Sözleşme/kalan tutarı (saha için false).
  final bool showMoney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final x = context.xc;
    final overdue = project.daysOverdue();
    final balance = project.listBalance;
    final canStage =
        onStageChanged != null && ref.watch(jobsAccessProvider).canChangeStage;
    final busy = ref.watch(stageBusyProvider).contains(project.id);
    final next = nextStageOf(project.stageEnum);
    Future<void> change(ProjectStage s) => changeProjectStage(
      context,
      ref,
      projectId: project.id,
      current: project.stageEnum,
      next: s,
      onChanged: onStageChanged!,
      optimistic: true,
    );
    final subtitle = [
      if ((project.service ?? '').isNotEmpty) project.service!,
      if ((project.address ?? '').isNotEmpty) project.address!,
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.code,
                            style: context.text.labelMedium?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            project.customerName,
                            style: context.text.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (showMoney && project.totalAmount != null) ...[
                      const SizedBox(width: Space.md),
                      MoneyText(
                        project.totalAmount!,
                        hideZeroKurus: true,
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: project.stageProgress,
                    minHeight: 6,
                    semanticsLabel: 'Aşama ilerlemesi',
                  ),
                ),
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (canStage)
                      Semantics(
                        button: true,
                        hint: 'Aşamayı değiştir',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          onTap: busy
                              ? null
                              : () async {
                                  final s = await showProjectStageSheet(
                                    context,
                                    project.stageEnum,
                                  );
                                  if (s != null) await change(s);
                                },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: Sizes.minTouch,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: StatusChip.stage(project.stage),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      StatusChip.stage(project.stage),
                    if (overdue != null)
                      StatusChip(
                        label: overdue == 0
                            ? 'Gecikti'
                            : '$overdue gün gecikti',
                        tone: StatusTone.danger,
                        icon: Icons.warning_amber,
                      ),
                    if (showMoney && balance != null && balance.isPositive)
                      Text(
                        'Kalan ${balance.format(hideZeroKurus: true)}',
                        style: context.text.bodyMedium?.copyWith(
                          color: x.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (canStage && next != null) ...[
                  const SizedBox(height: Space.sm),
                  StageNextButton(
                    next: next,
                    expand: true,
                    onPressed: busy ? null : () => change(next),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
