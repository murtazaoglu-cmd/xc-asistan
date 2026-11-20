// Ödeme ekle / düzenle. Alanlar: proje (aramalı), tutar, yöntem, tarih, açıklama.
// Kaydet çubuğu klavye açıkken de görünür; form her zaman kaydırılabilir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/finance_calc.dart';
import '../data/finance_errors.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import 'finance_actions.dart';
import 'form_widgets.dart';
import 'owner_picker.dart';
import 'project_picker.dart';

/// Rota girişi: düzenlemede ödemeyi (extra yoksa) listeden bulur.
class PaymentFormLoader extends ConsumerWidget {
  const PaymentFormLoader({super.key, required this.paymentId, this.initial});
  final String paymentId;
  final Payment? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return PaymentFormScreen(editing: initial);
    final async = ref.watch(paymentsProvider);
    return async.when(
      loading: () => const AppScaffold(
        title: 'Ödemeyi düzenle',
        body: SkeletonList(itemCount: 4),
      ),
      error: (e, _) => AppScaffold(
        title: 'Ödemeyi düzenle',
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(paymentsProvider),
        ),
      ),
      data: (list) {
        final p = list.where((e) => e.id == paymentId).firstOrNull;
        if (p == null) {
          return const AppScaffold(
            title: 'Ödemeyi düzenle',
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Ödeme bulunamadı',
              message: 'Silinmiş olabilir.',
            ),
          );
        }
        return PaymentFormScreen(editing: p);
      },
    );
  }
}

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({super.key, this.projectId, this.editing});

  /// Önceden seçili proje (proje ekranından "Ödeme ekle").
  final String? projectId;
  final Payment? editing;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<PaymentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _method;
  late DateTime _date;
  ProjectRef? _picked;
  String? _ownerId; // null: ben
  bool _saving = false;
  String? _error;
  String? _projectError;

  Payment? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    _amount = TextEditingController(
      text: e == null ? '' : amountFieldText(e.amount),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _method = e?.method ?? PaymentMethodOption.standard.first.api;
    _ownerId = e?.ownerId;
    final d = e?.paidAt ?? Ist.now();
    final w = Ist.wall(d);
    _date = Ist.fromWall(w.year, w.month, w.day, 12);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _projectId => _editing?.projectId ?? widget.projectId;

  Money? get _parsedAmount => FinanceValidators.amount(_amount.text).value;

  /// Tutarın girilebileceği üst sınır: kalan (+ düzenlenen ödemenin kendi tutarı).
  Money? _available(ProjectRef? p) =>
      p == null ? null : p.remaining + (_editing?.amount ?? Money.zero);

  Future<void> _pickProject() async {
    final res = await showProjectPicker(context);
    if (res?.project != null) {
      setState(() {
        _picked = res!.project;
        _projectError = null;
      });
    }
  }

  void _setAmount(Money m) {
    _amount.text = amountFieldText(m);
    setState(() {});
  }

  Future<void> _save(ProjectRef? project) async {
    setState(() => _error = null);
    final formOk = _form.currentState?.validate() ?? false;
    final needsProject = _editing == null;
    if (needsProject && project == null) {
      setState(() => _projectError = 'Bir proje seçin.');
    }
    if (!formOk || (needsProject && project == null)) {
      _scroll.animateTo(0, duration: Motion.fast, curve: Curves.easeOut);
      return;
    }
    final amount = _parsedAmount!;
    final avail = _available(project);
    if (avail != null && amount > avail) {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Kalandan fazla',
        message:
            'Girilen tutar (${amount.format()}) kalan bakiyeden (${avail.format()}) fazla. Yine de kaydedilsin mi?',
        confirmLabel: 'Yine de kaydet',
      );
      if (!ok || !mounted) return;
    }
    // Düzenlemede sahip değişmediyse owner_id gönderilmez (yanlışlıkla taşıma olmasın).
    final owner = (_editing != null && _ownerId == _editing!.ownerId)
        ? null
        : _ownerId;
    final input = PaymentInput(
      amount: amount,
      method: _method,
      paidAt: _date,
      note: _note.text,
      ownerId: owner,
    );
    final controller = ref.read(financeControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (_editing == null) {
        final created = await controller.addPayment(project!, input);
        final after = project.remaining - amount;
        final left = after.isPositive
            ? ' · Kalan ${after.format(hideZeroKurus: true)}'
            : '';
        if (!mounted) return;
        UndoSnackbar.show(
          context,
          message:
              '${amount.format(hideZeroKurus: true)} tahsilat eklendi$left',
          onUndo: () => controller
              .removePayment(created.id)
              .catchError((Object e) => showUndoFailure(messenger, e)),
        );
      } else {
        final old = _editing!;
        final updated = await controller.editPayment(old, input);
        if (!mounted) return;
        UndoSnackbar.show(
          context,
          message: 'Ödeme güncellendi',
          onUndo: () => controller
              .editPayment(
                updated,
                PaymentInput(
                  amount: old.amount,
                  method: old.method,
                  paidAt: old.paidAt ?? _date,
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
        _error = FinanceErrors.message(e, FinanceOp.savePayment);
      });
      _scroll.animateTo(0, duration: Motion.fast, curve: Curves.easeOut);
    }
  }

  Future<void> _delete() async {
    final p = _editing!;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Ödeme silinsin mi?',
      message:
          '${p.amount.format()} tutarındaki ${p.projectLabel} ödemesi silinecek. Birkaç saniye içinde geri alabilirsiniz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    deletePaymentWithUndo(context, ref, p);
    closeFinanceForm(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final id = _projectId;
    final preloaded = id == null ? null : ref.watch(projectByIdProvider(id));
    final project = _picked ?? preloaded?.value;
    final editing = _editing;
    final options = _methodOptions();
    final avail = _available(project);
    final entered = _parsedAmount;
    final over = avail != null && entered != null && entered > avail;
    return AppScaffold(
      title: editing == null ? 'Ödeme ekle' : 'Ödemeyi düzenle',
      showMenuButton: false,
      actions: [
        if (editing != null)
          IconButton(
            tooltip: 'Ödemeyi sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
      ],
      bottomBar: BottomSaveBar(
        onSave: _saving ? null : () => _save(project),
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
              label: 'Proje',
              child: ProjectField(
                project: project,
                loading: preloaded?.isLoading ?? false,
                readOnlyLabel: editing?.projectLabel,
                errorText: _projectError,
                onTap: _pickProject,
              ),
            ),
            FormBlock(
              label: 'Tutar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AmountField(
                    controller: _amount,
                    autofocus: editing == null && id != null,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (avail != null && avail.isPositive) ...[
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        ActionChip(
                          label: Text(
                            'Kalanın tamamı ${avail.format(hideZeroKurus: true)}',
                          ),
                          onPressed: () => _setAmount(avail),
                        ),
                        ActionChip(
                          label: const Text('%50'),
                          onPressed: () =>
                              _setAmount(FinanceCalc.percentOf(avail, 50)),
                        ),
                        ActionChip(
                          label: const Text('%25'),
                          onPressed: () =>
                              _setAmount(FinanceCalc.percentOf(avail, 25)),
                        ),
                      ],
                    ),
                  ],
                  if (over)
                    InlineNotice(
                      'Bu tutar kalan bakiyeden (${avail.format()}) fazla. Kaydederken onay istenecek.',
                    ),
                ],
              ),
            ),
            OwnerPickerBlock(
              projectId: project?.id ?? _editing?.projectId,
              selectedId: _ownerId,
              onChanged: (v) => setState(() => _ownerId = v),
            ),
            FormBlock(
              label: 'Ödeme yöntemi',
              child: OptionChips<PaymentMethodOption>(
                options: options,
                value: options.where((o) => o.api == _method).firstOrNull,
                labelOf: (o) => o.label,
                onChanged: (o) => setState(() => _method = o.api),
              ),
            ),
            FormBlock(
              label: 'Tarih',
              child: DateChips(
                value: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
            ),
            FormBlock(
              label: 'Açıklama (isteğe bağlı)',
              child: TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: FinanceValidators.note,
                decoration: const InputDecoration(
                  hintText: 'Örn. 2. taksit ödemesi',
                ),
              ),
            ),
            // Klavye ve alt çubuk için kaydırma payı.
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }

  /// Sağlayıcıdaki seçenekler; kayıtlı (bilinmeyen) yöntem de görünür kalır.
  List<PaymentMethodOption> _methodOptions() {
    final base = ref.watch(paymentMethodOptionsProvider);
    if (base.any((o) => o.api == _method) || _method.isEmpty) return base;
    return [...base, PaymentMethodOption(_method, _method)];
  }
}
