// Cihaz içi dikte (ücretsiz). speech_to_text benzeri paket pubspec'te YOK; bu yüzden varsayılan
// uygulama "kullanılamıyor"dur ve mikrofon düğmesi klavyedeki dikte düğmesini işaret eder.
// Paket eklendiğinde yalnız bu sağlayıcı override edilir (bkz. docs/CORE-REQUESTS.md).
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class DictationService {
  /// Uygulama içi dikte kullanılabilir mi?
  bool get available;

  /// Konuşmayı dinler ve metne çevirir; iptal/izin yoksa null.
  Future<String?> listen();
}

class NoopDictationService implements DictationService {
  const NoopDictationService();
  @override
  bool get available => false;
  @override
  Future<String?> listen() async => null;
}

final dictationServiceProvider = Provider<DictationService>(
  (ref) => const NoopDictationService(),
);
