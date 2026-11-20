// Kendi şifreni değiştir (PATCH /users/me/password). Başarıda sunucu tüm eski jetonları iptal eder;
// yanıttaki YENİ jeton saklanır (oturum kapanmaz). Diğer cihazlar çıkış yapar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/settings_repository.dart';
import '../data/user_rules.dart';
import 'password_field.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.settings);
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(settingsRepositoryProvider)
          .changeOwnPassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      await ref.read(sessionProvider.notifier).adoptToken(r.token);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Şifreniz değiştirildi. Diğer cihazlardaki oturumlar kapatıldı.',
          ),
        ),
      );
      _close();
    } catch (e) {
      if (!mounted) return;
      final ex = e is AppException ? e : null;
      setState(() {
        _saving = false;
        _error = ex?.code == AppErrorCode.validation && ex!.message.isNotEmpty
            ? ex.message
            : UserErrors.message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Şifremi değiştir',
    showMenuButton: false,
    bottomBar: BottomSaveBar(
      onSave: _saving ? null : _save,
      loading: _saving,
      saveLabel: 'Şifreyi değiştir',
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
                key: const Key('password-error'),
                style: TextStyle(color: context.colors.error),
              ),
            ),
          PasswordField(
            key: const Key('field-current'),
            controller: _current,
            label: 'Mevcut şifre',
            validator: UserValidators.currentPassword,
            autofocus: true,
          ),
          const SizedBox(height: Space.md),
          PasswordField(
            key: const Key('field-new'),
            controller: _next,
            label: 'Yeni şifre',
            helperText: 'En az ${UserValidators.passwordMin} karakter.',
            validator: (v) => UserValidators.newPassword(v, _current.text),
          ),
          const SizedBox(height: Space.md),
          PasswordField(
            key: const Key('field-confirm'),
            controller: _confirm,
            label: 'Yeni şifre (tekrar)',
            textInputAction: TextInputAction.done,
            validator: (v) => UserValidators.confirm(v, _next.text),
          ),
          const SizedBox(height: Space.lg),
          Text(
            'Şifre değişince bu hesabın diğer cihazlardaki oturumları kapanır; bu cihazda oturumunuz sürer.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    ),
  );
}
