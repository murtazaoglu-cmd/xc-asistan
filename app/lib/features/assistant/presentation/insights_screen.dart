// Müdür ekranı: öneri listesi + (yalnız admin) kural açma/kapama ve eşik düzenleme.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/access.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../data/insight_models.dart';
import 'widgets/assistant_ui.dart';
import 'widgets/insight_card.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  static const _filters = <(String, String)>[
    ('acik', 'Açık'),
    ('ertelendi', 'Ertelenen'),
    ('kapatildi', 'Kapatılan'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(assistantAccessProvider);
    if (!access.showManager) {
      return const AppScaffold(
        title: 'Müdür',
        showMenuButton: false,
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm sizin için kapalı',
          message: 'Müdür önerileri yalnız yönetici, muhasebe ve iş ortakları içindir.',
        ),
      );
    }
    final status = ref.watch(insightStatusFilterProvider);
    final async = ref.watch(insightsProvider);
    Future<void> refresh() =>
        ref.read(insightsProvider.notifier).refreshFromServer();

    return AppScaffold(
      title: 'Müdür',
      showMenuButton: false,
      actions: [
        if (access.canEditRules)
          IconButton(
            tooltip: 'Kurallar',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push(AssistantPaths.insightRules),
          ),
      ],
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
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: status == f.$1,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => ref
                          .read(insightStatusFilterProvider.notifier)
                          .set(f.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PullToRefresh(
              onRefresh: refresh,
              child: async.when(
                loading: () => const SkeletonList(itemHeight: 140),
                error: (e, _) => FillRefresh(
                  onRefresh: refresh,
                  child: ErrorState(
                    error: e,
                    onRetry: () => ref.invalidate(insightsProvider),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? FillRefresh(
                        onRefresh: refresh,
                        child: EmptyState(
                          icon: Icons.check_circle_outline,
                          title: status == 'acik'
                              ? 'Şu an öneri yok'
                              : 'Kayıt yok',
                          message: status == 'acik'
                              ? 'İşler yolunda görünüyor. Yeni bir durum oluşursa burada ve brifingde göreceksiniz.'
                              : null,
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Space.lg),
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Space.md),
                        itemBuilder: (context, i) => InsightCardView(
                          key: ValueKey(list[i].id),
                          insight: list[i],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yalnız admin: kural aç/kapat ve eşik düzenleme. Bağımlılığı karşılanmayan kurallar GÖSTERİLMEZ.
class InsightRulesScreen extends ConsumerWidget {
  const InsightRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(assistantAccessProvider);
    if (!access.canEditRules) {
      return const AppScaffold(
        title: 'Müdür kuralları',
        showMenuButton: false,
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Yetkiniz yok',
          message: 'Kuralları yalnız yönetici değiştirebilir.',
        ),
      );
    }
    final async = ref.watch(insightRulesProvider);
    Future<void> refresh() async {
      ref.invalidate(insightRulesProvider);
      try {
        await ref.read(insightRulesProvider.future);
      } on Object {
        // Hata ekranı gösterilir.
      }
    }

    return AppScaffold(
      title: 'Müdür kuralları',
      showMenuButton: false,
      body: PullToRefresh(
        onRefresh: refresh,
        child: async.when(
          loading: () => const SkeletonList(itemHeight: 72),
          error: (e, _) => FillRefresh(
            onRefresh: refresh,
            child: ErrorState(
              error: e,
              onRetry: () => ref.invalidate(insightRulesProvider),
            ),
          ),
          data: (cfg) {
            final rules = cfg.visible;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Space.lg),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kalibrasyon modu'),
                  subtitle: const Text(
                    'Açıkken öneriler yalnız bilgi amaçlı gösterilir; kırmızı uyarı çıkmaz.',
                  ),
                  value: cfg.calibrationMode,
                  onChanged: (v) => _guard(
                    context,
                    () => ref
                        .read(insightRulesProvider.notifier)
                        .setCalibration(v),
                  ),
                ),
                const Divider(),
                if (rules.isEmpty)
                  const EmptyState(title: 'Kural yok', icon: Icons.rule)
                else
                  for (final r in rules) _RuleTile(rule: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } on Object catch (e) {
    if (context.mounted) toast(context, errorText(e));
  }
}

class _RuleTile extends ConsumerStatefulWidget {
  const _RuleTile({required this.rule});
  final InsightRule rule;
  @override
  ConsumerState<_RuleTile> createState() => _RuleTileState();
}

class _RuleTileState extends ConsumerState<_RuleTile> {
  bool _open = false;
  bool _saving = false;
  late final Map<String, TextEditingController> _ctrls = {
    for (final e in widget.rule.params.entries)
      e.key: TextEditingController(text: '${e.value}'),
  };
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final out = <String, int>{};
    for (final e in _ctrls.entries) {
      final n = int.tryParse(e.value.text.trim());
      if (n == null || n < 0 || n > 1000000000) {
        setState(
          () =>
              _error = 'Değerler 0 ile 1.000.000.000 arasında tam sayı olmalı.',
        );
        return;
      }
      out[e.key] = n;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await _guard(
      context,
      () => ref
          .read(insightRulesProvider.notifier)
          .setParams(widget.rule.key, out),
    );
    if (mounted) setState(() => _saving = false);
  }

  static String _label(String k) {
    final s = k.replaceAll('_', ' ');
    return s.isEmpty ? k : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: Space.sm,
          title: Text(r.title),
          subtitle: Text(r.description),
          onTap: r.params.isEmpty ? null : () => setState(() => _open = !_open),
          trailing: Switch(
            value: r.enabled,
            onChanged: (v) => _guard(
              context,
              () =>
                  ref.read(insightRulesProvider.notifier).setEnabled(r.key, v),
            ),
          ),
        ),
        if (_open && r.params.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Eşikler (para değerleri kuruş, oranlar baz puan olarak girilir).',
                  style: context.text.bodySmall,
                ),
                for (final e in _ctrls.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: TextField(
                      controller: e.value,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _label(e.key),
                        helperText: r.defaults[e.key] == null
                            ? null
                            : 'Varsayılan: ${r.defaults[e.key]}',
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                  ),
                const SizedBox(height: Space.sm),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Eşikleri kaydet'),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
