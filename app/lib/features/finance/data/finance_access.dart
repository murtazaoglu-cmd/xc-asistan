// Rol görünürlüğü (UI gizlemesi; asıl yetki her uçta sunucuda denetlenir).
// saha: finans YOK (tüm uçlar 403). personel: kısıtlı (genel gider/sabit gider/kişisel yok).
import '../../../core/auth/auth_models.dart';

class FinanceAccess {
  const FinanceAccess(this.role, {this.homeFinance = true});

  final UserRole role;

  /// Sunucu `capabilities.homeFinance`: kişisel (ev) giderleri görme/girme.
  final bool homeFinance;

  factory FinanceAccess.of(AppCapabilities caps) =>
      FinanceAccess(caps.role, homeFinance: caps.homeFinance);

  /// Para sekmesini görebilir mi (saha hiçbir finans verisi görmez).
  bool get canView => role != UserRole.saha;

  /// Kısıtlı rol (personel).
  bool get isRestricted => role == UserRole.personel;

  /// Sabit giderler: yalnız A M O.
  bool get canManageRecurring =>
      role == UserRole.admin ||
      role == UserRole.muhasebe ||
      role == UserRole.ortak;

  /// Projeye bağlı olmayan (genel) gider: personel giremez (403).
  bool get canAddGeneralExpense => role != UserRole.personel && canView;

  /// Kişisel (ev) gider kapsamı.
  bool get canUsePersonalScope => canView && homeFinance;
}
