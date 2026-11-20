// Hata eşleme (sözleşme §0, §5): 403 / 409 / 400 için kullanıcıya nazik Türkçe mesaj.
// 5xx ayrıntısı AppException tarafından zaten maskelenir.
import '../../../core/api/api_exception.dart';

enum FinanceOp {
  savePayment,
  saveExpense,
  saveRecurring,
  applyRecurring,
  delete,
  load,
}

abstract final class FinanceErrors {
  static const String recurringAlreadyApplied =
      'Bu ay zaten eklenmiş. Aynı sabit gider aynı ay için bir kez uygulanır.';
  static const String generalExpenseForbidden =
      'Genel gider ekleme yetkiniz yok. Gideri bir projeye bağlayın.';
  static const String forbidden = 'Bu işlem için yetkiniz yok.';
  static const String invalid = 'Geçersiz veya eksik değer girildi.';

  /// 409 "zaten eklenmiş" bilgi durumudur, hata değildir (arayüz nazik gösterir).
  static bool isAlreadyApplied(Object error) =>
      error is AppException && error.code == AppErrorCode.conflict;

  static String message(Object error, FinanceOp op, {bool hasProject = true}) {
    if (error is! AppException) return AppException.unknownMessage;
    switch (error.code) {
      case AppErrorCode.forbidden:
        if (op == FinanceOp.saveExpense && !hasProject) {
          return generalExpenseForbidden;
        }
        return forbidden;
      case AppErrorCode.conflict:
        if (op == FinanceOp.applyRecurring) return recurringAlreadyApplied;
        return error.message.isEmpty
            ? 'Bu kayıt zaten var ya da başka kayıtlarla ilişkili.'
            : error.message;
      case AppErrorCode.validation:
        return error.message.isEmpty ? invalid : error.message;
      case AppErrorCode.notFound:
        return 'Kayıt bulunamadı. Silinmiş olabilir; listeyi yenileyin.';
      default:
        return error.message;
    }
  }
}
