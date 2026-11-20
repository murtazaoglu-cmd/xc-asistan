// Brifing blokları: randevular, hatırlatmalar, dikkat, yeni talepler, geciken işler, tahsilat,
// düşük stok, para özeti, tek soru, dünün kapanışı. Bilinmeyen blok türü çizilmez.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/util/json.dart';
import '../../../../core/util/money.dart';
import '../../application/assistant_routes_paths.dart';
import '../../data/assistant_repository.dart';
import '../../data/briefing_models.dart';
import '../../data/model_utils.dart';
import 'assistant_ui.dart';

class BriefingBlockView extends ConsumerWidget {
  const BriefingBlockView({super.key, required this.block});
  final BriefingBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (block.type) {
      case 'appointments':
        return _Appointments(block: block);
      case 'reminders':
        return _Reminders(block: block);
      case 'attention':
        return _Attention(block: block);
      case 'new_requests':
        return _NewRequests(block: block);
      case 'overdue_jobs':
        return _OverdueJobs(block: block);
      case 'collections':
        return _Collections(block: block);
      case 'low_stock':
        return _LowStock(block: block);
      case 'money':
        return _MoneyBlock(block: block);
      case 'question':
        return _QuestionBlock(block: block);
      case 'missed_closure':
        return _MissedClosure(block: block);
    }
    return const SizedBox.shrink();
  }
}

Widget _titled(
  BuildContext context,
  BriefingBlock b,
  List<Widget> children, {
  String? trailing,
  VoidCallback? onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: SectionCard(
      title: b.title,
      onTap: onTap,
      trailing: trailing == null
          ? (b.count > 0 ? _CountBadge(b.count) : null)
          : Text(trailing, style: context.text.labelLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.sm,
      vertical: Space.xs,
    ),
    decoration: BoxDecoration(
      color: context.colors.primaryContainer,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      '$count',
      style: context.text.labelMedium?.copyWith(
        color: context.colors.onPrimaryContainer,
      ),
    ),
  );
}

/// Ara / WhatsApp / Yol tarifi düğmeleri (sunucunun `actions` haritasından).
class ContactActionsRow extends ConsumerWidget {
  const ContactActionsRow({super.key, required this.actions});
  final JsonMap? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = actions;
    if (a == null) return const SizedBox.shrink();
    final call = a.strOrNull('call');
    final wa = a.strOrNull('whatsapp');
    final dir = a.strOrNull('directions');
    if (call == null && wa == null && dir == null)
      return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call != null)
          IconButton(
            tooltip: 'Ara',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => openExternalLink(ref, context, call),
          ),
        if (wa != null)
          IconButton(
            tooltip: 'WhatsApp',
            icon: const Icon(Icons.chat_outlined),
            onPressed: () => openExternalLink(ref, context, wa),
          ),
        if (dir != null)
          IconButton(
            tooltip: 'Yol tarifi',
            icon: const Icon(Icons.directions_outlined),
            onPressed: () => openExternalLink(ref, context, dir),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.main, this.sub, this.trailing, this.onTap});
  final String main;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(main, style: context.text.bodyLarge),
                if (sub != null) Text(sub!, style: context.text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    return onTap == null
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.minTouch),
            child: body,
          )
        : InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouch),
              child: body,
            ),
          );
  }
}

class _Appointments extends StatelessWidget {
  const _Appointments({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    final items = block.items;
    return _titled(context, block, [
      if (items.isEmpty)
        Text('Bugün kayıtlı randevu yok.', style: context.text.bodyMedium),
      for (final it in items)
        _Row(
          main:
              it.strOrNull('summary') ??
              '${it.strOr('time')} ${it.strOr('customer_name')}'.trim(),
          sub:
              [
                it.strOrNull('service'),
                it.strOrNull('address'),
              ].whereType<String>().join(' · ').trim().isEmpty
              ? null
              : [
                  it.strOrNull('service'),
                  it.strOrNull('address'),
                ].whereType<String>().join(' · '),
          trailing: ContactActionsRow(actions: it.mapOrNull('actions')),
        ),
    ]);
  }
}

class _Reminders extends StatelessWidget {
  const _Reminders({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    final rem = block.raw.list('reminders');
    final fol = block.raw.list('followups');
    final quotes = block.raw.list('quote_waiting');
    return _titled(context, block, [
      for (final r in rem)
        _Row(
          main: '${r.strOr('time')} ${r.strOr('title')}'.trim(),
          sub: r.boolOr('overdue') ? 'Gecikti' : null,
          trailing: r.boolOr('overdue')
              ? Icon(
                  Icons.schedule,
                  color: context.colors.error,
                  semanticLabel: 'Gecikti',
                )
              : null,
        ),
      for (final f in fol)
        _Row(
          main: f.strOrNull('title') ?? f.strOr('customer_name'),
          sub: 'Takip',
        ),
      for (final q in quotes)
        _Row(
          main: q.strOr('customer_name'),
          sub: 'Teklif ${q.intOr('age_days')} gündür yanıt bekliyor',
        ),
      if (rem.isEmpty && fol.isEmpty && quotes.isEmpty)
        Text('Bugün için hatırlatma yok.', style: context.text.bodyMedium),
    ]);
  }
}

class _Attention extends StatelessWidget {
  const _Attention({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    return _titled(context, block, [
      for (final it in block.items)
        Builder(
          builder: (context) {
            final sev = it.strOr('severity');
            final screen =
                (it['actions'] is List && (it['actions'] as List).isNotEmpty)
                ? asJsonMap((it['actions'] as List).first).strOrNull('screen')
                : null;
            final route =
                routeForScreen(screen) ??
                (it.strOrNull('insight_id') != null
                    ? AssistantPaths.insights
                    : null);
            return _Row(
              main: it.strOr('title'),
              sub: it.strOrNull('text'),
              trailing: sev == 'critical'
                  ? Icon(
                      Icons.priority_high,
                      color: context.colors.error,
                      semanticLabel: 'Kritik',
                    )
                  : Icon(
                      Icons.warning_amber_rounded,
                      color: context.xc.warning,
                      semanticLabel: 'Uyarı',
                    ),
              onTap: route == null ? null : () => goTo(context, route),
            );
          },
        ),
    ]);
  }
}

class _NewRequests extends StatelessWidget {
  const _NewRequests({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    final age = block.raw.intOrNull('oldest_age_hours');
    return _titled(context, block, [
      if (age != null && age >= 24)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: Text(
            'En eskisi $age saattir bekliyor.',
            style: context.text.bodySmall,
          ),
        ),
      for (final it in block.items)
        _Row(
          main: it.strOrNull('summary') ?? it.strOr('customer_name'),
          trailing: ContactActionsRow(actions: it.mapOrNull('actions')),
        ),
    ], onTap: () => goTo(context, Routes.jobs));
  }
}

class _OverdueJobs extends StatelessWidget {
  const _OverdueJobs({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) => _titled(context, block, [
    for (final it in block.items)
      _Row(
        main: '${it.strOr('code')} ${it.strOr('customer_name')}'.trim(),
        sub: '${it.intOr('days_overdue')} gün gecikti',
        onTap: it.strOrNull('id') == null
            ? null
            : () => goTo(context, Routes.project(it.strOr('id'))),
      ),
  ]);
}

class _Collections extends StatelessWidget {
  const _Collections({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    final total = kurusOrNull(block.raw, 'total_kurus');
    return _titled(context, block, [
      for (final it in block.items)
        _Row(
          main: it.strOr('customer_name'),
          sub: '${it.intOr('age_days')} gündür açık',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyText(
                kurus(it, 'balance_kurus'),
                style: context.text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              ContactActionsRow(actions: it.mapOrNull('actions')),
            ],
          ),
          onTap: it.strOrNull('project_id') == null
              ? null
              : () => goTo(context, Routes.project(it.strOr('project_id'))),
        ),
    ], trailing: total?.format());
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) => _titled(context, block, [
    for (final it in block.items)
      _Row(
        main: it.strOr('name'),
        sub:
            'Stok ${it.str('stock') ?? '-'} ${it.strOr('unit')} (eşik ${it.str('threshold') ?? '-'})',
      ),
  ], onTap: () => goTo(context, Routes.stock));
}

class _MoneyBlock extends StatelessWidget {
  const _MoneyBlock({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) {
    final month = block.raw.mapOrNull('month');
    final y = block.raw.mapOrNull('yesterday');
    return _titled(context, block, [
      if (block.raw.strOrNull('text') != null)
        Text(block.raw.strOr('text'), style: context.text.bodyMedium),
      if (y != null) ...[
        const SizedBox(height: Space.sm),
        _MoneyLine('Dün tahsilat', kurus(y, 'collected_kurus')),
        _MoneyLine('Dün gider', kurus(y, 'expense_kurus')),
      ],
      if (month != null) ...[
        _MoneyLine('Bu ay net', kurus(month, 'net_kurus'), strong: true),
      ],
    ]);
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine(this.label, this.amount, {this.strong = false});
  final String label;
  final Money amount;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.text.bodyMedium)),
        MoneyText(
          amount,
          colorizeNegative: true,
          style: context.text.bodyLarge?.copyWith(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _QuestionBlock extends ConsumerStatefulWidget {
  const _QuestionBlock({required this.block});
  final BriefingBlock block;
  @override
  ConsumerState<_QuestionBlock> createState() => _QuestionBlockState();
}

class _QuestionBlockState extends ConsumerState<_QuestionBlock> {
  bool _done = false;
  bool _busy = false;

  Future<void> _apply(JsonMap chip) async {
    final raw = widget.block.raw;
    final value = chip['value'];
    if (value == null) {
      setState(() => _done = true); // "Sonra": yalnız gizle
      return;
    }
    final apply = raw.mapOrNull('apply');
    final projectId = raw.strOrNull('project_id');
    if (apply == null || projectId == null) return;
    final path = apply.strOr('path').replaceAll('<id>', projectId);
    final field = apply.strOr('body_field');
    if (field.isEmpty || hasPlaceholder(path)) return;
    setState(() => _busy = true);
    try {
      await ref.read(assistantRepositoryProvider).callApply(
        apply.strOr('method', 'PATCH'),
        path,
        {field: value},
      );
      if (mounted) {
        setState(() => _done = true);
        toast(context, 'Kaydedildi.');
      }
    } on Object catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    final raw = widget.block.raw;
    return _titled(context, widget.block, [
      Text(raw.strOr('text'), style: context.text.bodyLarge),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final c in raw.list('chips'))
            ActionChip(
              label: Text(c.strOr('label')),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onPressed: _busy ? null : () => _apply(c),
            ),
        ],
      ),
    ]);
  }
}

class _MissedClosure extends StatelessWidget {
  const _MissedClosure({required this.block});
  final BriefingBlock block;
  @override
  Widget build(BuildContext context) => _titled(context, block, [
    Text(block.raw.strOr('text'), style: context.text.bodyMedium),
    const SizedBox(height: Space.sm),
    OutlinedButton(
      onPressed: () => goTo(context, AssistantPaths.closure),
      child: const Text('Kapanışa git'),
    ),
  ]);
}
