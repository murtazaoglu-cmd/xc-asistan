// Kompozisyon kökü: feature modüllerini birbirine takan TEK yer. Feature'lar birbirinin
// presentation kodunu içe aktarmaz; bağlantılar burada Riverpod override'ları ile kurulur.
// `main.dart` ve testlerdeki `pumpXcApp` aynı listeyi kullanır.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart' show Icons;

import 'package:share_plus/share_plus.dart';

import 'core/notifications/daily_scheduler.dart';
import 'core/notifications/notification_providers.dart';
import 'core/storage/storage_providers.dart';
import 'core/router/master_detail.dart';
import 'core/router/routes.dart';
import 'core/web/browser.dart';
import 'features/assistant/assistant_public.dart';
import 'features/appointments/presentation/appointments_screen.dart'
    show AppointmentsScreen;
import 'features/customers/presentation/conversation_section.dart';
import 'features/customers/presentation/customers_screen.dart'
    show CustomersScreen;
import 'features/jobs/presentation/jobs_screen.dart' show JobsScreen;
import 'features/finance/presentation/payment_schedule_section.dart'
    show paymentScheduleBuilderProvider;
import 'features/invoices_vat/data/invoices_vat_models.dart' show ExportFile;
import 'features/invoices_vat/data/invoices_vat_services.dart'
    show ExportDelivery, ExportSharer, LocalExportSharer, exportSharerProvider;
import 'features/invoices_vat/presentation/payment_schedule_section.dart'
    as vat;

/// Riverpod 3 varsayılan olarak başarısız sağlayıcıyı otomatik yeniden dener ve bu sırada
/// "yükleniyor" kalır; hata/çevrimdışı durumu uzun süre iskelet görünürdü. GET'leri ApiClient zaten dener.
Duration? noProviderRetry(int retryCount, Object error) => null;

/// Core'un günlük bildirim kurucusunun yerine asistan kurucusu çalışır (aynı bildirim
/// kimlikleri; ikisi birden çalışırsa çift/çakışan bildirim olurdu). Core çağrıları
/// (açılış, ön plana dönüş, giriş sonrası, ayarlar) böylece asistan tercihlerini uygular.
class AssistantBackedDailyScheduler extends DailyNotificationScheduler {
  AssistantBackedDailyScheduler(
    this._assistant, {
    required super.service,
    required super.prefs,
    required super.content,
  });
  final AssistantNotificationScheduler _assistant;

  @override
  Future<void> apply() => _assistant.apply();
}

/// Fatura/KDV dışa aktarma: dosyayı geçici klasöre yazar, sonra sistem paylaş menüsünü açar
/// (Drive, e-posta, WhatsApp...). Menü açılamazsa dosya yolu gösterilir (kayıt başarılıdır).
class ShareSheetExportSharer extends LocalExportSharer {
  @override
  Future<ExportDelivery> deliver(ExportFile file) async {
    final saved = await super.deliver(file);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(saved.path, mimeType: file.mime)],
          subject: file.filename,
        ),
      );
      return ExportDelivery(path: saved.path, shared: true);
    } on Object {
      return saved;
    }
  }
}

/// Web: dışa aktarılan dosya tarayıcı indirmesi olarak iner (paylaş menüsü/dosya sistemi yok).
class WebDownloadExportSharer implements ExportSharer {
  @override
  Future<ExportDelivery> deliver(ExportFile file) async {
    final ok = await browserDownload(file.bytes, file.filename, file.mime);
    if (!ok) throw UnsupportedError('İndirme başlatılamadı.');
    return const ExportDelivery(path: 'tarayıcı indirmeleri klasörü');
  }
}

/// Geniş pencerede (>= 1200 dp) liste + ayrıntı bölmeleri (core/router/master_detail.dart).
final List<MasterPane> masterPanes = [
  MasterPane(
    prefix: Routes.jobs,
    builder: (_) => const JobsScreen(),
    emptyIcon: Icons.work_outline,
    emptyTitle: 'Bir teklif ya da iş seçin',
  ),
  MasterPane(
    prefix: Routes.customers,
    builder: (_) => const CustomersScreen(),
    emptyIcon: Icons.groups_outlined,
    emptyTitle: 'Bir müşteri seçin',
  ),
  MasterPane(
    prefix: Routes.appointments,
    builder: (_) => const AppointmentsScreen(),
    emptyIcon: Icons.event_outlined,
    emptyTitle: 'Bir randevu seçin',
  ),
];

final List<Override> featureWiring = [
  masterPanesProvider.overrideWithValue(masterPanes),
  exportSharerProvider.overrideWithValue(
    kIsWeb ? WebDownloadExportSharer() : ShareSheetExportSharer(),
  ),
  // Müşteri kartı: yazışma geçmişi (assistant)
  conversationSectionBuilderProvider.overrideWithValue(
    (context, args) => AssistantConversationSection(
      phoneKey: args.customer.phoneKey,
      name: args.customer.name,
    ),
  ),
  // Finans alacak kartı: vade / ödeme planı (invoices_vat)
  paymentScheduleBuilderProvider.overrideWithValue(
    (context, p) => vat.PaymentScheduleSection(
      projectId: p.id,
      projectCode: p.code,
      customerName: p.customerName,
      remaining: p.remaining,
    ),
  ),
  // Sabah/akşam bildirimleri: asistan kurucusu
  dailySchedulerProvider.overrideWith(
    (ref) => AssistantBackedDailyScheduler(
      ref.watch(assistantNotificationSchedulerProvider),
      service: ref.watch(notificationServiceProvider),
      prefs: ref.watch(appPrefsProvider),
      content: ref.watch(briefingContentProvider),
    ),
  ),
];
