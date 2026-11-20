// Yeni taksit planı sihirbazı: toplam, taksit sayısı, vade aralığı → satırlar (önizleme) → kaydet.
// Kuruş artığı SON taksite eklenir (sunucuyla aynı kural); kesin kayıt sunucuda üretilir.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_input.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import '../data/vat_calc.dart';
import 'inv_widgets.dart';

class ScheduleWizardScreen extends ConsumerStatefulWidget {
  const ScheduleWizardScreen({
    super.key,
    this.projectId,
    this.projectLabel,
    this.initialTotal,
  });
  final String? projectId;
  final String? projectLabel;
  final Money? initialTotal;

  @override
  ConsumerState<ScheduleWizardScreen> createState() =>
      _ScheduleWizardScreenState();
}

class _ScheduleWizardScreenState extends ConsumerState<ScheduleWizardScreen> {
  final _form = GlobalKey<FormState>();
  late final _total = TextEditingController(
    text: widget.initialTotal == null
        ? ''
        : widget.initialTotal!.toApiString().replaceAll('.', ','),
  );
  final _count = TextEditingController(text: '3');
  final _interval = TextEditingController(text: '30');
  late String? _projectId = widget.projectId;
  late String? _projectLabel = widget.projectLabel;
  late String _firstDue = dayKey(Ist.now().add(const Duration(days: 30)));
  ScheduleKind _kind = ScheduleKind.taksit;
  ScheduleMethod? _method = ScheduleMethod.havale;
  bool _busy = false;
  String? _error;
  String _idemKey = HttpInvoicesVatRepository.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    for (final c in [_total, _count, _interval]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _total.dispose();
    _count.dispose();
    _interval.dispose();
    super.dispose();
  }

  List<PlannedInstallment> get _plan {
    final total = Money.parseUserInput(_total.text);
    final count = int.tryParse(_count.text.trim());
    final interval = int.tryParse(_interval.text.trim());
    if (total == null || count == null || interval == null) return const [];
    return InstallmentPlanner.generate(
      total: total,
      count: count,
      firstDue: _firstDue,
      intervalDays: interval,
    );
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_projectId == null) {
      setState(() => _error = 'Plan için bir proje seçin.');
      return;
    }
    final plan = _plan;
    if (plan.isEmpty) {
      setState(() => _error = 'Plan oluşturulamadı; değerleri kontrol edin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(invoicesVatRepositoryProvider)
          .generateSchedule(
            PlanRequest(
              projectId: _projectId!,
              total: Money.parseUserInput(_total.text)!,
              count: int.parse(_count.text.trim()),
              firstDue: _firstDue,
              kind: _kind,
              intervalDays: int.parse(_interval.text.trim()),
              method: _method,
            ),
            idempotencyKey: _idemKey,
          );
      invalidateInvoicesVatW(ref);
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      _idemKey = HttpInvoicesVatRepository.newIdempotencyKey();
      setState(() {
        _busy = false;
        _error = InvoicesVatErrors.message(e, InvoicesVatOp.plan);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final total = Money.parseUserInput(_total.text);
    final count = int.tryParse(_count.text.trim());
    final hasRemainder =
        plan.length > 1 && plan.last.amount != plan.first.amount;
    return AppScaffold(
      title: 'Taksit planı oluştur',
      showMenuButton: false,
      bottomBar: BottomSaveBar(
        onSave: _save,
        loading: _busy,
        saveLabel: 'Planı kaydet',
        onCancel: () => context.canPop() ? context.pop() : null,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            RefPickerField(
              label: 'Proje',
              kind: RefKind.project,
              hasValue: _projectId != null,
              selectedLabel: _projectLabel,
              onChanged: (r) => setState(() {
                _projectId = r?.id;
                _projectLabel = r?.label;
              }),
            ),
            const SizedBox(height: Space.md),
            MoneyField(
              controller: _total,
              label: 'Toplam tutar',
              validator: (m) => InvoiceRules.planTotal(m, count),
            ),
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('plan_count'),
                    controller: _count,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Taksit sayısı',
                    ),
                    validator: (v) => InvoiceRules.installmentCount(
                      int.tryParse((v ?? '').trim()),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    key: const Key('plan_interval'),
                    controller: _interval,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Vade aralığı',
                      suffixText: 'gün',
                    ),
                    validator: (v) =>
                        InvoiceRules.interval(int.tryParse((v ?? '').trim())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final d in const [7, 15, 30, 60])
                  ActionChip(
                    label: Text('$d gün'),
                    onPressed: () => _interval.text = '$d',
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            DayField(
              label: 'İlk vade',
              value: _firstDue,
              onChanged: (v) => setState(() => _firstDue = v ?? _firstDue),
            ),
            const SizedBox(height: Space.lg),
            Text('Tür', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final k in ScheduleKind.values)
                  ChoiceChip(
                    key: Key('kind_${k.api}'),
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      if (k == ScheduleKind.cek) _method = ScheduleMethod.cek;
                      if (k == ScheduleKind.senet)
                        _method = ScheduleMethod.senet;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            Text('Yöntem', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final m in ScheduleMethod.values)
                  ChoiceChip(
                    key: Key('method_${m.api}'),
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (s) => setState(() => _method = s ? m : null),
                  ),
              ],
            ),
            if (_kind == ScheduleKind.cek ||
                _kind == ScheduleKind.senet ||
                (_method?.isInstrument ?? false))
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Çek/senet numarası ve banka bilgisini plan oluşunca satır satır ekleyebilirsiniz.',
                  style: context.text.bodySmall,
                ),
              ),
            const SizedBox(height: Space.xl),
            SectionCard(
              key: const Key('plan_preview'),
              title: 'Önizleme',
              child: plan.isEmpty
                  ? Text(
                      total == null
                          ? 'Tutarı girin.'
                          : 'Değerleri kontrol edin.',
                      style: context.text.bodyMedium,
                    )
                  : Column(
                      children: [
                        for (final p in plan)
                          KeyValueRow(
                            '${p.index}. taksit · ${DateText.format(Ist.tryParse(p.dueDate), DateTextMode.date)}',
                            p.amount.format(),
                          ),
                        const Divider(),
                        KeyValueRow(
                          'Toplam',
                          Money.sum(plan.map((p) => p.amount)).format(),
                          bold: true,
                        ),
                        if (hasRemainder)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.sm),
                            child: Text(
                              'Kuruş artığı son taksite eklendi.',
                              key: const Key('remainder_note'),
                              style: context.text.bodySmall,
                            ),
                          ),
                      ],
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('wizard_error'),
                  style: TextStyle(color: context.colors.error),
                ),
              ),
            ],
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }
}
