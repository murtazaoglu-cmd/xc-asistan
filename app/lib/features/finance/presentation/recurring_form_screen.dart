// Sabit gider ekle / düzenle (A M O). Alanlar: kategori, tutar, kapsam, not, (düzenlemede) aktif.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/finance_errors.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import 'finance_actions.dart';
import 'form_widgets.dart';

class RecurringFormLoader extends ConsumerWidget {
  const RecurringFormLoader({
    super.key,
    required this.recurringId,
    this.initial,
  });
  final String recurringId;
  final RecurringExpense? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return RecurringFormScreen(editing: initial);
    final async = ref.watch(recurringProvider);
    return async.when(
      loading: () => const AppScaffold(
        title: 'Sabit gideri düzenle',
        body: SkeletonList(itemCount: 3),
      ),
      error: (e, _) => AppScaffold(
        title: 'Sabit gideri düzenle',
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(recurringProvider),
        ),
      ),
      data: (list) {
        final r = list.where((e) => e.id == recurringId).firstOrNull;
        if (r == null) {
          return const AppScaffold(
            title: 'Sabit gideri düzenle',
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Sabit gider bulunamadı',
            ),
          );
        }
        return RecurringFormScreen(editing: r);
      },
    );
  }
}

class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.editing});
  final RecurringExpense? editing;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<RecurringFormScreen> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _note;
  late ScopeView _scope;
  late bool _active;
  bool _saving = false;
  String? _error;

  RecurringExpense? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    _amount = TextEditingController(
      text: e == null ? '' : amountFieldText(e.amount),
    );
    _category = TextEditingController(text: e?.category ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _scope = e?.scope ?? ScopeView.business;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final input = RecurringInput(
      category: _category.text,
      amount: FinanceValidators.amount(_amount.text).value!,
      scope: _scope,
      note: _note.text,
      active: _editing == null ? null : _active,
    );
    final controller = ref.read(financeControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (_editing == null) {
        final created = await controller.addRecurring(input);
        if (!mounted) return;
        UndoSnackbar.show(
          context,
          message: '"${created.category}" sabit gider olarak eklendi',
          onUndo: () => controller
              .removeRecurring(created.id)
              .catchError((Object e) => showUndoFailure(messenger, e)),
        );
      } else {
        await controller.editRecurring(_editing!.id, input);
        if (!mounted) return;
        showFinanceMessage(messenger, 'Sabit gider güncellendi');
      }
      if (mounted) closeFinanceForm(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = FinanceErrors.message(e, FinanceOp.saveRecurring);
      });
      _scroll.animateTo(0, duration: Motion.fast, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(financeAccessProvider);
    if (access == null || !access.canManageRecurring) {
      return const AppScaffold(
        title: 'Sabit gider',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    final terms = ref.watch(brandProfileProvider).terms;
    final scopes = <ScopeView>[
      if (access.canUsePersonalScope) ScopeView.personal,
      ScopeView.business,
      ScopeView.general,
    ];
    final categories = FinanceCategories.options(
      terms,
      scope: _scope,
      hasProject: false,
    );
    final editing = _editing;
    return AppScaffold(
      title: editing == null ? 'Sabit gider ekle' : 'Sabit gideri düzenle',
      showMenuButton: false,
      bottomBar: BottomSaveBar(
        onSave: _saving ? null : _save,
        loading: _saving,
        onCancel: () => closeFinanceForm(context),
        saveLabel: editing == null ? 'Kaydet' : 'Güncelle',
      ),
      body: Form(
        key: _form,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            if (_error != null) FormErrorBanner(_error!),
            FormBlock(
              label: 'Aylık tutar',
              child: AmountField(
                controller: _amount,
                autofocus: editing == null,
              ),
            ),
            FormBlock(
              label: 'Kategori',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final c in categories)
                        ChoiceChip(
                          label: Text(FinanceCategories.label(terms, c)),
                          selected: _category.text.trim() == c,
                          onSelected: (_) => setState(() => _category.text = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    controller: _category,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 100,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: FinanceValidators.category,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Kategori (seçin ya da yazın)',
                    ),
                  ),
                ],
              ),
            ),
            FormBlock(
              label: 'Kapsam',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OptionChips<ScopeView>(
                    options: scopes,
                    value: scopes.contains(_scope) ? _scope : null,
                    labelOf: (s) => s.label,
                    iconOf: (s) => switch (s) {
                      ScopeView.personal => Icons.home_outlined,
                      ScopeView.business => Icons.storefront_outlined,
                      ScopeView.general => Icons.public,
                    },
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                  if (_scope == ScopeView.personal)
                    const InlineNotice(
                      'Ev giderleri işletme kârına dahil edilmez.',
                    ),
                ],
              ),
            ),
            FormBlock(
              label: 'Not (isteğe bağlı)',
              child: TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: FinanceValidators.note,
                decoration: const InputDecoration(
                  hintText: 'Örn. her ayın 1\'inde',
                ),
              ),
            ),
            if (editing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                subtitle: const Text(
                  'Pasif sabit gider "Bu ay uygula" ile eklenmez.',
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }
}
