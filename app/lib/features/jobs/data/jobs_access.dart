// SAHİBİ: jobs ajanı. Rol/yetki görünürlüğü TEK yerde (sözleşme §0 roller, §5 finans, §10 saha).
// Not: bu yalnız arayüz gizlemesidir; sunucu her uçta yetkiyi yine denetler.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';

class JobsAccess {
  const JobsAccess(this.caps);
  final AppCapabilities caps;

  UserRole get role => caps.role;
  bool get isField => caps.isField;

  /// Teklifler sekmesi (A M O P). Saha 403.
  bool get canSeeOffers => !isField && caps.offers;

  /// Projeler sekmesi (A M O P).
  bool get canSeeProjects => !isField && caps.projects;

  /// Teklif hazırlama/gönderme (POST /quotes: A M O; personel yok).
  bool get canPrepareQuote => !isField && caps.quotes;

  /// Teklif şablonları (/quote-templates: yalnız A M).
  bool get canUseTemplates =>
      role == UserRole.admin || role == UserRole.muhasebe;

  /// Teklif silme (A O P; muhasebe yok).
  bool get canDeleteOffer =>
      role == UserRole.admin ||
      role == UserRole.ortak ||
      role == UserRole.personel;

  /// Proje silme (`DELETE /projects/:id`: yalnız admin; geri alınamaz).
  bool get canDeleteProject => role == UserRole.admin;

  /// Tekliflerde toplu durum değiştirme (`PATCH /offers/bulk-status`: A M O P).
  bool get canBulkOfferStatus => !isField && caps.offers;

  /// Tekliflerde toplu silme (`DELETE /offers/bulk`: sunucuda A M O P ama admin dışı yalnız kendi
  /// kayıtlarını siler; arayüz tek silmeyle aynı rolleri gösterir: A O P).
  bool get canBulkDeleteOffers => canDeleteOffer;

  /// Proje bilgisi/tutar/tarih/ilave iş düzenleme (A M O P).
  bool get canEditProject => !isField && caps.projects;

  /// Sözleşme/tahsilat/kalan çubukları: saha asla görmez (total_amount yok).
  bool get showProjectMoney => !isField && caps.projects;

  /// Ödeme ve gider SATIRLARI: finans yetkisi gerekir (saha: tümü 403).
  bool get showLedger => !isField && caps.finance;

  /// Paylaşım ekleme/kaldırma bölümü (kaydın sahibi/admin; sunucu ayrıca denetler).
  bool get canShare => !isField;

  /// Kullanıcı listesi (`GET /users`: yalnız A ve O) — paylaşım adayları için.
  bool get canListUsers => role == UserRole.admin || role == UserRole.ortak;

  /// Aşama değiştirme: oturumlu herkes (saha dahil), erişimi olan kayıtta.
  bool get canChangeStage => true;

  /// Görev ekleme/durum: oturumlu herkes (saha dahil).
  bool get canManageTasks => true;
}

final jobsAccessProvider = Provider<JobsAccess>((ref) {
  final caps =
      ref.watch(capabilitiesProvider) ?? AppCapabilities.forRole(UserRole.saha);
  return JobsAccess(caps);
});
