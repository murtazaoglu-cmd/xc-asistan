import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/tokens.dart';

/// Giriş ekranı (client:"mobile"). Oturum süresi dolduysa üstte bilgi gösterir.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(appPrefsProvider).lastEmail ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_email.text, _password.text);
      // Yönlendirmeyi router yapar (oturum durumu değişince).
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final notice = session is SessionUnauthenticated ? session.notice : null;
    final brand = ref.watch(brandProfileProvider);
    final demo = ref.watch(appConfigProvider).demo;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandLogo(size: Sizes.logoLarge)),
                      const SizedBox(height: Space.lg),
                      Text(
                        brand.appName,
                        style: context.text.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        brand.tagline,
                        style: context.text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.xxl),
                      if (notice != null)
                        _Banner(
                          text: notice,
                          color: context.xc.warningContainer,
                          fg: context.xc.warning,
                          icon: Icons.lock_clock,
                        ),
                      if (_error != null)
                        _Banner(
                          text: _error!,
                          color: context.colors.errorContainer,
                          fg: context.colors.onErrorContainer,
                          icon: Icons.error_outline,
                        ),
                      TextFormField(
                        key: const ValueKey('login-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'E-posta',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'E-posta adresinizi girin.';
                          if (!t.contains('@') || !t.contains('.'))
                            return 'Geçerli bir e-posta girin.';
                          return null;
                        },
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: Space.lg),
                      TextFormField(
                        key: const ValueKey('login-password'),
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Şifreyi göster'
                                : 'Şifreyi gizle',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Şifrenizi girin.'
                            : null,
                        onFieldSubmitted: (_) {
                          TextInput.finishAutofillContext();
                          _submit();
                        },
                      ),
                      const SizedBox(height: Space.xl),
                      FilledButton(
                        key: const ValueKey('login-submit'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Giriş yap'),
                      ),
                      if (demo) ...[
                        const SizedBox(height: Space.lg),
                        Text(
                          'DEMO modu: herhangi bir şifre kabul edilir. Rol için e-postaya saha, personel, '
                          'muhasebe veya ortak yazın (ör. saha@demo.com).',
                          style: context.text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.color,
    required this.fg,
    required this.icon,
  });
  final String text;
  final Color color;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  text,
                  style: context.text.bodyMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
