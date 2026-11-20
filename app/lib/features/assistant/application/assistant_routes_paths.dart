// Asistan rota yolları (core/router/routes.dart değiştirilemediği için burada). Tek kaynak.
import '../../../core/router/routes.dart';

abstract final class AssistantPaths {
  static const root = Routes.assistant;
  static const briefing = '${Routes.assistant}/briefing';
  static const briefingHistory = '${Routes.assistant}/briefing/history';
  static const briefingView = '${Routes.assistant}/briefing/view';
  static const insights = '${Routes.assistant}/insights';
  static const insightRules = '${Routes.assistant}/insights/rules';
  static const closure = '${Routes.assistant}/closure';
  static const inbox = '${Routes.assistant}/inbox';
  static const prefs = '${Routes.assistant}/prefs';
  static const share = Routes.assistantShare;
  static const importPreview = '${Routes.assistant}/imports/preview';
  static const suggestions = '${Routes.assistant}/suggestions';
  static const consents = '${Routes.assistant}/consents';

  /// Haftalık/aylık rapor listesi: `?type=weekly|monthly`.
  static String reports(String type) => '$briefingHistory?type=$type';

  /// Yazışma öneri listesi. `conversationId` ya da `customerKey` ile süzülür.
  static String suggestionsFor({String? conversationId, String? customerKey}) {
    final q = {
      if (conversationId != null) 'conversation': conversationId,
      if (customerKey != null) 'customer': customerKey,
    };
    return Uri(
      path: suggestions,
      queryParameters: q.isEmpty ? null : q,
    ).toString();
  }

  /// Müşteri kartından "Yazışma ekle": paylaşım ekranı o müşteriye ön ayarlı açılır.
  static String shareForCustomer(String customerKey) =>
      Uri(path: share, queryParameters: {'customer': customerKey}).toString();
}
