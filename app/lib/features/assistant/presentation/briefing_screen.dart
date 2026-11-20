// Brifing ekranları: bugünün brifingi, geçmiş listesi (sabah / haftalık / aylık / akşam), ayrıntı.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/access.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../data/assistant_repository.dart';
import '../data/briefing_models.dart';
import 'widgets/assistant_ui.dart';
import 'widgets/briefing_views.dart';

/// Bir brifingin gövdesi (türüne göre); açılınca okundu işaretler.
class _BriefingView extends ConsumerStatefulWidget {
  const _BriefingView({required this.briefing, this.onRead});
  final Briefing briefing;
  final VoidCallback? onRead;
  @override
  ConsumerState<_BriefingView> createState() => _BriefingViewState();
}

class _BriefingViewState extends ConsumerState<_BriefingView> {
  late Briefing _b = widget.briefing;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    if (!_b.isRead && _b.id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _mark(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant _BriefingView old) {
    super.didUpdateWidget(old);
    if (old.briefing.id != widget.briefing.id ||
        old.briefing.readAt != widget.briefing.readAt) {
      _b = widget.briefing;
    }
  }

  Future<void> _mark({bool silent = false}) async {
    if (_marking || _b.id.isEmpty) return;
    _marking = true;
    try {
      await ref.read(assistantRepositoryProvider).markBriefingRead(_b.id);
      if (mounted)
        setState(() => _b = _b.copyWith(readAt: DateTime.now().toUtc()));
      widget.onRead?.call();
    } on Object catch (e) {
      if (mounted && !silent) toast(context, errorText(e));
    } finally {
      _marking = false;
    }
  }

  @override
  Widget build(BuildContext context) => _b.kind.isReport
      ? ReportBody(briefing: _b, onMarkRead: _mark)
      : BriefingBody(briefing: _b, onMarkRead: _mark);
}

/// Bugünün sabah brifingi.
class BriefingScreen extends ConsumerWidget {
  const BriefingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(briefingTodayProvider);
    Future<void> refresh() async {
      ref.invalidate(briefingTodayProvider);
      try {
        await ref.read(briefingTodayProvider.future);
      } on Object {
        // Hata ekranı gösterilir.
      }
    }

    return AppScaffold(
      title: 'Brifing',
      showMenuButton: false,
      actions: [
        IconButton(
          tooltip: 'Geçmiş brifingler',
          icon: const Icon(Icons.history),
          onPressed: () => context.push(AssistantPaths.briefingHistory),
        ),
      ],
      body: PullToRefresh(
        onRefresh: refresh,
        child: async.when(
          loading: () => const SkeletonList(itemCount: 5, itemHeight: 110),
          error: (e, _) => FillRefresh(
            onRefresh: refresh,
            child: ErrorState(
              error: e,
              onRetry: () => ref.invalidate(briefingTodayProvider),
            ),
          ),
          data: (b) => _BriefingView(
            briefing: b,
            onRead: () => ref.invalidate(briefingHistoryProvider),
          ),
        ),
      ),
    );
  }
}

/// Geçmiş brifing/rapor listesi. `?type=weekly|monthly|morning|evening`.
class BriefingHistoryScreen extends ConsumerStatefulWidget {
  const BriefingHistoryScreen({super.key, this.initialType});
  final String? initialType;
  @override
  ConsumerState<BriefingHistoryScreen> createState() =>
      _BriefingHistoryScreenState();
}

class _BriefingHistoryScreenState extends ConsumerState<BriefingHistoryScreen> {
  late String? _type = widget.initialType;

  static const _types = <(String?, String)>[
    (null, 'Tümü'),
    ('morning', 'Sabah'),
    ('weekly', 'Haftalık'),
    ('monthly', 'Aylık'),
    ('evening', 'Gün sonu'),
  ];

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(assistantAccessProvider);
    final types = [
      for (final t in _types)
        if (access.showManager || (t.$1 != 'weekly' && t.$1 != 'monthly')) t,
    ];
    final async = ref.watch(briefingHistoryProvider(_type));
    Future<void> refresh() async {
      ref.invalidate(briefingHistoryProvider(_type));
      try {
        await ref.read(briefingHistoryProvider(_type).future);
      } on Object {
        // Hata ekranı gösterilir.
      }
    }

    return AppScaffold(
      title: 'Brifing geçmişi',
      showMenuButton: false,
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              children: [
                for (final t in types)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() => _type = t.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PullToRefresh(
              onRefresh: refresh,
              child: async.when(
                loading: () => const SkeletonList(itemHeight: 64),
                error: (e, _) => FillRefresh(
                  onRefresh: refresh,
                  child: ErrorState(
                    error: e,
                    onRetry: () =>
                        ref.invalidate(briefingHistoryProvider(_type)),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? FillRefresh(
                        onRefresh: refresh,
                        child: const EmptyState(
                          icon: Icons.history,
                          title: 'Henüz brifing yok',
                          message: 'Brifingler her sabah ve (yöneticiler için) hafta/ay başında oluşur.',
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Space.lg),
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Space.sm),
                        itemBuilder: (context, i) =>
                            _HistoryTile(briefing: list[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.briefing});
  final Briefing briefing;

  @override
  Widget build(BuildContext context) {
    final b = briefing;
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      onTap: () => context.push(AssistantPaths.briefingView, extra: b),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.kind.label,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
                Text(
                  b.title,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: b.isRead ? FontWeight.w400 : FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(b.date, style: context.text.bodySmall),
              ],
            ),
          ),
          if (!b.isRead)
            Semantics(
              label: 'Okunmadı',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Geçmişten seçilen tek brifing/rapor (GoRouter `extra`).
class BriefingDetailScreen extends ConsumerWidget {
  const BriefingDetailScreen({super.key, required this.briefing});
  final Briefing? briefing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = briefing;
    return AppScaffold(
      title: b?.kind.label ?? 'Brifing',
      showMenuButton: false,
      body: b == null
          ? EmptyState(
              icon: Icons.history,
              title: 'Brifing bulunamadı',
              actionLabel: 'Geçmişe dön',
              onAction: () => context.go(AssistantPaths.briefingHistory),
            )
          : _BriefingView(
              briefing: b,
              onRead: () => ref.invalidate(briefingHistoryProvider),
            ),
    );
  }
}

@visibleForTesting
Briefing? debugBriefing(Object? extra) => extra is Briefing ? extra : null;
