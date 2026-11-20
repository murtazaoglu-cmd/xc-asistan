// SAHİBİ: settings ajanı. Çekirdek ayarlar çalışır durumda; ajan genişletir
// (kullanıcı yönetimi, profil vb.). Sürüm numarası ve bağlantı denemesi burada.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/api/health_service.dart';
import '../../../core/auth/biometric.dart';
import '../../../core/auth/session.dart';
import '../../assistant/assistant_public.dart' show AssistantPrefsSection;
import '../../../core/notifications/daily_scheduler.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _healthText;
  bool _checking = false;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _checkHealth() async {
    setState(() {
      _checking = true;
      _healthText = null;
    });
    final r = await ref.read(healthServiceProvider).check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _healthText = r.ok
          ? 'Bağlantı tamam (${r.latency?.inMilliseconds ?? '-'} ms).'
          : 'Bağlantı kurulamadı: ${r.error ?? ''}';
    });
  }

  Future<void> _toggleBiometric(bool v) async {
    final ok = await ref.read(appLockProvider.notifier).setEnabled(v);
    if (!ok)
      _toast(
        v
            ? 'Bu cihazda parmak izi/yüz ya da ekran kilidi doğrulaması kullanılamıyor.'
            : 'Değiştirilemedi.',
      );
  }

  Future<void> _enableNotifications() async {
    final ok = await ref.read(notificationServiceProvider).requestPermission();
    if (ok) await ref.read(dailySchedulerProvider).apply();
    _toast(
      ok
          ? 'Bildirimler açık.'
          : 'Bildirim izni verilmedi. Telefon ayarlarından açabilirsiniz.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final caps = ref.watch(capabilitiesProvider);
    final lock = ref.watch(appLockProvider);
    final themeMode = ref.watch(themeModeProvider);
    final config = ref.watch(appConfigProvider);
    final pkg = ref.watch(packageInfoProvider).value;

    return AppScaffold(
      title: 'Ayarlar',
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          if (user != null)
            SectionCard(
              title: 'Hesap',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: context.text.titleMedium),
                  Text(user.email),
                  Text(user.role.label),
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    key: const Key('change-password'),
                    onPressed: () => context.push(Routes.changePassword),
                    icon: const Icon(Icons.password),
                    label: const Text('Şifremi değiştir'),
                  ),
                ],
              ),
            ),
          if (caps != null && caps.showUsers) ...[
            const SizedBox(height: Space.md),
            SectionCard(
              title: 'Yönetim',
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: ListTile(
                key: const Key('open-users'),
                minTileHeight: Sizes.minTouch,
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Kullanıcılar'),
                subtitle: const Text('Personel, saha ve ortak hesapları'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.users),
              ),
            ),
          ],
          // Web: biyometrik kilit yok (tarayıcıda cihaz doğrulaması kullanılamaz).
          if (!kIsWeb) ...[
            const SizedBox(height: Space.md),
            SectionCard(
              title: 'Güvenlik',
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: SwitchListTile(
                key: const ValueKey('biometric-switch'),
                title: const Text('Parmak izi / yüz ile kilit'),
                subtitle: const Text(
                  'Uygulamaya her dönüşte kimlik doğrulaması istenir.',
                ),
                value: lock.enabled,
                onChanged: _toggleBiometric,
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Görünüm',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem')),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu')),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Bildirimler',
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sabah/akşam saati, günler, sessiz saat: sunucudaki asistan tercihleri.
                const AssistantPrefsSection(shrinkWrap: true),
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Text(
                      'Web panelinde bildirimler tarayıcıya gönderilmez; Bugün ekranındaki zil (Gelen kutusu) üzerinden görünür.',
                      key: const Key('web-inbox-note'),
                      style: context.text.bodySmall,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _enableNotifications,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Bildirim iznini ver'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Bağlantı ve sürüm',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sürüm: ${pkg == null ? '-' : '${pkg.version} (${pkg.buildNumber})'}',
                  key: const ValueKey('version-text'),
                ),
                Text(
                  'Sunucu: ${config.demo ? 'DEMO (bellek içi örnek veri)' : config.apiBaseUrl}',
                ),
                const SizedBox(height: Space.md),
                OutlinedButton.icon(
                  key: const ValueKey('health-button'),
                  onPressed: _checking ? null : _checkHealth,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Bağlantıyı dene'),
                ),
                if (_healthText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Text(_healthText!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Oturum',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: 'Tüm cihazlardan çıkış yapılsın mı?',
                      message: 'Bu hesabın açık olduğu tüm telefonlarda oturum kapanır.',
                      confirmLabel: 'Tümünden çık',
                      destructive: true,
                    );
                    if (!ok) return;
                    try {
                      await ref.read(sessionProvider.notifier).logoutAll();
                    } catch (e) {
                      _toast(AppException.from(e).message);
                    }
                  },
                  child: const Text('Tüm cihazlardan çıkış'),
                ),
                const SizedBox(height: Space.sm),
                FilledButton(
                  onPressed: () => ref.read(sessionProvider.notifier).logout(),
                  child: const Text('Çıkış yap'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
