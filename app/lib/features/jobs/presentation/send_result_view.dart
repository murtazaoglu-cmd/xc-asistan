// SAHİBİ: jobs ajanı. Teklif gönderim sonucu: 200 / 207 / 502 DÜRÜSTÇE (kanal + hata).
// "Her zaman gönderildi" göstermek YASAKTIR (araştırma: teklif gönderimi 200'de de hata gizliyordu).
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../data/jobs_models.dart';

enum SendResultAction { retry, whatsapp, openPdf, copyPdf }

class SendResultView extends StatelessWidget {
  const SendResultView({
    super.key,
    required this.result,
    required this.onAction,
    this.hasPhone = true,
  });

  final QuoteSendResult result;
  final ValueChanged<SendResultAction> onAction;

  /// Müşterinin telefonu varsa "WhatsApp'ta kendim gönder" önerilir.
  final bool hasPhone;

  static String titleOf(SendOutcome o) => switch (o) {
    SendOutcome.sent => 'Gönderildi',
    SendOutcome.partial => 'Kısmen gönderildi',
    SendOutcome.failed => 'Gönderilemedi',
  };

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final (IconData icon, Color color) = switch (result.outcome) {
      SendOutcome.sent => (Icons.check_circle, x.success),
      SendOutcome.partial => (Icons.warning_amber_rounded, x.warning),
      SendOutcome.failed => (Icons.error, context.colors.error),
    };
    final rows = <Widget>[
      _ChannelRow(label: 'WhatsApp', channel: result.whatsapp),
      _ChannelRow(label: 'E-posta', channel: result.email),
    ];
    final canWhatsapp =
        result.outcome != SendOutcome.sent &&
        (result.whatsappUrl != null || hasPhone) &&
        !result.whatsapp.sent;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(icon, color: color, size: Sizes.iconLg),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    titleOf(result.outcome),
                    key: const ValueKey('send-result-title'),
                    style: context.text.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(switch (result.outcome) {
            SendOutcome.sent =>
              '${result.sentChannelLabels.join(' ve ')} ile müşteriye gönderildi.',
            SendOutcome.partial =>
              'Yalnız ${result.sentChannelLabels.join(' ve ')} ile gönderildi; '
                  'diğer kanal başarısız oldu.',
            SendOutcome.failed =>
              'Teklif hiçbir kanaldan gönderilemedi. Müşteriye ulaşmadı.',
          }, style: context.text.bodyLarge),
          const SizedBox(height: Space.md),
          ...rows,
          if (result.outcome == SendOutcome.failed &&
              (result.error ?? '').isNotEmpty &&
              !result.whatsapp.failed &&
              !result.email.failed) ...[
            const SizedBox(height: Space.sm),
            Text(
              result.error!,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          if (canWhatsapp)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: x.success,
                foregroundColor: x.onSuccess,
              ),
              onPressed: () => onAction(SendResultAction.whatsapp),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp\'ta kendim göndereyim'),
            ),
          if (result.outcome == SendOutcome.failed) ...[
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: () => onAction(SendResultAction.retry),
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
          if (result.pdfUrl != null) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onAction(SendResultAction.openPdf),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF\'i aç'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onAction(SendResultAction.copyPdf),
                  icon: const Icon(Icons.link),
                  label: const Text('PDF bağlantısını kopyala'),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              'PDF bağlantısı 10 dakika geçerlidir.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.label, required this.channel});
  final String label;
  final ChannelResult channel;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final IconData icon;
    final Color color;
    final String text;
    if (channel.sent) {
      icon = Icons.check_circle_outline;
      color = x.success;
      text = '$label: gönderildi';
    } else if (channel.skipped) {
      icon = Icons.remove_circle_outline;
      color = context.colors.onSurfaceVariant;
      text =
          '$label: atlandı${channel.error == null ? '' : ' (${channel.error})'}';
    } else {
      icon = Icons.cancel_outlined;
      color = context.colors.error;
      text =
          '$label: gönderilemedi${channel.error == null ? '' : ' — ${channel.error}'}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: Sizes.iconSm),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

/// Alt sayfa olarak gösterir; seçilen eylemi döner.
Future<SendResultAction?> showSendResultSheet(
  BuildContext context,
  QuoteSendResult result, {
  bool hasPhone = true,
}) {
  return showModalBottomSheet<SendResultAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SendResultView(
        result: result,
        hasPhone: hasPhone,
        onAction: (a) => Navigator.of(ctx).pop(a),
      ),
    ),
  );
}
