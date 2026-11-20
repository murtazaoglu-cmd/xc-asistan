// SAHİBİ: home ajanı. Bugün (sabah) ekranı: tüm roller, rol/yetkiye göre.
//   Yönetici/personel/ortak/muhasebe: selamlama, Asistan Özeti, 4'lü sayı kutuları, bugün/yarın
//   randevuları, yeni talepler, geciken işler, hatırlatıcılar, düşük stok, tahsilat özeti.
//   Saha: sade lacivert ekran (FieldHomeBody).
// Durumlar: iskelet / hata (Tekrar dene) / çevrimdışı uyarı şeridi (eski veri korunur) / boş gün.
// Çekip yenileme + 3 dk'da bir ve uygulamaya dönüşte SESSİZ arka plan yenilemesi.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../appointments/appointments_routes.dart';
import '../../appointments/data/tr_text.dart';
import '../../assistant/assistant_public.dart'
    show BriefingSummaryCard, InboxBellButton;
import '../application/home_controller.dart';
import '../data/home_insights.dart';
import 'field_home_body.dart';
import 'widgets/home_sections.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _timer;

  /// Uygulamaya dönüşte bu süreden eski veri sessizce yenilenir.
  static const Duration _staleAfter = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final every = ref.read(homeAutoRefreshProvider);
    if (every != null) {
      _timer = Timer.periodic(every, (_) => _silentRefresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _silentRefresh() {
    if (!mounted) return;
    ref.read(homeControllerProvider.notifier).refresh(silent: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final d = ref.read(homeControllerProvider).value;
    if (d == null || Ist.now().difference(d.fetchedAt) > _staleAfter) {
      _silentRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(homeControllerProvider);
    final caps =
        ref.watch(capabilitiesProvider) ??
        AppCapabilities.forRole(UserRole.saha);
    final terms = ref.watch(brandProfileProvider).terms;
    final ctrl = ref.read(homeControllerProvider.notifier);
    final data = async.value;

    Future<void> refresh() => ctrl.refresh();

    final Widget body;
    if (data != null) {
      final banner = data.refreshError == null
          ? null
          : StaleBanner(error: data.refreshError!, onRetry: refresh);
      body = PullToRefresh(
        onRefresh: refresh,
        child: caps.isField
            ? FieldHomeBody(
                summary: data.summary,
                updatedAt: data.fetchedAt,
                banner: banner,
              )
            : _ManagerBody(data: data, caps: caps, banner: banner),
      );
    } else if (async.hasError) {
      body = PullToRefresh.fill(
        onRefresh: refresh,
        child: ErrorState(
          error: async.error,
          onRetry: () => ref.invalidate(homeControllerProvider),
        ),
      );
    } else {
      body = const HomeSkeleton();
    }

    return AppScaffold(
      title: 'Bugün',
      wideLayout: true,
      actions: [
        const InboxBellButton(),
        IconButton(
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh),
          onPressed: refresh,
        ),
      ],
      // Saha ekranında "Randevu ekle" yok; diğer roller için hızlı ekleme.
      floatingActionButton:
          (data != null && caps.appointmentsCreate && !caps.isField)
          ? FloatingActionButton(
              tooltip: '${terms.appointment} ekle',
              onPressed: () => context.push(
                AppointmentsRoutes.newPath(day: Ist.startOfDay(Ist.now())),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: body,
    );
  }
}

class _ManagerBody extends ConsumerWidget {
  const _ManagerBody({required this.data, required this.caps, this.banner});
  final HomeData data;
  final AppCapabilities caps;
  final Widget? banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final s = data.summary;
    final now = Ist.now();
    final canCreate = caps.appointmentsCreate;
    final lines = buildInsights(s, caps: caps, terms: terms, now: now);
    final quiet = isQuietDay(s, caps);
    final showOffers = caps.offers && (s.newOfferCount ?? 0) > 0;
    final showOverdue = caps.projects && s.overdueProjectCount > 0;
    final showStock = caps.materials && s.lowStockCount > 0;
    final showFinance = caps.homeFinance && s.finance != null;
    final todayAdd = canCreate
        ? () =>
              context.push(AppointmentsRoutes.newPath(day: Ist.startOfDay(now)))
        : null;

    Widget gap() => const SizedBox(height: Space.md);

    final briefing = const BriefingSummaryCard(showStats: false);
    final assistantCard = AssistantSummaryCard(lines: lines);
    final stats = HomeStatTiles(summary: s, caps: caps, terms: terms);
    final today = (!quiet || s.today.isNotEmpty)
        ? AppointmentsSection(
            title: 'Bugünkü ${trLower(terms.appointments)}',
            items: s.today,
            emptyText: 'Bugün ${trLower(terms.appointment)} yok.',
            onAdd: todayAdd,
          )
        : null;
    final tomorrow = s.tomorrow.any((a) => !a.isCancelled)
        ? AppointmentsSection(
            title: 'Yarınki ${trLower(terms.appointments)}',
            items: s.tomorrow,
            emptyText: 'Yarın ${trLower(terms.appointment)} yok.',
            showAll: false,
          )
        : null;
    final offers = showOffers
        ? NewOffersSection(summary: s, canOpen: caps.showJobs)
        : null;
    final overdue = showOverdue
        ? OverdueProjectsSection(summary: s, canOpen: caps.showJobs)
        : null;
    final reminders = s.reminderCount > 0 ? RemindersSection(summary: s) : null;
    final stock = showStock
        ? LowStockSection(summary: s, canOpen: caps.showStock)
        : null;
    final finance = showFinance
        ? FinanceSection(finance: s.finance!, canOpen: caps.showFinance)
        : null;
    final quietCard = quiet ? QuietDayCard(canCreate: canCreate) : null;

    // GENİŞ EKRAN (web paneli): sayı kutuları üstte tam genişlik, kartlar 2-3 sütunda.
    final wide = ShellController.maybeOf(context)?.wide ?? false;
    if (wide) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 96),
        children: [
          if (banner != null) ...[banner!, gap()],
          HomeGreeting(name: s.userName, now: now, updatedAt: data.fetchedAt),
          const SizedBox(height: Space.lg),
          ResponsiveColumns(
            gap: Space.lg,
            fullWidth: [stats],
            children: [
              briefing,
              assistantCard,
              ?quietCard,
              ?today,
              ?tomorrow,
              ?offers,
              ?overdue,
              ?reminders,
              ?stock,
              ?finance,
            ],
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
      children: [
        if (banner != null) ...[banner!, gap()],
        HomeGreeting(name: s.userName, now: now, updatedAt: data.fetchedAt),
        const SizedBox(height: Space.lg),
        briefing,
        gap(),
        assistantCard,
        gap(),
        stats,
        gap(),
        if (quietCard != null) ...[quietCard, gap()],
        if (today != null) ...[today, gap()],
        if (tomorrow != null) ...[tomorrow, gap()],
        if (offers != null) ...[offers, gap()],
        if (overdue != null) ...[overdue, gap()],
        if (reminders != null) ...[reminders, gap()],
        if (stock != null) ...[stock, gap()],
        ?finance,
      ],
    );
  }
}
