// Menü öğeleri ve rol/yetkiye göre görünürlük (tek doğruluk kaynağı).
// Alt çubuk: Bugün · İşler · Asistan(orta, büyük) · Müşteriler · Para.
// Sol üst menü: Randevular, Stok, Raporlar, Fatura/KDV, Ayarlar.
// SAHA rolü SADE kabuk: alt çubukta yalnız Bugün + Randevular; çekmecede yalnız Ayarlar.
import 'package:material_ui/material_ui.dart';

import '../auth/auth_models.dart';
import '../config/brand_profile.dart';
import 'routes.dart';

class NavItem {
  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.branchIndex,
    this.isCenter = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  /// StatefulShellRoute dalı (sekme durumunu korumak için). 5 = seyrek ekranlar dalı.
  final int branchIndex;

  /// Alt çubuğun ortasındaki büyük vurgulu düğme (Asistan).
  final bool isCenter;

  bool matches(String location) =>
      location == path || location.startsWith('$path/');
}

/// Dal numaraları (app_router.dart'taki sırayla aynı).
abstract final class Branches {
  static const today = 0;
  static const jobs = 1;
  static const assistant = 2;
  static const customers = 3;
  static const finance = 4;
  static const extras = 5;
  static const tabCount = 5; // 0..4 sekme; 5 sekme değil
}

abstract final class NavCatalog {
  static NavItem today() => const NavItem(
    id: 'today',
    label: 'Bugün',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
    path: Routes.today,
    branchIndex: Branches.today,
  );

  static NavItem appointments(Glossary g) => NavItem(
    id: 'appointments',
    label: g.appointments,
    icon: Icons.event_outlined,
    selectedIcon: Icons.event,
    path: Routes.appointments,
    branchIndex: Branches.extras,
  );

  static List<NavItem> bottom(AppCapabilities c, Glossary g) {
    if (c.isField) return [today(), appointments(g)];
    return [
      today(),
      if (c.showJobs)
        NavItem(
          id: 'jobs',
          label: g.jobs,
          icon: Icons.work_outline,
          selectedIcon: Icons.work,
          path: Routes.jobs,
          branchIndex: Branches.jobs,
        ),
      if (c.showAssistant)
        const NavItem(
          id: 'assistant',
          label: 'Asistan',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
          path: Routes.assistant,
          branchIndex: Branches.assistant,
          isCenter: true,
        ),
      if (c.showCustomers)
        NavItem(
          id: 'customers',
          label: g.customers,
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          path: Routes.customers,
          branchIndex: Branches.customers,
        ),
      if (c.showFinance)
        NavItem(
          id: 'finance',
          label: g.money,
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          path: Routes.finance,
          branchIndex: Branches.finance,
        ),
    ];
  }

  static List<NavItem> drawer(AppCapabilities c, Glossary g) {
    const settings = NavItem(
      id: 'settings',
      label: 'Ayarlar',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      path: Routes.settings,
      branchIndex: Branches.extras,
    );
    if (c.isField) return const [settings];
    return [
      // Alt çubukta da olan sekmeler menüde de bulunur ("Daha fazla" tüm modüllere açılır).
      if (c.showCustomers)
        NavItem(
          id: 'customers',
          label: g.customers,
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          path: Routes.customers,
          branchIndex: Branches.customers,
        ),
      if (c.showAssistant)
        const NavItem(
          id: 'assistant',
          label: 'Asistan',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
          path: Routes.assistant,
          branchIndex: Branches.assistant,
        ),
      appointments(g),
      if (c.showStock)
        NavItem(
          id: 'stock',
          label: g.stock,
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          path: Routes.stock,
          branchIndex: Branches.extras,
        ),
      if (c.showReports)
        const NavItem(
          id: 'reports',
          label: 'Raporlar',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          path: Routes.reports,
          branchIndex: Branches.extras,
        ),
      if (c.showInvoicesVat)
        const NavItem(
          id: 'invoices',
          label: 'Fatura / KDV',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          path: Routes.invoicesVat,
          branchIndex: Branches.extras,
        ),
      if (c.showUsers)
        const NavItem(
          id: 'users',
          label: 'Kullanıcılar',
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts,
          path: Routes.users,
          branchIndex: Branches.extras,
        ),
      settings,
    ];
  }
}
