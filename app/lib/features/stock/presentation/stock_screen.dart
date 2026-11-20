// Stok: malzeme listesi, düşük stok vurgusu, tek dokunuşla +/- ve değer girişi, arama.
// Sektör nötr: "Stok" başlığı BrandProfile sözlüğünden.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/stock_models.dart';
import '../data/stock_repository.dart';
import '../stock_routes.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final caps = ref.watch(capabilitiesProvider);
    if (caps == null || !caps.showStock) {
      return AppScaffold(
        title: terms.stock,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
          message: 'Stoğu yalnızca yönetici, muhasebe ve iş ortağı görebilir.',
        ),
      );
    }
    ref.listen<String?>(stockMessageProvider, (_, m) {
      if (m == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      ref.read(stockMessageProvider.notifier).set(null);
    });

    final stock = ref.watch(stockListProvider);
    final query = ref.watch(stockQueryProvider);
    final onlyLow = ref.watch(stockOnlyLowProvider);

    return AppScaffold(
      title: terms.stock,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(StockRoutes.create),
        icon: const Icon(Icons.add),
        label: const Text('Malzeme ekle'),
      ),
      body: AsyncValueView<StockState>(
        value: stock,
        onRetry: () => ref.invalidate(stockListProvider),
        data: (s) {
          final shown = filterStock(s.items, query: query, onlyLow: onlyLow);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.screenH,
                  Space.md,
                  Space.screenH,
                  Space.xs,
                ),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  onChanged: (v) {
                    ref.read(stockQueryProvider.notifier).set(v);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: 'Malzeme ara',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Aramayı temizle',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              ref.read(stockQueryProvider.notifier).set('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Space.sm,
                    children: [
                      ChoiceChip(
                        label: Text('Tümü (${s.items.length})'),
                        selected: !onlyLow,
                        onSelected: (_) =>
                            ref.read(stockOnlyLowProvider.notifier).set(false),
                      ),
                      ChoiceChip(
                        avatar: Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: s.lowCount > 0 ? context.xc.warning : null,
                        ),
                        label: Text('Düşük stok (${s.lowCount})'),
                        selected: onlyLow,
                        onSelected: (_) =>
                            ref.read(stockOnlyLowProvider.notifier).set(true),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? PullToRefresh.fill(
                        onRefresh: () => ref.refresh(stockListProvider.future),
                        child: _empty(context, s, query, onlyLow),
                      )
                    : PullToRefresh(
                        onRefresh: () => ref.refresh(stockListProvider.future),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            Space.screenH,
                            Space.md,
                            Space.screenH,
                            96,
                          ),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: Space.md),
                          itemBuilder: (_, i) => StockCard(
                            item: shown[i],
                            saving: s.saving.contains(shown[i].id),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(
    BuildContext context,
    StockState s,
    String query,
    bool onlyLow,
  ) {
    if (s.items.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Henüz malzeme yok',
        message:
            'Malzeme ekleyin; miktarı tek dokunuşla artırıp azaltabilirsiniz.',
        actionLabel: 'İlk malzemeyi ekle',
        onAction: () => context.push(StockRoutes.create),
      );
    }
    if (onlyLow && query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Düşük stok yok',
        message: 'Tüm malzemelerin miktarı asgari düzeyin üstünde.',
      );
    }
    return EmptyState(
      icon: Icons.search_off,
      title: 'Sonuç bulunamadı',
      message: '"${query.trim()}" için eşleşen malzeme yok.',
    );
  }
}

/// Tek malzeme kartı: ad + durum, asgari stok, [-] değer [+].
class StockCard extends ConsumerWidget {
  const StockCard({super.key, required this.item, this.saving = false});
  final StockItem item;
  final bool saving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final it = item;
    final n = ref.read(stockListProvider.notifier);
    final x = context.xc;
    final low = it.isLow;
    final border = low
        ? BorderSide(
            color: it.isOut ? context.colors.error : x.warning,
            width: 1.5,
          )
        : BorderSide(color: context.colors.outlineVariant);
    return Semantics(
      container: true,
      label:
          '${it.name}, ${StockQty.format(it.quantity)} ${it.unit}${low ? (it.isOut ? ', tükendi' : ', düşük stok') : ''}',
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(StockRoutes.edit(it.id)),
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        it.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                    ),
                    if (saving)
                      const Padding(
                        padding: EdgeInsets.only(left: Space.sm, top: Space.xs),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                if (low) ...[
                  const SizedBox(height: Space.xs),
                  StatusChip(
                    label: it.isOut ? 'Tükendi' : 'Düşük stok',
                    tone: it.isOut ? StatusTone.danger : StatusTone.warning,
                    icon: it.isOut
                        ? Icons.remove_circle_outline
                        : Icons.warning_amber_rounded,
                  ),
                ],
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Asgari: ${StockQty.format(it.minStock)} ${it.unit}',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '${it.name} azalt',
                      onPressed: it.quantity <= 0
                          ? null
                          : () => n.adjust(it.id, -1),
                      icon: const Icon(Icons.remove),
                    ),
                    InkWell(
                      key: Key('qty-${it.id}'),
                      borderRadius: BorderRadius.circular(Radii.sm),
                      onTap: () => showQuantityDialog(context, ref, it),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 72,
                          minHeight: Sizes.minTouch,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              StockQty.format(it.quantity),
                              style: context.text.titleLarge?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: low
                                    ? (it.isOut ? context.colors.error : null)
                                    : null,
                              ),
                            ),
                            Text(it.unit, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '${it.name} artır',
                      onPressed: () => n.adjust(it.id, 1),
                      icon: const Icon(Icons.add),
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

/// Miktarı doğrudan yazma penceresi (virgüllü sayı kabul eder).
Future<void> showQuantityDialog(
  BuildContext context,
  WidgetRef ref,
  StockItem it,
) async {
  final n = ref.read(stockListProvider.notifier);
  final ctrl = TextEditingController(text: StockQty.format(it.quantity));
  final form = GlobalKey<FormState>();
  final value = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(it.name),
      content: Form(
        key: form,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Miktar (${it.unit})',
            helperText: 'Örn. 12 ya da 2,5',
          ),
          validator: (v) => StockValidators.quantity(v),
          onFieldSubmitted: (_) {
            if (form.currentState?.validate() ?? false) {
              Navigator.of(ctx).pop(StockQty.parse(ctrl.text));
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState?.validate() ?? false) {
              Navigator.of(ctx).pop(StockQty.parse(ctrl.text));
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (value != null) n.setQuantity(it.id, value, immediate: true);
}
