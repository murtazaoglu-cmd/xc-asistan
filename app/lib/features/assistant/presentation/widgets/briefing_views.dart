// Brifing gövdesi: "Asistan Özeti" mor kartı, 4'lü sayı kutuları, bloklar; haftalık/aylık müdür raporu.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/brand_profile.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/util/money.dart';
import '../../application/access.dart';
import '../../application/assistant_routes_paths.dart';
import '../../data/briefing_models.dart';
import '../../data/insight_models.dart';
import 'assistant_ui.dart';
import 'briefing_blocks.dart';

/// "Bugün N randevu var" gibi madde metinleri (rol süzgeçli; sektör sözlüğüyle).
List<String> briefingBullets(Briefing b, AssistantAccess a, Glossary terms) {
  if (b.isEmptyDay) return [b.text.split('\n').first];
  final s = b.stats;
  return [
    if (s.appointments > 0)
      'Bugün ${s.appointments} ${trLower(terms.appointment)} var.',
    if (a.showFinance && s.lateCollections > 0)
      '${s.lateCollections} tahsilat bekliyor.',
    if (a.showSales && s.newRequests > 0)
      '${s.newRequests} yeni ${trLower(terms.offer)} talebi yanıt bekliyor.',
    if (s.overdueJobs > 0) '${s.overdueJobs} ${trLower(terms.job)} gecikti.',
    if (s.followups > 0) '${s.followups} takip var.',
    if (a.showSales && s.lowStock > 0) '${s.lowStock} kalem düşük stokta.',
  ];
}

/// 4'lü sayı kutuları; rol kısıtlıysa yalnız izinli kutular.
class BriefingStatRow extends StatelessWidget {
  const BriefingStatRow({
    super.key,
    required this.briefing,
    required this.access,
  });
  final Briefing briefing;
  final AssistantAccess access;

  @override
  Widget build(BuildContext context) {
    final s = briefing.stats;
    final terms = context.terms;
    final x = context.xc;
    final tiles = <Widget>[
      StatTile(
        label: terms.appointment,
        value: '${s.appointments}',
        icon: Icons.event_outlined,
        onTap: () => goTo(context, Routes.appointments),
      ),
      if (access.showFinance)
        StatTile(
          label: 'Tahsilat',
          value: '${s.lateCollections}',
          icon: Icons.payments_outlined,
          color: x.success,
          onTap: () => goTo(context, Routes.finance),
        ),
      if (access.showSales)
        StatTile(
          label: terms.offer,
          value: '${s.newRequests}',
          icon: Icons.request_quote_outlined,
          color: x.warning,
          onTap: () => goTo(context, Routes.jobs),
        ),
      StatTile(
        label: 'Geciken iş',
        value: '${s.overdueJobs}',
        icon: Icons.error_outline,
        color: context.colors.error,
        onTap: access.isField ? null : () => goTo(context, Routes.jobs),
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.sm),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// Bugünün brifingi: özet kartı + sayılar + bloklar + okundu.
class BriefingBody extends ConsumerWidget {
  const BriefingBody({super.key, required this.briefing, this.onMarkRead});
  final Briefing briefing;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(assistantAccessProvider);
    final terms = context.terms;
    final blocks = visibleBlocks(briefing, access);
    final bullets = briefingBullets(briefing, access, terms);
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        AiCard(
          kind: AiCardKind.summary,
          title: briefing.title.isEmpty ? 'Günaydın' : briefing.title,
          body: bullets.isEmpty ? null : bullets.map((e) => '• $e').join('\n'),
          child: briefing.holiday != null
              ? Text(
                  'Resmî tatil: ${briefing.holiday}',
                  style: context.text.bodySmall,
                )
              : (briefing.dayKind == 'pazar'
                    ? Text(
                        'Pazar: dinlenme günü.',
                        style: context.text.bodySmall,
                      )
                    : null),
        ),
        const SizedBox(height: Space.md),
        BriefingStatRow(briefing: briefing, access: access),
        const SizedBox(height: Space.lg),
        for (final b in blocks) BriefingBlockView(block: b),
        if (access.showManager)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      goTo(context, AssistantPaths.reports('weekly')),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Haftalık rapor'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      goTo(context, AssistantPaths.reports('monthly')),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Aylık rapor'),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            if (briefing.isRead)
              Row(
                children: [
                  Icon(
                    Icons.done_all,
                    size: Sizes.iconSm,
                    color: context.xc.success,
                  ),
                  const SizedBox(width: Space.xs),
                  Text('Okundu', style: context.text.bodySmall),
                ],
              )
            else if (onMarkRead != null)
              TextButton.icon(
                onPressed: onMarkRead,
                icon: const Icon(Icons.done),
                label: const Text('Okundu işaretle'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Haftalık/aylık müdür raporu: gelir / gider / kâr, tahsilat, teklif hattı, en çok 3 öneri.
class ReportBody extends ConsumerWidget {
  const ReportBody({super.key, required this.briefing, this.onMarkRead});
  final Briefing briefing;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = briefing.report;
    final terms = context.terms;
    if (r == null) return const SizedBox.shrink();
    final m = r.money;
    final change = m.netChange;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text(
          r.periodLabel.isEmpty
              ? briefing.kind.label
              : '${briefing.kind.label}: ${r.periodLabel}',
          style: context.text.titleLarge,
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: _MoneyTile(
                label: 'Gelir',
                amount: m.collected,
                color: context.xc.success,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _MoneyTile(
                label: 'Gider',
                amount: m.expense,
                color: context.colors.error,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _MoneyTile(
                label: 'Kâr',
                amount: m.net,
                color: context.colors.primary,
              ),
            ),
          ],
        ),
        if (change != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'Önceki döneme göre ${change.isNegative ? 'azalış' : 'artış'}: ${change.abs().format()}',
              style: context.text.bodyMedium,
            ),
          ),
        if (m.note != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(m.note!, style: context.text.bodySmall),
          ),
        SectionLabel('Tahsilat'),
        SectionCard(
          onTap: () => goTo(context, Routes.finance),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  r.lateCount > 0
                      ? '${r.lateCount} geciken tahsilat'
                      : 'Geciken tahsilat yok',
                  style: context.text.bodyLarge,
                ),
              ),
              if (r.lateCount > 0)
                MoneyText(r.lateTotal, style: context.text.titleMedium),
            ],
          ),
        ),
        SectionLabel('${terms.offer} hattı'),
        SectionCard(
          child: Wrap(
            spacing: Space.xl,
            runSpacing: Space.sm,
            children: [
              _Stat('Yeni', r.offers.created),
              _Stat('Teklif verilen', r.offers.quoted),
              _Stat('Kabul', r.offers.accepted),
              _Stat('Red', r.offers.rejected),
              if (r.offers.conversionBp != null)
                _StatText('Dönüşüm', formatBp(r.offers.conversionBp!)),
            ],
          ),
        ),
        SectionLabel(
          'Bu dönemin ${r.topActions.length > 1 ? '${r.topActions.length} önerisi' : 'önerisi'}',
        ),
        if (r.topActions.isEmpty)
          Text('Bu dönem için öneri yok.', style: context.text.bodyMedium)
        else
          for (final t in r.topActions) _TipTile(insight: t),
        if (ref.watch(assistantAccessProvider).showManager)
          TextButton(
            onPressed: () => goTo(context, AssistantPaths.insights),
            child: const Text('Tüm müdür önerileri'),
          ),
        if (!briefing.isRead && onMarkRead != null)
          TextButton.icon(
            onPressed: onMarkRead,
            icon: const Icon(Icons.done),
            label: const Text('Okundu işaretle'),
          ),
      ],
    );
  }
}

class _MoneyTile extends StatelessWidget {
  const _MoneyTile({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final Money amount;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: ${amount.format()}',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: Space.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount,
              hideZeroKurus: true,
              style: context.text.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => _StatText(label, '$value');
}

class _StatText extends StatelessWidget {
  const _StatText(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: context.text.titleMedium),
      Text(label, style: context.text.bodySmall),
    ],
  );
}

class _TipTile extends StatefulWidget {
  const _TipTile({required this.insight});
  final Insight insight;
  @override
  State<_TipTile> createState() => _TipTileState();
}

class _TipTileState extends State<_TipTile> {
  bool _why = false;
  @override
  Widget build(BuildContext context) {
    final i = widget.insight;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: AiCard(
        kind: AiCardKind.managerTip,
        title: i.title,
        body: i.body.isEmpty ? null : i.body,
        onWhy: i.evidence.metrics.isEmpty
            ? null
            : () => setState(() => _why = !_why),
        child: _why
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in i.evidence.metrics)
                    Text(
                      '${m.label}: ${m.display}',
                      style: context.text.bodySmall,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
