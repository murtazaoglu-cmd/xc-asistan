import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/jobs/data/jobs_access.dart';

JobsAccess a(UserRole r) => JobsAccess(AppCapabilities.forRole(r));

void main() {
  test('admin: her şey', () {
    final x = a(UserRole.admin);
    expect(x.canSeeOffers && x.canSeeProjects && x.canPrepareQuote, true);
    expect(x.canUseTemplates && x.canDeleteOffer && x.showLedger, true);
    expect(x.canListUsers && x.showProjectMoney, true);
  });
  test('muhasebe: şablon var, teklif silme yok, defter görür', () {
    final x = a(UserRole.muhasebe);
    expect(x.canUseTemplates, true);
    expect(x.canDeleteOffer, false);
    expect(x.showLedger, true);
    expect(x.canListUsers, false);
  });
  test('ortak: şablon yok, silebilir, kullanıcı listesi var', () {
    final x = a(UserRole.ortak);
    expect(x.canUseTemplates, false);
    expect(x.canDeleteOffer, true);
    expect(x.canListUsers, true);
  });
  test('personel: teklif hazırlayamaz', () {
    final x = a(UserRole.personel);
    expect(x.canPrepareQuote, false);
    expect(x.canSeeOffers && x.canSeeProjects, true);
    expect(x.canUseTemplates, false);
  });
  test('saha: teklif/proje sekmesi, para ve defter yok; görev/aşama var', () {
    final x = a(UserRole.saha);
    expect(x.canSeeOffers, false);
    expect(x.canSeeProjects, false);
    expect(x.showProjectMoney, false);
    expect(x.showLedger, false);
    expect(x.canShare, false);
    expect(x.canEditProject, false);
    expect(x.canChangeStage && x.canManageTasks, true);
  });

  test('proje silme yalnız admin; toplu teklif işlemleri rol tablosu', () {
    for (final r in UserRole.values) {
      expect(a(r).canDeleteProject, r == UserRole.admin, reason: '$r');
    }
    expect(a(UserRole.muhasebe).canBulkOfferStatus, true);
    expect(a(UserRole.muhasebe).canBulkDeleteOffers, false);
    expect(a(UserRole.personel).canBulkDeleteOffers, true);
    expect(a(UserRole.saha).canBulkOfferStatus, false);
    expect(a(UserRole.saha).canBulkDeleteOffers, false);
  });
}
