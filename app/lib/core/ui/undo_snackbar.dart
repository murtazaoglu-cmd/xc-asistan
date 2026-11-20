import 'package:material_ui/material_ui.dart';

/// "Geri al" düğmeli bildirim (varsayılan 8 sn).
abstract final class UndoSnackbar {
  static const Duration defaultDuration = Duration(seconds: 8);

  /// İşlem ZATEN yapıldı; kullanıcı "Geri al"a basarsa [onUndo] çağrılır
  /// (ör. durum değişimini eski değere yaz).
  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    String undoLabel = 'Geri al',
    Duration duration = defaultDuration,
  }) => showOn(
    ScaffoldMessenger.of(context),
    message: message,
    onUndo: onUndo,
    undoLabel: undoLabel,
    duration: duration,
  );

  /// [show] ile aynı; çağıran widget bu arada ağaçtan çıkabiliyorsa (ör. süzgeçten düşen kart)
  /// önceden alınmış [ScaffoldMessengerState] ile.
  static void showOn(
    ScaffoldMessengerState m, {
    required String message,
    required VoidCallback onUndo,
    String undoLabel = 'Geri al',
    Duration duration = defaultDuration,
  }) {
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        persist: false, // eylemli SnackBar varsayılanda kapanmaz; süre dolunca kapanmalı
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
  }

  /// GECİKMELİ işlem (silme için önerilir): [onCommit] ancak süre dolar ya da bildirim
  /// başka nedenle kapanırsa çalışır; "Geri al"a basılırsa hiç çalışmaz ve [onUndo] çağrılır.
  /// Silme uçları geri alınamaz (sözleşme §14) olduğundan gerçek DELETE bu yolla geciktirilir.
  static Future<void> deferred(
    BuildContext context, {
    required String message,
    required Future<void> Function() onCommit,
    VoidCallback? onUndo,
    String undoLabel = 'Geri al',
    Duration duration = defaultDuration,
  }) async {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    final controller = m.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        persist: false, // eylemli SnackBar varsayılanda kapanmaz; süre dolunca kapanmalı
        action: SnackBarAction(label: undoLabel, onPressed: () {}),
      ),
    );
    final reason = await controller.closed;
    if (reason == SnackBarClosedReason.action) {
      onUndo?.call();
    } else {
      await onCommit();
    }
  }
}
