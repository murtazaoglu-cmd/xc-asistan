// Gider ekle / düzenle. Kategori (marka sözlüğü + serbest metin), kapsam (Ev / Dükkan / İşletme),
// isteğe bağlı proje, tutar, tarih, not. Personel proje bağsız (genel) gider giremez.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../data/finance_access.dart';
import '../data/finance_errors.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import 'finance_actions.dart';
import 'form_widgets.dart';
import 'owner_picker.dart';
import 'project_picker.dart';

class ExpenseFormLoader extends ConsumerWidget {
  const ExpenseFormLoader({super.key, required this.expenseId, this.initial});
  final String expenseId;
  final Expense? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return ExpenseFormScreen(editing: initial);
    final async = ref.watch(expensesProvider);
    return async.when(
      loading: () => const AppScaffold(
        title: 'Gideri düzenle',
        body: SkeletonList(itemCount: 4),
      ),
      error: (e, _) => AppScaffold(
        title: 'Gideri düzenle',
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(expensesProvider),
        ),
      ),
      data: (list) {
        final x = list.where((e) => e.id == expenseId).firstOrNull;
        if (x == null) {
          return const AppScaffold(
            title: 'Gideri düzenle',
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Gider bulunamadı',
              message: 'Silinmiş olabilir.',
            ),
          );
        }
        return ExpenseFormScreen(editing: x);
      },
    );
  }
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.projectId, this.editing});

  /// Önceden bağlı proje (proje ekranından "Gider ekle"); null → genel gider.
  final String? projectId;
  final Expense? editing;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _note;
  late ScopeView _scope;
  late DateTime _date;
  ProjectRef? _picked;
  bool _projectCleared = false;
  String? _ownerId; // null: ben
  bool _saving = false;
  String? _error;
  String? _projectError;

  Expense? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    _amount = TextEditingController(
      text: e == null ? '' : amountFieldText(e.amount),
    );
    _category = TextEditingController(text: e?.category ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _scope = e?.scope ?? ScopeView.general;
    _ownerId = e?.ownerId;
    final w = Ist.wall(e?.date ?? Ist.now());
    _date = Ist.fromWall(w.year, w.month, w.day, 12);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  ProjectRef? _project(AsyncValue<ProjectRef>? preloaded) {
    if (_projectCleared) return null;
    return _picked ?? preloaded?.value;
  }

  Future<void> _pickProject(FinanceAccess access) async {
    final res = await showProjectPicker(
      context,
      allowNone: access.canAddGeneralExpense,
    );
    if (res == null) return;
    setState(() {
      _picked = res.project;
      _projectCleared = res.project == null;
      _projectError = null;
      // Projeye bağlı gider kişisel olamaz.
      if (res.project != null && _scope == ScopeView.personal) {
        _scope = ScopeView.general;
      }
    });
  }

  Future<void> _save(ProjectRef? project, FinanceAccess access) async {
    setState(() => _error = null);
    final formOk = _form.currentState?.validate() ?? false;
    final isNew = _editing == null;
    final hasProject = isNew ? project != null : _editing!.hasProject;
    String? projectError;
    if (!hasProject && !access.canAddGeneralExpense) {
      projectError = FinanceErrors.generalExpenseForbidden;
    }
    if (projectError != null) {
      // Hem üstteki şeritte (görünür) hem proje alanında göster.
      setState(() {
        _projectError = projectError;
        _error = projectError;
      });
    }
    if (!formOk || projectError != null) {
      _scroll.animateTo(0, duration: Motion.fast, curve: Curves.easeOut);
      return;
    }
    final input = ExpenseInput(
      category: _category.text,
      amount: FinanceValidators.amount(_amount.text).value!,
      scope: _scope,
      date: _date,
      projectId: project?.id,
      note: _note.text,
      ownerId: (!isNew && _ownerId == _editing!.ownerId) ? null : _ownerId,
    );
    final controller = ref.read(financeControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (isNew) {
        final created = await controller.addExpense(input, project: project);
        if (!mounted) return;
        UndoSnackbar.show(
          context,
          message:
              '${input.amount.format(hideZeroKurus: true)} gider eklendi (${_scope.label})',
          onUndo: () => controller
              .removeExpense(created.id)
              .catchError((Object e) => showUndoFailure(messenger, e)),
        );
      } else {
        final old = _editing!;
        final updated = await controller.editExpense(old, input);
        if (!mounted) return;
        UndoSnackbar.show(
          context,
          message: 'Gider güncellendi',
          onUndo: () => controller
              .editExpense(
                updated,
                ExpenseInput(
                  category: old.category,
                  amount: old.amount,
                  scope: old.scope,
                  date: old.date ?? _date,
                  note: old.note,
                ),
              )
              .then((_) {})
              .catchError((Object e) => showUndoFailure(messenger, e)),
        );
      }
      if (mounted) closeFinanceForm(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = FinanceErrors.message(
          e,
          FinanceOp.saveExpense,
          hasProject: hasProject,
        );
      });
      _scroll.animateTo(0, duration: Motion.fast, curve: Curves.easeOut);
    }
  }

  Future<void> _delete() async {
    final x = _editing!;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Gider silinsin mi?',
      message:
          '${x.amount.format()} tutarındaki "${x.category}" gideri silinecek. Birkaç saniye içinde geri alabilirsiniz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    deleteExpenseWithUndo(context, ref, x);
    closeFinanceForm(context, true);
  }

  List<String> _recentCategories() {
    final list = ref.watch(expensesProvider).value ?? const <Expense>[];
    final sorted = [
      ...list,
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    return [for (final e in sorted) e.category];
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(financeAccessProvider);
    if (access == null || !access.canView) {
      return const AppScaffold(
        title: 'Gider',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    final terms = ref.watch(brandProfileProvider).terms;
    final editing = _editing;
    final id = editing == null ? widget.projectId : null;
    final preloaded = id == null ? null : ref.watch(projectByIdProvider(id));
    final project = _project(preloaded);
    final hasProject = editing != null ? editing.hasProject : project != null;
    final scopes = <ScopeView>[
      if (access.canUsePersonalScope && !hasProject) ScopeView.personal,
      ScopeView.business,
      ScopeView.general,
    ];
    final categories = FinanceCategories.options(
      terms,
      scope: _scope,
      hasProject: hasProject,
      recent: _recentCategories(),
    );
    return AppScaffold(
      title: editing == null ? 'Gider ekle' : 'Gideri düzenle',
      showMenuButton: false,
      actions: [
        if (editing != null)
          IconButton(
            tooltip: 'Gideri sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
      ],
      bottomBar: BottomSaveBar(
        onSave: _saving ? null : () => _save(project, access),
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
              label: 'Tutar',
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
                    textInputAction: TextInputAction.next,
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
                      'Ev giderleri işletme kârına dahil edilmez; özet ekranında ayrı gösterilir.',
                    ),
                ],
              ),
            ),
            FormBlock(
              label: editing == null ? 'Proje (isteğe bağlı)' : 'Proje',
              child: ProjectField(
                project: project,
                placeholder: access.canAddGeneralExpense
                    ? 'Projeye bağlı değil'
                    : 'Proje seçin (zorunlu)',
                loading: preloaded?.isLoading ?? false,
                readOnlyLabel: editing == null
                    ? null
                    : (editing.hasProject
                          ? editing.projectLabel
                          : 'Projeye bağlı değil'),
                errorText: _projectError,
                onTap: () => _pickProject(access),
                onClear: access.canAddGeneralExpense && editing == null
                    ? () => setState(() {
                        _picked = null;
                        _projectCleared = true;
                      })
                    : null,
              ),
            ),
            OwnerPickerBlock(
              projectId: editing != null ? editing.projectId : project?.id,
              selectedId: _ownerId,
              onChanged: (v) => setState(() => _ownerId = v),
            ),
            FormBlock(
              label: 'Tarih',
              child: DateChips(
                value: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
            ),
            FormBlock(
              label: 'Not (isteğe bağlı)',
              child: TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: FinanceValidators.note,
                decoration: const InputDecoration(
                  hintText: 'Örn. fiş no, tedarikçi',
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }
}
