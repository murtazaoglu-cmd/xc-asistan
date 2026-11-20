// Hazır metinler (marka adı BrandProfile'dan gelir; sektör terimi yok).
import '../../../core/util/money.dart';

abstract final class ReminderMessage {
  /// Nazik tahsilat hatırlatması (WhatsApp). [company] `BrandProfile.companyName`.
  static String build({
    required String company,
    required String customer,
    required Money remaining,
    String? projectCode,
  }) {
    final who = customer.trim().isEmpty ? '' : ' ${customer.trim()}';
    final code = (projectCode ?? '').trim();
    final job = code.isEmpty ? 'işimize' : '$code numaralı işimize';
    return 'Merhaba$who, $company olarak yazıyoruz. $job ait '
        '${remaining.format()} tutarında kalan bakiye görünüyor. '
        'Müsait olduğunuzda ödemeyi yapabilirseniz çok seviniriz. '
        'İlginiz için teşekkür ederiz.';
  }
}
