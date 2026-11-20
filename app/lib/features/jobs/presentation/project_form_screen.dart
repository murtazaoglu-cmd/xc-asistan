// SAHİBİ: jobs ajanı. Yeni (elle) proje: POST /projects {customer_name*, service*, total_amount, stage, address}.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/money.dart';
import '../../customers/customers_public.dart';
import '../data/jobs_project_models.dart';
import '../data/jobs_repository.dart';

class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key});

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _service = TextEditingController();
  final _amount = TextEditingController();
  final _address = TextEditingController();
  ProjectStage _stage = ProjectStage.malzemeTemini;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_customer, _service, _amount, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "Mevcut müşteriden seç": müşteri adı (+ adres varsa) doldurulur; elle yazılan adres boşla ezilmez.
  Future<void> _pickCustomer() async {
    final c = await showCustomerPicker(context);
    if (c == null || !mounted) return;
    setState(() {
      _customer.text = c.name;
      if ((c.address ?? '').isNotEmpty) _address.text = c.address!;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = ProjectDraft(
      customerName: _customer.text,
      service: _service.text,
      totalAmount: Money.parseUserInput(_amount.text) ?? Money.zero,
      stage: _stage,
      address: _address.text,
    );
    setState(() => _saving = true);
    try {
      final p = await ref.read(jobsRepositoryProvider).createProject(draft);
      if (!mounted) return;
      setState(() => _dirty = false);
      context.pushReplacement(Routes.project(p.id));
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
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await ConfirmDialog.show(
          context,
          title: 'Değişiklikler kaybolsun mu?',
          message: 'Kaydedilmemiş bilgiler silinecek.',
          confirmLabel: 'Vazgeç ve çık',
          cancelLabel: 'Düzenlemeye dön',
          destructive: true,
        );
        if (discard && context.mounted) context.pop();
      },
      child: AppScaffold(
        title: 'Yeni ${terms.job}',
        showMenuButton: false,
        bottomBar: BottomSaveBar(
          saveLabel: '${terms.job} oluştur',
          loading: _saving,
          onSave: _save,
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: () => _dirty = true,
          child: ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
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
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickCustomer,
                icon: const Icon(Icons.person_search_outlined),
                label: Text(_pickLabel(terms.customer)),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '${terms.customer} adı *',
                ),
                validator: ProjectValidators.customerName,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _service,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Hizmet *'),
                validator: ProjectValidators.service,
              ),
              if (terms.serviceTypes.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  children: [
                    for (final s in terms.serviceTypes)
                      ActionChip(
                        label: Text(s),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onPressed: () => setState(() {
                          _service.text = s;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Sözleşme tutarı',
                  prefixText: '₺ ',
                  helperText: 'Boş bırakılırsa 0 olur.',
                ),
                validator: ProjectValidators.amount,
              ),
              const SizedBox(height: Space.lg),
              Text('Aşama', style: context.text.labelLarge),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  for (final s in ProjectStage.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _stage == s,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() {
                        _stage = s;
                        _dirty = true;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Adres'),
                validator: ProjectValidators.address,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Türkçe ek uyumu yalnız varsayılan sözcükte güvenli; özel sözlükte ek gerektirmeyen ifade.
String _pickLabel(String customerTerm) =>
    customerTerm == 'Müşteri' ? 'Mevcut müşteriden seç' : 'Kayıtlı kişiyi seç';
