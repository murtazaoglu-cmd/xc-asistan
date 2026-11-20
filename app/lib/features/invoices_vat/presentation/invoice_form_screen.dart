// Fatura ekle / düzenle. Uygulama fatura KESMEZ: kesilmiş/alınmış belgeyi KAYDEDER.
// Toplamlar sunucuda hesaplanır; alttaki önizleme kuruş tamsayısıyla cihazda yapılır.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_input.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import '../data/invoices_vat_services.dart';
import '../data/vat_calc.dart';
import 'inv_widgets.dart';

class InvoiceFormScreen extends ConsumerStatefulWidget {
  /// [invoiceId] doluysa düzenleme; boşsa yeni kayıt.
  const InvoiceFormScreen({super.key, this.invoiceId});
  final String? invoiceId;

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _form = GlobalKey<FormState>();
  final _no = TextEditingController();
  final _ettn = TextEditingController();
  final _party = TextEditingController();
  final _taxId = TextEditingController();
  final _amount = TextEditingController();
  final _docKdv = TextEditingController();
  final _note = TextEditingController();
  final _exemption = TextEditingController();
  final _customPay = TextEditingController();
  final _customPayda = TextEditingController();

  InvoiceDirection _direction = InvoiceDirection.giden;
  InvoiceType _type = InvoiceType.eArsiv;
  AmountBasis _basis = AmountBasis.exclusive;
  InvoiceStatus _status = InvoiceStatus.kesildi;
  String _issue = dayKey(Ist.now());
  String? _due;
  num? _rate;
  bool _rateTouched = false;
  String? _withholdingId; // null: yok, 'custom': elle
  bool _deductible = true;
  String? _projectId;
  String? _projectLabel;
  final List<PickedAttachment> _pending = [];

  Invoice? _loaded;
  bool _initDone = false;
  bool _saving = false;
  String? _error;
  String _idemKey = HttpInvoicesVatRepository.newIdempotencyKey();

  bool get _isEdit => widget.invoiceId != null;

  @override
  void initState() {
    super.initState();
    if (!_isEdit) _initDone = true;
    for (final c in [_amount, _docKdv, _customPay, _customPayda, _taxId]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _no,
      _ettn,
      _party,
      _taxId,
      _amount,
      _docKdv,
      _note,
      _exemption,
      _customPay,
      _customPayda,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Invoice i) {
    _loaded = i;
    _direction = i.direction ?? InvoiceDirection.giden;
    _type = i.type ?? InvoiceType.diger;
    _status = i.status ?? InvoiceStatus.kesildi;
    _no.text = i.invoiceNo ?? '';
    _ettn.text = i.ettn ?? '';
    _party.text = i.counterparty ?? '';
    _taxId.text = i.counterpartyTaxId ?? '';
    _basis = AmountBasis.exclusive;
    _amount.text = _plain(i.matrah);
    _rate = i.kdvOran;
    _rateTouched = true;
    _issue = i.issueDate == null ? _issue : dayKey(i.issueDate!);
    _due = i.dueDate == null ? null : dayKey(i.dueDate!);
    _note.text = i.note ?? '';
    _deductible = i.kdvDeductible;
    _exemption.text = i.kdvExemptionReason ?? '';
    _projectId = i.projectId;
    _projectLabel = [
      i.projectCode,
      i.customerName,
    ].whereType<String>().join(' · ');
    if (_projectLabel!.isEmpty)
      _projectLabel = i.projectId == null ? null : 'Bağlı proje';
    if (i.withholding != null) {
      _withholdingId = 'custom';
      _customPay.text = '${i.withholding!.pay}';
      _customPayda.text = '${i.withholding!.payda}';
    }
  }

  static String _plain(Money m) => m.toApiString().replaceAll('.', ',');

  Withholding? _withholding(VatRates? rates) {
    if (_withholdingId == null) return null;
    if (_withholdingId == 'custom') {
      final p = int.tryParse(_customPay.text.trim());
      final d = int.tryParse(_customPayda.text.trim());
      return (p == null || d == null) ? null : Withholding(p, d);
    }
    final t = rates?.withholdingTypes
        .where((e) => e.id == _withholdingId)
        .firstOrNull;
    return t?.ratio;
  }

  num? _effectiveRate(VatRates? rates) => _rate ?? rates?.defaultRate?.percent;

  VatPreview? _preview(VatRates? rates) {
    final amt = Money.parseUserInput(_amount.text);
    final r = _effectiveRate(rates);
    if (amt == null || !amt.isPositive || r == null) return null;
    final w = _withholding(rates);
    return _basis == AmountBasis.exclusive
        ? VatCalc.fromMatrah(amt, r, withholding: w)
        : VatCalc.fromGross(amt, r, withholding: w);
  }

  Future<bool> _attachGuard(PickedAttachment? a) async {
    if (a == null) return false;
    if (!isAllowedAttachmentName(a.name)) {
      _snack('Bu dosya türü eklenemez (PDF ya da fotoğraf seçin).');
      return false;
    }
    if (_pending.length >= attachmentMaxCount) {
      _snack('En çok $attachmentMaxCount dosya eklenebilir.');
      return false;
    }
    final len = await attachmentSizeOf(a.path);
    if (len != null && len > attachmentMaxBytes) {
      _snack('Dosya çok büyük (en çok 15 MB).');
      return false;
    }
    return true;
  }

  Future<void> _addAttachment(
    Future<PickedAttachment?> Function(AttachmentPicker) pick,
  ) async {
    try {
      final a = await pick(ref.read(attachmentPickerProvider));
      if (await _attachGuard(a)) setState(() => _pending.add(a!));
    } catch (_) {
      _snack('Dosya seçilemedi. İzinleri kontrol edin.');
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  InvoiceInput? _build(VatRates? rates, {bool accept = false}) {
    final amt = Money.parseUserInput(_amount.text);
    if (amt == null) return null;
    final docKdv = _docKdv.text.trim().isEmpty
        ? null
        : Money.parseUserInput(_docKdv.text);
    return InvoiceInput(
      direction: _direction,
      issueDate: _issue,
      amount: amt,
      basis: _basis,
      invoiceType: _type,
      invoiceNo: _no.text,
      ettn: _ettn.text,
      counterparty: _party.text,
      counterpartyTaxId: _taxId.text,
      kdvOran: _effectiveRate(rates),
      documentKdv: docKdv,
      withholding: _withholding(rates),
      kdvExemptionReason: _effectiveRate(rates) == 0 ? _exemption.text : null,
      kdvDeductible: _direction == InvoiceDirection.gelen ? _deductible : null,
      status: _status,
      dueDate: _due,
      projectId: _projectId,
      note: _note.text,
      customerId: _loaded?.customerId,
      acceptMismatch: accept,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final rates = ref.read(vatRatesProvider).asData?.value;
    if (!(_form.currentState?.validate() ?? false)) return;
    final due = InvoiceRules.dueAfterIssue(_issue, _due);
    if (due != null) {
      setState(() => _error = due);
      return;
    }
    final wErr = _withholdingId == 'custom'
        ? InvoiceRules.withholding(
            int.tryParse(_customPay.text),
            int.tryParse(_customPayda.text),
          )
        : null;
    if (wErr != null) {
      setState(() => _error = wErr);
      return;
    }
    var input = _build(rates);
    if (input == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(invoicesVatRepositoryProvider);
    try {
      Invoice saved;
      try {
        saved = await _write(repo, input);
      } catch (e) {
        final mm = KdvMismatch.of(e);
        if (mm == null || !mounted) rethrow;
        final go = await ConfirmDialog.show(
          context,
          title: 'KDV tutarı uyuşmuyor',
          message:
              'Belgedeki KDV hesaplanandan farklı${mm.expected == null ? '' : ' (beklenen ${mm.expected!.format()})'}. '
              'Belgeyi kontrol edin; yine de belgedeki değerle kaydedilsin mi?',
          confirmLabel: 'Yine de kaydet',
        );
        if (!go) {
          setState(() => _saving = false);
          return;
        }
        _idemKey = HttpInvoicesVatRepository.newIdempotencyKey();
        input = input.copyWith(acceptMismatch: true);
        saved = await _write(repo, input);
      }
      var failed = 0;
      for (final a in _pending) {
        try {
          await repo.uploadInvoiceFile(saved.id, a.path, fileName: a.name);
        } catch (_) {
          failed++;
        }
      }
      invalidateInvoicesVatW(ref);
      if (!mounted) return;
      if (failed > 0) {
        _snack(
          'Fatura kaydedildi; $failed ek yüklenemedi. Fatura sayfasından tekrar ekleyin.',
        );
      }
      if (context.canPop()) {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      if (!(e is AppException && e.isNetwork)) {
        _idemKey = HttpInvoicesVatRepository.newIdempotencyKey();
      }
      setState(() {
        _saving = false;
        _error = InvoicesVatErrors.message(e, InvoicesVatOp.save);
      });
    }
  }

  Future<Invoice> _write(InvoicesVatRepository repo, InvoiceInput input) =>
      _isEdit
      ? repo.updateInvoice(widget.invoiceId!, input)
      : repo.createInvoice(input, idempotencyKey: _idemKey);

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_initDone) {
      final async = ref.watch(invoiceDetailProvider(widget.invoiceId!));
      return AppScaffold(
        title: 'Faturayı düzenle',
        showMenuButton: false,
        body: AsyncValueView<Invoice>(
          value: async,
          onRetry: () =>
              ref.invalidate(invoiceDetailProvider(widget.invoiceId!)),
          data: (i) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _initDone) return;
              setState(() {
                _fill(i);
                _initDone = true;
              });
            });
            return const SkeletonList(itemCount: 4, itemHeight: 64);
          },
        ),
      );
    }

    final ratesAsync = ref.watch(vatRatesProvider);
    final rates = ratesAsync.asData?.value;
    final preview = _preview(rates);

    return AppScaffold(
      title: _isEdit ? 'Faturayı düzenle' : 'Fatura ekle',
      showMenuButton: false,
      bottomBar: BottomSaveBar(
        onSave: _save,
        loading: _saving,
        onCancel: () => context.canPop() ? context.pop() : null,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const DisclaimerNote(
              'Uygulama fatura KESMEZ; kestiğiniz veya aldığınız belgeyi takip için kaydedersiniz.',
            ),
            const SizedBox(height: Space.lg),
            Text('Yön', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            SegmentedButton<InvoiceDirection>(
              key: const Key('direction_select'),
              segments: [
                for (final d in InvoiceDirection.values)
                  ButtonSegment(
                    value: d,
                    label: Text(d.label),
                    tooltip: d.hint,
                    icon: Icon(
                      d == InvoiceDirection.giden
                          ? Icons.north_east
                          : Icons.south_west,
                    ),
                  ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, Sizes.minTouch)),
              ),
            ),
            const SizedBox(height: Space.lg),
            DropdownButtonFormField<InvoiceType>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Belge türü'),
              items: [
                for (final t in InvoiceType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _no,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Belge no'),
              validator: InvoiceRules.invoiceNo,
            ),
            const SizedBox(height: Space.md),
            DayField(
              label: 'Fatura tarihi',
              value: _issue,
              onChanged: (v) => setState(() => _issue = v ?? _issue),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _party,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _direction == InvoiceDirection.giden
                    ? 'Müşteri / alıcı unvanı'
                    : 'Satıcı / tedarikçi unvanı',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: InvoiceRules.counterparty,
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _taxId,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: InputDecoration(
                labelText: 'VKN / TCKN (isteğe bağlı)',
                helperText: InvoiceRules.taxIdWarning(_taxId.text),
                helperMaxLines: 2,
                helperStyle: TextStyle(color: context.xc.warning),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: InvoiceRules.taxId,
            ),
            const SizedBox(height: Space.xl),
            Text('Tutar', style: context.text.titleMedium),
            const SizedBox(height: Space.sm),
            SegmentedButton<AmountBasis>(
              key: const Key('basis_select'),
              segments: const [
                ButtonSegment(
                  value: AmountBasis.exclusive,
                  label: Text('KDV hariç'),
                ),
                ButtonSegment(
                  value: AmountBasis.inclusive,
                  label: Text('KDV dahil'),
                ),
              ],
              selected: {_basis},
              onSelectionChanged: (s) => setState(() => _basis = s.first),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, Sizes.minTouch)),
              ),
            ),
            const SizedBox(height: Space.md),
            MoneyField(
              controller: _amount,
              label: _basis == AmountBasis.exclusive
                  ? 'Matrah (KDV hariç)'
                  : 'Toplam (KDV dahil)',
            ),
            const SizedBox(height: Space.md),
            _RateSelector(
              rates: ratesAsync,
              selected: _effectiveRate(rates),
              onSelected: (v) => setState(() {
                _rate = v;
                _rateTouched = true;
              }),
              onRetry: () => ref.invalidate(vatRatesProvider),
              touched: _rateTouched,
            ),
            if (_effectiveRate(rates) == 0) ...[
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _exemption,
                decoration: const InputDecoration(
                  labelText: 'KDV istisna nedeni',
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            _WithholdingSelector(
              rates: rates,
              selectedId: _withholdingId,
              pay: _customPay,
              payda: _customPayda,
              onChanged: (v) => setState(() => _withholdingId = v),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _docKdv,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Belgedeki KDV (isteğe bağlı)',
                prefixText: '₺ ',
                helperText: 'Girerseniz hesaplananla karşılaştırılır.',
              ),
            ),
            if (_direction == InvoiceDirection.gelen)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('KDV indirilebilir'),
                subtitle: const Text(
                  'İşletmeyle ilgili ve belgeli alımlar. Emin değilseniz mali müşavire sorun.',
                ),
                value: _deductible,
                onChanged: (v) => setState(() => _deductible = v),
              ),
            const SizedBox(height: Space.md),
            if (preview != null)
              _PreviewCard(
                preview: preview,
                docKdv: Money.parseUserInput(_docKdv.text),
              ),
            const SizedBox(height: Space.xl),
            Text('Durum ve vade', style: context.text.titleMedium),
            const SizedBox(height: Space.sm),
            DropdownButtonFormField<InvoiceStatus>(
              isExpanded: true,
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Durum'),
              items: [
                for (final s in InvoiceStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: Space.md),
            DayField(
              label: 'Vade tarihi (isteğe bağlı)',
              value: _due,
              allowClear: true,
              onChanged: (v) => setState(() => _due = v),
              errorText: InvoiceRules.dueAfterIssue(_issue, _due),
            ),
            const SizedBox(height: Space.md),
            RefPickerField(
              label: 'Bağlı proje',
              kind: RefKind.project,
              hasValue: _projectId != null,
              selectedLabel: _projectLabel,
              onChanged: (r) => setState(() {
                _projectId = r?.id;
                _projectLabel = r?.label;
              }),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _note,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Not'),
              validator: InvoiceRules.note,
            ),
            const SizedBox(height: Space.lg),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Ek bilgiler (ETTN)'),
              children: [
                TextFormField(
                  controller: _ettn,
                  decoration: const InputDecoration(labelText: 'ETTN'),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            _AttachmentsPending(
              files: _pending,
              onCamera: () => _addAttachment((p) => p.takePhoto()),
              onGallery: () => _addAttachment((p) => p.pickPhoto()),
              onFile: () => _addAttachment((p) => p.pickFile()),
              onRemove: (a) => setState(() => _pending.remove(a)),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.lg),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('form_error'),
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, this.docKdv});
  final VatPreview preview;
  final Money? docKdv;

  @override
  Widget build(BuildContext context) {
    final mismatch =
        docKdv != null && !VatCalc.kdvMatches(docKdv!, preview.kdv);
    return SectionCard(
      key: const Key('vat_preview'),
      title: 'Önizleme (tahmini)',
      child: Column(
        children: [
          KeyValueRow('Matrah', preview.matrah.format()),
          KeyValueRow('KDV', preview.kdv.format()),
          if (!preview.tevkifat.isZero)
            KeyValueRow('Tevkifat', '−${preview.tevkifat.format()}'),
          KeyValueRow('Genel toplam', preview.tutar.format(), bold: true),
          if (!preview.tevkifat.isZero)
            KeyValueRow('Ödenecek', preview.odenecek.format(), bold: true),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Belgedeki KDV (${docKdv!.format()}) hesaplanandan farklı.',
                key: const Key('mismatch_note'),
                style: context.text.bodySmall?.copyWith(
                  color: context.xc.warning,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'Kesin hesap sunucudadır; bu yalnızca önizlemedir.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateSelector extends StatelessWidget {
  const _RateSelector({
    required this.rates,
    required this.selected,
    required this.onSelected,
    required this.onRetry,
    required this.touched,
  });
  final AsyncValue<VatRates> rates;
  final num? selected;
  final ValueChanged<num> onSelected;
  final VoidCallback onRetry;
  final bool touched;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('KDV oranı', style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        rates.when(
          loading: () => const SkeletonBox(height: 40),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Oran listesi alınamadı. Oranı elle girin ve mali müşavire teyit edin.',
                style: context.text.bodySmall,
              ),
              TextFormField(
                key: const Key('manual_rate'),
                initialValue: selected?.toString(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'KDV oranı (%)',
                  suffixText: '%',
                ),
                onChanged: (v) {
                  final n = num.tryParse(v.replaceAll(',', '.'));
                  if (n != null) onSelected(n);
                },
              ),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Listeyi yenile'),
              ),
            ],
          ),
          data: (v) {
            if (v.rates.isEmpty) {
              return Text(
                'Tanımlı KDV oranı yok. Ayarlardan oran ekleyin.',
                style: context.text.bodySmall,
              );
            }
            final current = v.rates
                .where((r) => r.percent == selected)
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final r in v.rates)
                      ChoiceChip(
                        key: Key('rate_${formatPercent(r.percent)}'),
                        avatar: r.confirmation.needed
                            ? Icon(
                                Icons.fact_check_outlined,
                                size: Sizes.iconSm,
                                color: context.xc.warning,
                              )
                            : null,
                        label: Text(r.percentLabel),
                        selected: r.percent == selected,
                        onSelected: (_) => onSelected(r.percent),
                      ),
                  ],
                ),
                if (current != null && current.confirmation.needed)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: ConfirmBadge(current.confirmation),
                  ),
                if (v.disclaimer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(v.disclaimer!, style: context.text.bodySmall),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WithholdingSelector extends StatelessWidget {
  const _WithholdingSelector({
    required this.rates,
    required this.selectedId,
    required this.pay,
    required this.payda,
    required this.onChanged,
  });
  final VatRates? rates;
  final String? selectedId;
  final TextEditingController pay;
  final TextEditingController payda;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final types = rates?.withholdingTypes ?? const <WithholdingType>[];
    final selected = types.where((t) => t.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          key: const Key('withholding_select'),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Tevkifat (isteğe bağlı)',
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Yok')),
            for (final t in types)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(
                  t.confirmation.needed ? '${t.label} (teyit edin)' : t.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem<String?>(
              value: 'custom',
              child: Text('Elle gir (pay/payda)'),
            ),
          ],
          onChanged: onChanged,
        ),
        if (selected != null && selected.confirmation.needed)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: ConfirmBadge(selected.confirmation),
          ),
        if (selectedId == 'custom') ...[
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: pay,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Pay'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Space.sm),
                child: Text('/'),
              ),
              Expanded(
                child: TextFormField(
                  controller: payda,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Payda'),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: Space.xs),
            child: ConfirmBadge(
              Confirmation(
                needed: true,
                reasons: ['Elle girilen tevkifat oranı doğrulanmadı.'],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AttachmentsPending extends StatelessWidget {
  const _AttachmentsPending({
    required this.files,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onRemove,
  });
  final List<PickedAttachment> files;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final ValueChanged<PickedAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Ekler (fotoğraf / PDF)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlinedButton.icon(
                key: const Key('attach_camera'),
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Kamera'),
              ),
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeri'),
              ),
              OutlinedButton.icon(
                onPressed: onFile,
                icon: const Icon(Icons.attach_file),
                label: const Text('Dosya'),
              ),
            ],
          ),
          for (final a in files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: Space.sm,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Kaydedilince yüklenir'),
              trailing: IconButton(
                tooltip: 'Kaldır',
                icon: const Icon(Icons.close),
                onPressed: () => onRemove(a),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'PDF, JPG, PNG, WEBP, HEIC · en çok 15 MB · en çok $attachmentMaxCount dosya.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
