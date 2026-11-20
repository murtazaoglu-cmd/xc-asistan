// Hata eşleme (sözleşme B + genel §0): nazik Türkçe mesaj. 5xx ayrıntısı AppException'da maskelidir.
import '../../../core/api/api_exception.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

enum InvoicesVatOp {
  load,
  save,
  delete,
  markPaid,
  upload,
  lock,
  export,
  remind,
  plan,
}

/// 400 `kdv_mismatch`: belgedeki KDV hesaplananla uyuşmuyor; kullanıcı onaylarsa yeniden gönderilir.
class KdvMismatch {
  const KdvMismatch(this.expected);
  final Money? expected;

  static KdvMismatch? of(Object error) {
    if (error is! AppException || error.statusCode != 400) return null;
    final b = asJsonMap(error.body);
    if (b.str('code') != 'kdv_mismatch') return null;
    final k = b.intOrNull('expectedKdvKurus');
    return KdvMismatch(k == null ? null : Money.fromKurus(k));
  }
}

abstract final class InvoicesVatErrors {
  static const String periodLocked =
      'Bu KDV dönemi kilitli. Değişiklik için önce dönemin kilidini açın.';
  static const String forbidden = 'Bu işlem için yetkiniz yok.';
  static const String invalid = 'Geçersiz veya eksik değer girildi.';

  static String? code(Object error) {
    if (error is! AppException) return null;
    return asJsonMap(error.body).str('code');
  }

  static bool isPeriodLocked(Object error) =>
      error is AppException &&
      error.code == AppErrorCode.conflict &&
      code(error) == 'vat_period_locked';

  static String message(Object error, InvoicesVatOp op) {
    if (error is! AppException) return AppException.unknownMessage;
    if (isPeriodLocked(error)) return periodLocked;
    switch (error.code) {
      case AppErrorCode.forbidden:
        return forbidden;
      case AppErrorCode.conflict:
        if (op == InvoicesVatOp.lock) {
          return 'Dönemin durumu bu arada değişmiş. Yenileyip tekrar deneyin.';
        }
        return error.message.isEmpty
            ? 'Bu kayıt başka kayıtlarla ilişkili ya da durumu uygun değil.'
            : error.message;
      case AppErrorCode.validation:
        if (error.statusCode == 413) {
          return 'Dosya çok büyük (en çok 15 MB).';
        }
        return error.message.isEmpty ? invalid : error.message;
      case AppErrorCode.notFound:
        return 'Kayıt bulunamadı. Silinmiş olabilir; listeyi yenileyin.';
      default:
        return error.message;
    }
  }
}
