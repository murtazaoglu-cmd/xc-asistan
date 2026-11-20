// Rol görünürlüğü (UI gizlemesi + rota koruması; asıl yetki her uçta sunucuda denetlenir).
// admin/muhasebe: tam. ortak: yalnız KENDİ defteri, takvimi okur. personel/saha: YOK (403).
import '../../../core/auth/auth_models.dart';

class InvoicesVatAccess {
  const InvoicesVatAccess(this.role);
  final UserRole role;

  factory InvoicesVatAccess.of(AppCapabilities caps) =>
      InvoicesVatAccess(caps.role);

  bool get canView =>
      role == UserRole.admin ||
      role == UserRole.muhasebe ||
      role == UserRole.ortak;

  bool get isFullAccess => role == UserRole.admin || role == UserRole.muhasebe;

  /// Ortak yalnız kendi defterini görür (bilgi şeridi gösterilir).
  bool get ownLedgerOnly => role == UserRole.ortak;

  /// Vergi takvimi öğesi ekle/düzenle/sil: admin/muhasebe (ortak okur).
  bool get canEditTaxCalendar => isFullAccess;

  /// KDV dönemi kilitle/aç, devreden düzelt.
  bool get canLockPeriod => isFullAccess;
}
