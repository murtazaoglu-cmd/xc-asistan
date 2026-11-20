import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Form ekranlarının alt eylem çubuğu. [AppScaffold.bottomBar] olarak verilirse
/// klavye açıldığında da görünür kalır (gövde klavyenin üstüne sıkışır).
class BottomSaveBar extends StatelessWidget {
  const BottomSaveBar({
    super.key,
    required this.onSave,
    this.saveLabel = 'Kaydet',
    this.loading = false,
    this.onCancel,
    this.cancelLabel = 'Vazgeç',
  });

  /// null ise düğme pasif (form geçersiz).
  final VoidCallback? onSave;
  final String saveLabel;

  /// Kayıt sürerken düğme pasif ve dönen gösterge görünür (çift gönderim engellenir).
  final bool loading;
  final VoidCallback? onCancel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              if (onCancel != null) ...[
                OutlinedButton(
                  onPressed: loading ? null : onCancel,
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: loading ? null : onSave,
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(saveLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
