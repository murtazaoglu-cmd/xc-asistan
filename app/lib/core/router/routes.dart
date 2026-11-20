// Rota yolları TEK yerde. Ekranlar yol metni yazmaz: `context.go(Routes.offer(id))`.
// Derin bağlantılar: /jobs/offers/:id, /jobs/projects/:id, /customers/:phoneKey, /appointments/:id.
import '../auth/auth_models.dart';

abstract final class Routes {
  // Kabuk dışı
  static const splash = '/splash';
  static const login = '/login';
  static const updateRequired = '/update-required';

  // Kabuk: alt çubuk sekmeleri
  static const today = '/today';
  static const jobs = '/jobs';
  static const assistant = '/assistant';
  static const customers = '/customers';
  static const finance = '/finance';

  // Kabuk: seyrek ekranlar (sol üst menü)
  static const appointments = '/appointments';
  static const stock = '/stock';
  static const reports = '/reports';
  static const invoicesVat = '/invoices-vat';
  static const settings = '/settings';
  static const users = '/users'; // Kullanıcılar (yalnız admin/ortak)
  static const changePassword = '/settings/password';
  static const more = '/more';

  // Alt rotalar (yol kalıpları: GoRoute.path içinde, üst yola göreli)
  static const offerPattern = 'offers/:id';
  static const projectPattern = 'projects/:id';
  static const customerPattern = ':phoneKey';
  static const appointmentPattern = ':id';
  static const sharePattern = 'share';

  static String offer(String id) => '$jobs/offers/$id';
  static String project(String id) => '$jobs/projects/$id';
  static String customer(String phoneKey) => '$customers/$phoneKey';
  static String appointment(String id) => '$appointments/$id';
  static const assistantShare = '$assistant/share';
}

/// Rota erişim denetimi (menüyle AYNI kurallar; sunucu yine her uçta denetler).
abstract final class RouteGuard {
  static const _fieldAssistantPaths = [
    '/assistant/briefing',
    '/assistant/closure',
    '/assistant/inbox',
    '/assistant/prefs',
  ];

  static bool isAllowed(String path, AppCapabilities caps) {
    bool under(String root) => path == root || path.startsWith('$root/');
    if (under(Routes.jobs)) return caps.showJobs;
    if (under(Routes.assistant)) {
      if (caps.showAssistant) return true;
      // Saha: sade brifing, gün sonu, gelen kutusu ve bildirim tercihleri (sohbet/içe aktarma yok).
      return caps.isField && _fieldAssistantPaths.any(under);
    }
    if (under(Routes.customers)) return caps.showCustomers;
    if (under(Routes.finance)) return caps.showFinance;
    if (under(Routes.stock)) return caps.showStock;
    if (under(Routes.reports)) return caps.showReports;
    if (under(Routes.invoicesVat)) return caps.showInvoicesVat;
    if (under(Routes.users)) return caps.showUsers;
    return true; // today, appointments, settings, more
  }
}
