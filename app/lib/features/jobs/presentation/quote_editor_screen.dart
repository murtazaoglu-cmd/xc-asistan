// SAHİBİ: jobs ajanı. Teklif düzenleme formu: kalem ekle/sil/kopyala, miktar, birim fiyat,
// KDV dahil/hariç (kalem bazlı), şablondan yükle (/quote-templates: yalnız A/M), canlı KDV'li toplam.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/jobs_access.dart';
import '../data/jobs_input.dart';
import '../data/jobs_models.dart';
import '../data/jobs_repository.dart';
import 'jobs_common.dart';
import 'resource_sections.dart';

class _Row {
  _Row({
    String desc = '',
    String qty = '1',
    String price = '',
    this.vatIncluded = false,
  }) : desc = TextEditingController(text: desc),
       qty = TextEditingController(text: qty),
       price = TextEditingController(text: price);

  factory _Row.fromItem(QuoteItem it) {
    final i = QuoteRowInput.fromItem(it);
    return _Row(
      desc: i.desc,
      qty: i.qty,
      price: i.price,
      vatIncluded: i.vatIncluded,
    );
  }

  final Key key = UniqueKey();
  final TextEditingController desc;
  final TextEditingController qty;
  final TextEditingController price;
  bool vatIncluded;

  QuoteRowInput get input => QuoteRowInput(
    desc: desc.text,
    qty: qty.text,
    price: price.text,
    vatIncluded: vatIncluded,
  );

  bool get isBlank => desc.text.trim().isEmpty && price.text.trim().isEmpty;

  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
  }
}

class QuoteEditorScreen extends ConsumerStatefulWidget {
  const QuoteEditorScreen({super.key, required this.offerId});
  final String offerId;

  @override
  ConsumerState<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends ConsumerState<QuoteEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_Row> _rows = [];
  bool _filled = false;
  bool _dirty = false;
  bool _saving = false;
  bool _showErrors = false;
  String? _error;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _fill(Offer o) {
    if (_filled) return;
    _filled = true;
    final items = o.quote?.items ?? const <QuoteItem>[];
    if (items.isEmpty) {
      _rows.add(_Row());
    } else {
      _rows.addAll(items.map(_Row.fromItem));
    }
  }

  QuoteDraft get _draft => QuoteDraft(_rows.map((r) => r.input).toList());

  void _touch() => setState(() => _dirty = true);

  void _addRow([_Row? row]) {
    if (_rows.length >= QuoteMath.maxItems) {
      showJobsInfo(context, 'En çok ${QuoteMath.maxItems} kalem eklenebilir.');
      return;
    }
    setState(() {
      _rows.add(row ?? _Row());
      _dirty = true;
    });
  }

  void _removeRow(_Row r) {
    setState(() {
      _rows.remove(r);
      _dirty = true;
    });
    r.dispose();
  }

  void _copyRow(_Row r) => _addRow(
    _Row(
      desc: r.desc.text,
      qty: r.qty.text,
      price: r.price.text,
      vatIncluded: r.vatIncluded,
    ),
  );

  Future<void> _loadTemplate() async {
    final picked = await showModalBottomSheet<QuoteTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final async = ref.watch(quoteTemplatesProvider);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
              ),
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.lg),
                  child: InlineSkeleton(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: InlineError(
                    error: e,
                    onRetry: () => ref.invalidate(quoteTemplatesProvider),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(Space.lg),
                        child: Text('Kayıtlı şablon yok.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in list)
                            ListTile(
                              minTileHeight: Sizes.minTouch,
                              title: Text(t.name),
                              subtitle: Text('${t.items.length} kalem'),
                              onTap: () => Navigator.of(ctx).pop(t),
                            ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Tek boş satır varsa şablonla değiştir; yoksa sona ekle.
      if (_rows.length == 1 && _rows.first.isBlank) {
        _rows.first.dispose();
        _rows.clear();
      }
      final room = QuoteMath.maxItems - _rows.length;
      _rows.addAll(picked.items.take(room).map(_Row.fromItem));
      _dirty = true;
    });
  }

  Future<void> _save(Glossary terms) async {
    if (_saving) return;
    setState(() {
      _showErrors = true;
      _error = null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    final draft = _draft;
    if (_rows.isEmpty) {
      setState(() => _error = 'En az bir kalem ekleyin.');
      return;
    }
    if (!formOk || !draft.allValid) {
      setState(
        () => _error =
            'Kalemleri kontrol edin: eksik ya da geçersiz alanlar var.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(jobsRepositoryProvider)
          .saveQuote(widget.offerId, draft.validItems);
      ref.invalidate(offerProvider(widget.offerId));
      if (!mounted) return;
      showJobsInfo(context, '${terms.offer} kaydedildi.');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppException.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final access = ref.watch(jobsAccessProvider);
    final async = ref.watch(offerProvider(widget.offerId));
    final totals = _draft.totals;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await ConfirmDialog.show(
          context,
          title: 'Değişiklikler kaybolsun mu?',
          message: 'Kaydedilmemiş kalemler silinecek.',
          confirmLabel: 'Vazgeç ve çık',
          cancelLabel: 'Düzenlemeye dön',
          destructive: true,
        );
        if (discard && context.mounted) context.pop();
      },
      child: AppScaffold(
        title: '${terms.offer} düzenle',
        showMenuButton: false,
        bottomBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TotalsBar(totals: totals),
            BottomSaveBar(
              saveLabel: '${terms.offer} kaydet',
              loading: _saving,
              onSave: async.hasValue ? () => _save(terms) : null,
            ),
          ],
        ),
        body: AsyncValueView<Offer>(
          value: async,
          onRetry: () => ref.invalidate(offerProvider(widget.offerId)),
          data: (o) {
            _fill(o);
            return Form(
              key: _formKey,
              autovalidateMode: _showErrors
                  ? AutovalidateMode.always
                  : AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  Text(
                    '${o.code} · ${o.name}',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: Space.md),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Card(
                          color: context.colors.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(Space.md),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: context.colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (var i = 0; i < _rows.length; i++)
                    Padding(
                      key: _rows[i].key,
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: _RowCard(
                        index: i,
                        row: _rows[i],
                        onChanged: _touch,
                        onDelete: _rows.length > 1
                            ? () => _removeRow(_rows[i])
                            : null,
                        onCopy: () => _copyRow(_rows[i]),
                      ),
                    ),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Kalem ekle'),
                      ),
                      if (access.canUseTemplates)
                        OutlinedButton.icon(
                          onPressed: _loadTemplate,
                          icon: const Icon(Icons.library_add_outlined),
                          label: const Text('Şablondan yükle'),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.xl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.index,
    required this.row,
    required this.onChanged,
    required this.onDelete,
    required this.onCopy,
  });
  final int index;
  final _Row row;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final item = row.input.toItem();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Kalem ${index + 1}',
                    style: context.text.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Kalemi kopyala',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: onCopy,
                ),
                IconButton(
                  tooltip: 'Kalemi sil',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
            TextFormField(
              controller: row.desc,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Açıklama'),
              validator: QuoteRowInput.validateDesc,
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: row.qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Adet'),
                    validator: QuoteRowInput.validateQty,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: row.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Birim fiyat',
                      prefixText: '₺ ',
                    ),
                    validator: QuoteRowInput.validatePrice,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fiyata KDV dahil'),
              subtitle: Text(
                row.vatIncluded
                    ? 'Girilen fiyatın içinde KDV var'
                    : 'KDV fiyatın üstüne eklenir',
              ),
              value: row.vatIncluded,
              onChanged: (v) {
                row.vatIncluded = v;
                onChanged();
              },
            ),
            if (item != null)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Satır (KDV dahil): ',
                        style: context.text.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    MoneyText(
                      item.lineGross,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.totals});
  final QuoteTotals totals;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('Ara toplam'), MoneyText(totals.subtotal)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('KDV (%${QuoteMath.vatPercent})'),
                MoneyText(totals.tax),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Toplam', style: context.text.titleMedium),
                MoneyText(
                  totals.total,
                  key: const ValueKey('quote-total'),
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
