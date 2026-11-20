// Yeni kullanıcı: ad, e-posta, şifre, rol (yetkiye göre: yönetici tüm roller, ortak yalnız saha/personel).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/settings_repository.dart';
import '../data/user_models.dart';
import '../data/user_rules.dart';
import 'password_field.dart';

class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  UserRole? _role;
  String? _leaderId;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  String? _emailError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _close([Object? result]) {
    if (context.canPop()) {
      context.pop(result);
    } else {
      context.go(Routes.users);
    }
  }

  Future<void> _save(UserRole actor) async {
    setState(() {
      _error = null;
      _emailError = null;
      _submitted = true;
    });
    final ok = _form.currentState?.validate() ?? false;
    final roleErr = UserValidators.role(_role, actor);
    if (!ok || roleErr != null) return;
    final input = NewUserInput(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      role: _role!,
      leaderId: (_role == UserRole.personel || _role == UserRole.saha)
          ? _leaderId
          : null,
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).createUser(input);
      ref.invalidate(usersProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${input.name.trim()} eklendi (${_role!.label}).'),
        ),
      );
      _close(true);
    } catch (e) {
      if (!mounted) return;
      final ex = e is AppException ? e : null;
      setState(() {
        _saving = false;
        if (ex?.code == AppErrorCode.conflict) {
          _emailError = UserErrors.message(e);
          _form.currentState?.validate();
        } else {
          _error = ex?.code == AppErrorCode.validation && ex!.message.isNotEmpty
              ? ex.message
              : UserErrors.message(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    if (caps == null || !caps.showUsers) {
      return const AppScaffold(
        title: 'Yeni kullanıcı',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
          message: 'Kullanıcıları yalnızca yönetici ve iş ortağı yönetebilir.',
        ),
      );
    }
    final actor = caps.role;
    final roles = UserRules.assignableRoles(actor);
    final showLeader =
        actor == UserRole.admin &&
        ref.watch(userEditEnabledProvider) &&
        (_role == UserRole.personel || _role == UserRole.saha);
    final ortaks = showLeader
        ? (ref.watch(usersProvider).value ?? const <ManagedUser>[])
              .where((u) => u.role == UserRole.ortak)
              .toList()
        : const <ManagedUser>[];
    return AppScaffold(
      title: 'Yeni kullanıcı',
      showMenuButton: false,
      bottomBar: BottomSaveBar(
        onSave: _saving ? null : () => _save(actor),
        loading: _saving,
        saveLabel: 'Kullanıcıyı ekle',
        onCancel: _close,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text(
                  _error!,
                  key: const Key('user-form-error'),
                  style: TextStyle(color: context.colors.error),
                ),
              ),
            TextFormField(
              key: const Key('field-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: UserValidators.name,
              decoration: const InputDecoration(labelText: 'Ad soyad'),
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              key: const Key('field-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => _emailError ?? UserValidators.email(v),
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
            const SizedBox(height: Space.md),
            PasswordField(
              key: const Key('field-password'),
              controller: _password,
              label: 'Şifre',
              helperText:
                  'En az ${UserValidators.passwordMin} karakter. Kullanıcıya iletin; ilk girişte değiştirmesini söyleyin.',
              validator: UserValidators.password,
            ),
            const SizedBox(height: Space.md),
            PasswordField(
              key: const Key('field-confirm'),
              controller: _confirm,
              label: 'Şifre (tekrar)',
              textInputAction: TextInputAction.done,
              validator: (v) => UserValidators.confirm(v, _password.text),
            ),
            const SizedBox(height: Space.lg),
            Text('Rol', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            RadioGroup<UserRole>(
              groupValue: _role,
              onChanged: (r) => setState(() => _role = r),
              child: Column(
                children: [
                  for (final r in roles)
                    RadioListTile<UserRole>(
                      key: Key('role-${r.api}'),
                      value: r,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label),
                      subtitle: Text(RoleInfo.describe(r)),
                    ),
                ],
              ),
            ),
            if (_submitted && UserValidators.role(_role, actor) != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  UserValidators.role(_role, actor)!,
                  key: const Key('role-error'),
                  style: TextStyle(color: context.colors.error),
                ),
              ),
            if (actor == UserRole.ortak)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Eklediğiniz kullanıcılar yalnızca sizin firmanızın verisini görür.',
                  style: context.text.bodySmall,
                ),
              ),
            if (showLeader && ortaks.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              DropdownButtonFormField<String?>(
                key: const Key('field-leader'),
                initialValue: _leaderId,
                decoration: const InputDecoration(
                  labelText: 'Bağlı olduğu ortak firma',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Kendi ekibim'),
                  ),
                  for (final o in ortaks)
                    DropdownMenuItem<String?>(value: o.id, child: Text(o.name)),
                ],
                onChanged: (v) => setState(() => _leaderId = v),
              ),
            ],
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }
}
