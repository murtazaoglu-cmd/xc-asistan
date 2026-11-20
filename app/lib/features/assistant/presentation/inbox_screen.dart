// Bildirim kutusu: liste + okundu/ack + rozet sayısı. Üst çubuk zil ikonu için `InboxBellButton`
// (bkz. docs/ARCHITECTURE.md §13: AppBar.actions içine konur).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../data/inbox_models.dart';
import 'widgets/assistant_ui.dart';

/// Bildirimin dokununca açacağı rota (bilinmiyorsa null: kutuda kalır).
String? routeForInboxItem(InboxItem i) {
  final d = i.data;
  switch (i.type) {
    case 'briefing':
      final k = d['kind']?.toString();
      return (k == 'weekly' || k == 'monthly')
          ? AssistantPaths.reports(k!)
          : AssistantPaths.briefing;
    case 'closure':
      return AssistantPaths.closure;
    case 'offer':
      return routeForEntity('offer', d['id']?.toString()) ?? Routes.jobs;
    case 'reminder':
      final kind = d['kind']?.toString();
      return (kind != null && kind.startsWith('appointment'))
          ? Routes.appointments
          : Routes.today;
    case 'tax_reminder':
      return Routes.invoicesVat;
    case 'receivable_reminder':
      return Routes.finance;
    case 'insight':
      return AssistantPaths.insights;
  }
  return null;
}

IconData inboxIcon(String type) => switch (type) {
  'briefing' => Icons.wb_sunny_outlined,
  'closure' => Icons.nightlight_outlined,
  'offer' => Icons.request_quote_outlined,
  'reminder' => Icons.alarm,
  'tax_reminder' => Icons.account_balance_outlined,
  'receivable_reminder' => Icons.payments_outlined,
  'insight' => Icons.insights,
  _ => Icons.notifications_none,
};

/// Üst çubuk zil ikonu + okunmamış rozeti.
class InboxBellButton extends ConsumerWidget {
  const InboxBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(inboxUnreadCountProvider).value ?? 0;
    return IconButton(
      tooltip: n > 0 ? 'Bildirimler, $n okunmamış' : 'Bildirimler',
      onPressed: () => context.push(AssistantPaths.inbox),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inboxProvider);
    final unreadOnly = ref.watch(inboxUnreadOnlyProvider);
    Future<void> refresh() async {
      ref.invalidate(inboxProvider);
      ref.invalidate(inboxUnreadCountProvider);
      try {
        await ref.read(inboxProvider.future);
      } on Object {
        // Hata ekranı gösterilir.
      }
    }

    return AppScaffold(
      title: 'Bildirimler',
      showMenuButton: false,
      actions: [
        IconButton(
          tooltip: 'Tümünü okundu yap',
          icon: const Icon(Icons.done_all),
          onPressed: (async.value?.unreadCount ?? 0) == 0
              ? null
              : () async {
                  try {
                    await ref.read(inboxProvider.notifier).markAllRead();
                  } on Object catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                  }
                },
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tümü'),
                  selected: !unreadOnly,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) =>
                      ref.read(inboxUnreadOnlyProvider.notifier).set(false),
                ),
                const SizedBox(width: Space.sm),
                ChoiceChip(
                  label: const Text('Okunmamış'),
                  selected: unreadOnly,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) =>
                      ref.read(inboxUnreadOnlyProvider.notifier).set(true),
                ),
              ],
            ),
          ),
          Expanded(
            child: PullToRefresh(
              onRefresh: refresh,
              child: async.when(
                loading: () => const SkeletonList(itemHeight: 72),
                error: (e, _) => FillRefresh(
                  onRefresh: refresh,
                  child: ErrorState(
                    error: e,
                    onRetry: () => ref.invalidate(inboxProvider),
                  ),
                ),
                data: (s) => s.items.isEmpty
                    ? FillRefresh(
                        onRefresh: refresh,
                        child: EmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: unreadOnly
                              ? 'Okunmamış bildirim yok'
                              : 'Bildirim yok',
                          message: 'Brifing, hatırlatma ve yeni talepler burada birikir.',
                        ),
                      )
                    : _InboxList(state: s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxList extends ConsumerWidget {
  const _InboxList({required this.state});
  final InboxState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
          ref.read(inboxProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, i) {
          if (i >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final it = state.items[i];
          return _InboxTile(item: it);
        },
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !item.isRead;
    final when = item.availableAt ?? item.createdAt;
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      onTap: () async {
        final route = routeForInboxItem(item);
        await ref.read(inboxProvider.notifier).open(item);
        if (route != null && context.mounted) context.push(route);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            inboxIcon(item.type),
            color: unread ? context.colors.primary : context.colors.outline,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (item.body.isNotEmpty)
                  Text(item.body, style: context.text.bodyMedium),
                if (when != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      Fmt.relativeDateTime(when),
                      style: context.text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (unread)
            Semantics(
              label: 'Okunmadı',
              child: Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: Space.xs),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
