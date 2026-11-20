// Malzeme ekle / düzenle / sil (silme: onay + geri al).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/stock_models.dart';
import '../data/stock_repository.dart';

class StockFormScreen extends ConsumerWidget {
  const StockFormScreen({super.key, this.id});
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final title = id == null ? 'Yeni malzeme' : 'Malzemeyi düzenle';
    if (caps == null || !caps.showStock) {
      return AppScaffold(
        title: title,
        showMenuButton: false,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    if (id == null) return StockForm(title: title);
    final list = ref.watch(stockListProvider);
    return list.when(
      loading: () => AppScaffold(
        title: title,
        showMenuButton: false,
        body: const SkeletonList(itemCount: 4, itemHeight: 56),
      ),
      error: (e, _) => AppScaffold(
        title: title,
        showMenuButton: false,
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(stockListProvider),
        ),
      ),
      data: (s) {
        final it = s.items.where((e) => e.id == id).firstOrNull;
        if (it == null) {
          return AppScaffold(
            title: title,
            showMenuButton: false,
            body: const EmptyState(
              icon: Icons.search_off,
              title: 'Malzeme bulunamadı',
              message: 'Silinmiş olabilir.',
            ),
          );
        }
        return StockForm(title: title, initial: it);
      },
    );
  }
}

class StockForm extends ConsumerStatefulWidget {
  const StockForm({super.key, required this.title, this.initial});
  final String title;
  final StockItem? initial;

  @override
  ConsumerState<StockForm> createState() => _StockFormState();
}

class _StockFormState extends ConsumerState<StockForm> {
  static const _unitSuggestions = [
    'adet',
    'kg',
    'metre',
    'kutu',
    'litre',
    'paket',
  ];

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _unit = TextEditingController(
    text: widget.initial?.unit ?? 'adet',
  );
  late final _qty = TextEditingController(
    text: widget.initial == null
        ? '0'
        : StockQty.format(widget.initial!.quantity),
  );
  late final _min = TextEditingController(
    text: widget.initial == null
        ? '5'
        : StockQty.format(widget.initial!.minStock),
  );
  late final _note = TextEditingController(text: widget.initial?.note);
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    for (final c in [_name, _unit, _qty, _min, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final input = StockInput(
      name: _name.text,
      unit: _unit.text,
      quantity: StockQty.parse(_qty.text) ?? 0,
      minStock: StockQty.parse(_min.text) ?? 0,
      note: _note.text,
    );
    final repo = ref.read(stockRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await repo.update(widget.initial!.id, input);
      } else {
        await repo.create(input);
      }
      ref.invalidate(stockListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing ? 'Değişiklikler kaydedildi.' : 'Malzeme eklendi.',
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppException.from(e).message;
        });
      }
    }
  }

  Future<void> _delete() async {
    final it = widget.initial!;
    final container = ProviderScope.containerOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final ok = await ConfirmDialog.show(
      context,
      title: '${it.name} silinsin mi?',
      message:
          'Malzeme kaydı kaldırılır. Birkaç saniye içinde geri alabilirsiniz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final n = container.read(stockListProvider.notifier);
    final repo = container.read(stockRepositoryProvider);
    final removed = n.removeLocal(it.id);
    UndoSnackbar.deferred(
      context,
      message: '${it.name} silindi',
      onUndo: () {
        if (removed != null) n.restore(removed);
      },
      onCommit: () async {
        try {
          await repo.delete(it.id);
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(AppException.from(e).message)),
          );
        }
        container.invalidate(stockListProvider);
      },
    );
    if (router.canPop()) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.title,
      showMenuButton: false,
      actions: [
        if (_editing)
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
      ],
      bottomBar: BottomSaveBar(
        onSave: _save,
        loading: _saving,
        saveLabel: _editing ? 'Kaydet' : 'Malzeme ekle',
        onCancel: () => context.pop(),
      ),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: context.colors.errorContainer,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.colors.onErrorContainer),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              key: const Key('field-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Malzeme adı *'),
              validator: StockValidators.name,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              key: const Key('field-unit'),
              controller: _unit,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Birim'),
              validator: StockValidators.unit,
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final u in _unitSuggestions)
                  ActionChip(
                    label: Text(u),
                    onPressed: () => setState(() => _unit.text = u),
                  ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('field-qty'),
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Mevcut miktar',
                    ),
                    validator: (v) => StockValidators.quantity(v),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    key: const Key('field-min'),
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Asgari stok',
                      helperText: 'Bu miktara inince uyarılır',
                      helperMaxLines: 2,
                    ),
                    validator: (v) =>
                        StockValidators.quantity(v, field: 'Asgari stok'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Not'),
              validator: StockValidators.note,
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }
}
