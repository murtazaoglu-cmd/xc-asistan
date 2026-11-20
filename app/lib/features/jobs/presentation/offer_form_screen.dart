// SAHİBİ: jobs ajanı. Yeni teklif talebi (POST /offers) ve temel bilgi düzenleme (PATCH /offers/:id).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../customers/customers_public.dart';
import '../data/jobs_models.dart';
import '../data/jobs_repository.dart';

class OfferFormScreen extends ConsumerStatefulWidget {
  /// null: yeni teklif; dolu: bu teklifin bilgilerini düzenle.
  const OfferFormScreen({super.key, this.offerId});
  final String? offerId;

  @override
  ConsumerState<OfferFormScreen> createState() => _OfferFormScreenState();
}

class _OfferFormScreenState extends ConsumerState<OfferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _service = TextEditingController();
  final _region = TextEditingController();
  final _address = TextEditingController();
  final _message = TextEditingController();
  final _notes = TextEditingController();

  bool _filled = false;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.offerId != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _service,
      _region,
      _address,
      _message,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Offer o) {
    if (_filled) return;
    _filled = true;
    _name.text = o.name;
    _phone.text = o.phone ?? '';
    _email.text = o.email ?? '';
    _service.text = o.service ?? '';
    _region.text = o.region ?? '';
    _address.text = o.address ?? '';
    _message.text = o.message ?? '';
    _notes.text = o.notes ?? '';
  }

  /// "Mevcut müşteriden seç": ad/telefon her zaman; e-posta, bölge ve adres yalnız müşteride varsa
  /// doldurulur (elle yazılmış değer boş bilgiyle ezilmez). Yinelenen müşteri kaydını önler.
  Future<void> _pickCustomer() async {
    final c = await showCustomerPicker(context);
    if (c == null || !mounted) return;
    setState(() {
      _name.text = c.name;
      if ((c.phone ?? '').isNotEmpty) _phone.text = c.phone!;
      if ((c.email ?? '').isNotEmpty) _email.text = c.email!;
      if ((c.region ?? '').isNotEmpty) _region.text = c.region!;
      if ((c.address ?? '').isNotEmpty) _address.text = c.address!;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = OfferDraft(
      name: _name.text,
      phone: _phone.text,
      service: _service.text,
      email: _email.text,
      region: _region.text,
      address: _address.text,
      message: _message.text,
      notes: _notes.text,
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(jobsRepositoryProvider);
      if (_isEdit) {
        await repo.updateOffer(widget.offerId!, draft);
        ref.invalidate(offerProvider(widget.offerId!));
        if (!mounted) return;
        setState(() => _dirty = false);
        context.pop(true);
      } else {
        final created = await repo.createOffer(draft);
        if (!mounted) return;
        setState(() => _dirty = false);
        context.pushReplacement(Routes.offer(created.id));
      }
    } catch (e) {
      final msg = AppException.from(e).message;
      if (mounted) {
        setState(() {
          _saving = false;
          _error = msg;
        });
      }
    }
  }

  Future<bool> _confirmDiscard() => ConfirmDialog.show(
    context,
    title: 'Değişiklikler kaybolsun mu?',
    message: 'Kaydedilmemiş bilgiler silinecek.',
    confirmLabel: 'Vazgeç ve çık',
    cancelLabel: 'Düzenlemeye dön',
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final title = _isEdit ? 'Bilgileri düzenle' : 'Yeni ${terms.offer}';

    Widget form() => Form(
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
                      style: TextStyle(color: context.colors.onErrorContainer),
                    ),
                  ),
                ),
              ),
            ),
          if (!_isEdit) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickCustomer,
              icon: const Icon(Icons.person_search_outlined),
              label: Text(_pickLabel(terms.customer)),
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Ya da aşağıya yeni ${terms.customer.toLowerCase()} bilgilerini yazın.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.md),
          ],
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(
              labelText: '${terms.customer} adı soyadı *',
            ),
            validator: OfferValidators.name,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Telefon *',
              hintText: '05XX XXX XX XX',
            ),
            validator: OfferValidators.phone,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-posta'),
            validator: OfferValidators.email,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _service,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Hizmet *'),
            validator: OfferValidators.service,
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
            controller: _region,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Bölge'),
            validator: OfferValidators.region,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _address,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Adres'),
            validator: OfferValidators.address,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: '${terms.customer} mesajı / ihtiyaç',
            ),
            validator: OfferValidators.message,
          ),
          if (_isEdit) ...[
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Not'),
            ),
          ],
        ],
      ),
    );

    final Widget body;
    if (_isEdit) {
      final async = ref.watch(offerProvider(widget.offerId!));
      body = AsyncValueView<Offer>(
        value: async,
        onRetry: () => ref.invalidate(offerProvider(widget.offerId!)),
        data: (o) {
          _fill(o);
          return form();
        },
      );
    } else {
      body = form();
    }

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) {
          setState(() => _dirty = false);
          context.pop();
        }
      },
      child: AppScaffold(
        title: title,
        showMenuButton: false,
        body: body,
        bottomBar: BottomSaveBar(
          saveLabel: _isEdit ? 'Kaydet' : '${terms.offer} oluştur',
          loading: _saving,
          onSave: _save,
        ),
      ),
    );
  }
}

/// Türkçe ek uyumu yalnız varsayılan sözcükte güvenli; özel sözlükte ek gerektirmeyen ifade.
String _pickLabel(String customerTerm) =>
    customerTerm == 'Müşteri' ? 'Mevcut müşteriden seç' : 'Kayıtlı kişiyi seç';
