import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/auth/biometric.dart';
import 'core/auth/session.dart';
import 'core/config/brand_profile.dart';
import 'core/notifications/daily_scheduler.dart';
import 'core/notifications/notification_providers.dart';
import 'core/router/app_router.dart';
import 'core/router/deep_links.dart';
import 'core/router/routes.dart';
import 'core/share/share_service.dart';
import 'core/storage/storage_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/web/page_title.dart';
import 'features/assistant/assistant_public.dart' show chatHistoryStoreProvider;
import 'features/auth/presentation/lock_screen.dart';

class XcApp extends ConsumerWidget {
  const XcApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final brand = ref.watch(brandProfileProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: brand.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(primary: brand.primaryColor),
      darkTheme: AppTheme.dark(primary: brand.primaryColor),
      themeMode: themeMode,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: [...GlobalMaterialLocalizations.delegates],
      routerConfig: router,
      builder: (context, child) => PageTitleSync(
        router: router,
        glossary: brand.terms,
        appName: brand.appName,
        child: AppRoot(router: router, child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Uygulama kökü: yaşam döngüsü (kilit, jeton yenileme, bildirim yeniden kurma), bildirim
/// dokunuşu, "Paylaş" akışı, bekleyen derin bağlantı ve biyometrik kilit örtüsü.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServices());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startServices() async {
    // Bildirim dokunuşu → rota
    try {
      final n = ref.read(notificationServiceProvider);
      await n.init();
      n.taps.listen((p) => ref.read(pendingLocationProvider.notifier).open(p));
      final launch = await n.takeLaunchPayload();
      if (launch != null)
        ref.read(pendingLocationProvider.notifier).open(launch);
    } catch (e) {
      if (kDebugMode) debugPrint('Bildirim başlatılamadı: $e');
    }
    // "Paylaş" menüsü → alınan paylaşım → /assistant/share
    try {
      final s = ref.read(shareServiceProvider);
      s.shares.listen((share) {
        ref.read(receivedShareProvider.notifier).receive(share);
        ref.read(pendingLocationProvider.notifier).open(Routes.assistantShare);
      });
      await s.start();
    } catch (e) {
      if (kDebugMode) debugPrint('Paylaşım dinleyicisi başlatılamadı: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.onBackgrounded();
      case AppLifecycleState.resumed:
        lock.onResumed();
        ref.read(sessionProvider.notifier).onAppResumed();
        _rescheduleNotifications();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _rescheduleNotifications() async {
    if (ref.read(sessionProvider) is! SessionAuthenticated) return;
    try {
      await ref.read(dailySchedulerProvider).apply();
    } catch (_) {}
  }

  /// Girişten sonra: bildirim iznini bir kez iste, günlük bildirimleri kur.
  Future<void> _onAuthenticated() async {
    try {
      final prefs = ref.read(appPrefsProvider);
      if (!prefs.notificationPermissionAsked) {
        await prefs.setNotificationPermissionAsked(true);
        await ref.read(notificationServiceProvider).requestPermission();
      }
      await ref.read(dailySchedulerProvider).apply();
    } catch (_) {}
  }

  /// Çıkışta: zamanlanmış bildirimler oturum katmanında iptal edilir (cancelAll);
  /// cihazdaki asistan sohbet geçmişi burada açıkça silinir.
  void _onLoggedOut() {
    try {
      ref.read(chatHistoryStoreProvider).clearAll();
    } catch (_) {}
  }

  void _applyPending() {
    final pending = ref.read(pendingLocationProvider);
    if (pending == null) return;
    if (ref.read(sessionProvider) is! SessionAuthenticated) return;
    if (ref.read(appLockProvider).locked) return;
    ref.read(pendingLocationProvider.notifier).clear();
    widget.router.go(pending);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next is SessionAuthenticated && prev is! SessionAuthenticated) {
        _onAuthenticated();
        _applyPending();
      } else if (next is! SessionAuthenticated &&
          prev is SessionAuthenticated) {
        _onLoggedOut();
      }
    });
    ref.listen<String?>(pendingLocationProvider, (_, _) => _applyPending());
    ref.listen<AppLockState>(appLockProvider, (_, _) => _applyPending());

    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      children: [
        widget.child,
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
