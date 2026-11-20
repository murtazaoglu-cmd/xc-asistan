// Müşteri ekle / düzenle. Telefon klavyesi, adres alanı, tekrar eden telefon uyarısı (phone_key).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/phone.dart';
import '../data/customer_models.dart';
import '../data/customers_repository.dart';

class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.phoneKey});

  /// Doluysa düzenleme; boşsa yeni kayıt.
  final String? phoneKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final caps = ref.watch(capabilitiesProvider);
    final editing = phoneKey != null;
    final title = editing
        ? '${terms.customer} düzenle'
        : 'Yeni ${terms.customer.toLowerCase()}';
    if (caps == null || !caps.showCustomers) {
      return AppScaffold(
        title: title,
        showMenuButton: false,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    if (!editing) {
      return CustomerForm(title: title);
    }
    final c = ref.watch(customerProvider(phoneKey!));
    return c.when(
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
          onRetry: () => ref.invalidate(customerProvider(phoneKey!)),
        ),
      ),
      data: (cust) => CustomerForm(title: title, initial: cust),
    );
  }
}

class CustomerForm extends ConsumerStatefulWidget {
  const CustomerForm({super.key, required this.title, this.initial});
  final String title;
  final Customer? initial;

  @override
  ConsumerState<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<CustomerForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _region = TextEditingController(text: widget.initial?.region);
  late final _address = TextEditingController(text: widget.initial?.address);
  late final _note = TextEditingController(text: widget.initial?.note);

  bool _saving = false;
  String? _error;
  Customer? _duplicate;
  Timer? _dupTimer;
  String _dupCheckedKey = '';

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    _dupTimer?.cancel();
    for (final c in [_name, _phone, _email, _region, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  CustomerInput get _input => CustomerInput(
    name: _name.text,
    phone: _phone.text,
    email: _email.text,
    region: _region.text,
    address: _address.text,
    note: _note.text,
  );

  void _onPhoneChanged(String _) {
    if (_editing) return;
    _dupTimer?.cancel();
    final key = PhoneUtil.phoneKey(_phone.text);
    if (key.length < 10) {
      if (_duplicate != null) setState(() => _duplicate = null);
      return;
    }
    _dupTimer = Timer(
      const Duration(milliseconds: 450),
      () => _checkDuplicate(key),
    );
  }

  Future<Customer?> _checkDuplicate(String key) async {
    try {
      final found = await ref
          .read(customersRepositoryProvider)
          .findByPhone(key);
      _dupCheckedKey = key;
      if (mounted && PhoneUtil.phoneKey(_phone.text) == key) {
        setState(() => _duplicate = found);
      }
      return found;
    } catch (_) {
      return null; // denetim başarısızsa kaydı engelleme; sunucu 409 ile bildirir
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final repo = ref.read(customersRepositoryProvider);
    final terms = ref.read(brandProfileProvider).terms;
    final input = _input;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_editing) {
        final key = input.phoneKey;
        final dup = _dupCheckedKey == key
            ? _duplicate
            : await _checkDuplicate(key);
        if (dup != null) {
          if (!mounted) return;
          final go = await ConfirmDialog.show(
            context,
            title: 'Bu numara zaten kayıtlı',
            message:
                '${dup.displayName} aynı telefon numarasıyla kayıtlı. Yinelenen ${terms.customer.toLowerCase()} oluşturmak yerine mevcut kartı açmanız önerilir.',
            confirmLabel: 'Mevcut kartı aç',
            cancelLabel: 'Yine de kaydet',
          );
          if (go) {
            if (mounted) context.pushReplacement(Routes.customer(dup.phoneKey));
            return;
          }
        }
        final created = await repo.create(input);
        ref.invalidate(customerListProvider);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${terms.customer} eklendi.')));
        context.pushReplacement(Routes.customer(created.phoneKey));
      } else {
        await repo.update(widget.initial!.phoneKey, input);
        ref.invalidate(customerListProvider);
        ref.invalidate(customerProvider(widget.initial!.phoneKey));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Değişiklikler kaydedildi.')),
        );
        context.pop(true);
      }
    } catch (e) {
      final ex = AppException.from(e);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ex.code == AppErrorCode.conflict
              ? 'Bu telefon numarasıyla kayıtlı bir ${terms.customer.toLowerCase()} zaten var.'
              : ex.message;
        });
      }
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    return AppScaffold(
      title: widget.title,
      showMenuButton: false,
      bottomBar: BottomSaveBar(
        onSave: _save,
        loading: _saving,
        saveLabel: _editing ? 'Kaydet' : '${terms.customer} ekle',
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
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: context.colors.onErrorContainer,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: context.colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              key: const Key('field-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Ad soyad *'),
              validator: CustomerValidators.name,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              key: const Key('field-phone'),
              controller: _phone,
              enabled: !_editing,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()\-]')),
                LengthLimitingTextInputFormatter(24),
              ],
              onChanged: _onPhoneChanged,
              decoration: InputDecoration(
                labelText: 'Telefon *',
                hintText: '05XX XXX XX XX',
                helperText: _editing
                    ? 'Telefon numarası kimlik olduğu için değiştirilemez.'
                    : null,
                helperMaxLines: 2,
              ),
              validator: CustomerValidators.phone,
            ),
            if (_duplicate != null) ...[
              const SizedBox(height: Space.sm),
              _DuplicateWarning(
                customer: _duplicate!,
                onOpen: () => context.pushReplacement(
                  Routes.customer(_duplicate!.phoneKey),
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
            TextFormField(
              key: const Key('field-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: CustomerValidators.email,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _region,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Bölge (ilçe / mahalle)',
              ),
              validator: (v) => CustomerValidators.maxLen(v, 200, 'Bölge'),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _address,
              keyboardType: TextInputType.streetAddress,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              autofillHints: const [AutofillHints.fullStreetAddress],
              decoration: const InputDecoration(
                labelText: 'Adres',
                hintText: 'Mahalle, sokak, kapı no',
              ),
              validator: (v) => CustomerValidators.maxLen(v, 500, 'Adres'),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Not'),
              validator: (v) => CustomerValidators.maxLen(v, 2000, 'Not'),
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.customer, required this.onOpen});
  final Customer customer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: x.warningContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: x.warning),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Bu numara zaten kayıtlı: ${customer.displayName}',
                    style: context.text.bodyLarge?.copyWith(
                      color: context.colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(onPressed: onOpen, child: const Text('Mevcut kartı aç')),
          ],
        ),
      ),
    );
  }
}
