// SAHİBİ: jobs ajanı. İşler alt rotaları (çekirdek `Routes` dosyasına dokunmadan; kökler Routes.jobs altındadır).
import '../../core/router/routes.dart';

abstract final class JobsPaths {
  static const String newOffer = '${Routes.jobs}/offers/new';
  static const String newProject = '${Routes.jobs}/projects/new';
  static String editOffer(String id) => '${Routes.offer(id)}/edit';
  static String quote(String id) => '${Routes.offer(id)}/quote';

  /// GoRoute göreli yolları (jobs_routes.dart).
  static const String newOfferPattern = 'offers/new';
  static const String newProjectPattern = 'projects/new';
  static const String editPattern = 'edit';
  static const String quotePattern = 'quote';
}
