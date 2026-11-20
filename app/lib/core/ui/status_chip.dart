import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../util/domain_enums.dart';

enum StatusTone { success, warning, danger, info, neutral, accent }

/// Durum rozeti: RENK + İKON + YAZI (renk tek başına anlam taşımaz; erişilebilirlik).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  // ---- Sözleşme enum'ları için hazır eşlemeler (tüm ekranlar aynı görünsün) ----

  /// `offers.status`
  factory StatusChip.offer(String? status, {Key? key}) {
    switch (OfferStatus.fromApi(status)) {
      case OfferStatus.yeni:
        return StatusChip(
          key: key,
          label: 'Yeni',
          tone: StatusTone.info,
          icon: Icons.fiber_new,
        );
      case OfferStatus.incelendi:
        return StatusChip(
          key: key,
          label: 'İncelendi',
          tone: StatusTone.neutral,
          icon: Icons.visibility_outlined,
        );
      case OfferStatus.kesifPlanlandi:
        return StatusChip(
          key: key,
          label: 'Keşif Planlandı',
          tone: StatusTone.info,
          icon: Icons.event_outlined,
        );
      case OfferStatus.teklifVerildi:
        return StatusChip(
          key: key,
          label: 'Teklif Verildi',
          tone: StatusTone.warning,
          icon: Icons.hourglass_top,
        );
      case OfferStatus.kabulEdildi:
        return StatusChip(
          key: key,
          label: 'Kabul Edildi',
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case OfferStatus.reddedildi:
        return StatusChip(
          key: key,
          label: 'Reddedildi',
          tone: StatusTone.danger,
          icon: Icons.cancel_outlined,
        );
      case null:
        return StatusChip(key: key, label: status ?? '-');
    }
  }

  /// `projects.stage`
  factory StatusChip.stage(String? stage, {Key? key}) {
    switch (ProjectStage.fromApi(stage)) {
      case ProjectStage.malzemeTemini:
        return StatusChip(
          key: key,
          label: 'Malzeme Temini',
          icon: Icons.inventory_2_outlined,
        );
      case ProjectStage.uretim:
        return StatusChip(
          key: key,
          label: 'Üretim',
          tone: StatusTone.info,
          icon: Icons.build_outlined,
        );
      case ProjectStage.montaj:
        return StatusChip(
          key: key,
          label: 'Montaj',
          tone: StatusTone.info,
          icon: Icons.handyman_outlined,
        );
      case ProjectStage.teslim:
        return StatusChip(
          key: key,
          label: 'Teslim',
          tone: StatusTone.warning,
          icon: Icons.local_shipping_outlined,
        );
      case ProjectStage.tamamlandi:
        return StatusChip(
          key: key,
          label: 'Tamamlandı',
          tone: StatusTone.success,
          icon: Icons.done_all,
        );
      case null:
        return StatusChip(key: key, label: stage ?? '-');
    }
  }

  /// `appointments.status` (serbest metin; bilinmeyen değer nötr rozetle olduğu gibi).
  factory StatusChip.appointment(String? status, {Key? key}) {
    final label = AppointmentValues.statusLabel(status);
    switch (AppointmentValues.normalize(status)) {
      case 'beklemede':
        return StatusChip(
          key: key,
          label: label,
          tone: StatusTone.warning,
          icon: Icons.schedule,
        );
      case 'onaylandi':
        return StatusChip(
          key: key,
          label: label,
          tone: StatusTone.info,
          icon: Icons.event_available,
        );
      case 'tamamlandi':
        return StatusChip(
          key: key,
          label: label,
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case 'iptal':
        return StatusChip(
          key: key,
          label: label,
          tone: StatusTone.danger,
          icon: Icons.block,
        );
      case 'planlandi':
        return StatusChip(
          key: key,
          label: label,
          icon: Icons.event_note_outlined,
        );
      default:
        return StatusChip(key: key, label: label);
    }
  }

  /// `quotes.last_send_status`
  factory StatusChip.send(String? status, {Key? key}) {
    switch (SendStatus.fromApi(status)) {
      case SendStatus.gonderildi:
        return StatusChip(
          key: key,
          label: 'Gönderildi',
          tone: StatusTone.success,
          icon: Icons.mark_email_read_outlined,
        );
      case SendStatus.kismen:
        return StatusChip(
          key: key,
          label: 'Kısmen gönderildi',
          tone: StatusTone.warning,
          icon: Icons.warning_amber,
        );
      case SendStatus.basarisiz:
        return StatusChip(
          key: key,
          label: 'Gönderilemedi',
          tone: StatusTone.danger,
          icon: Icons.error_outline,
        );
      case null:
        return StatusChip(
          key: key,
          label: 'Gönderilmedi',
          icon: Icons.outgoing_mail,
        );
    }
  }

  /// `project_tasks.status` / `reminders.status`
  factory StatusChip.task(String? status, {Key? key}) {
    switch (TaskStatus.fromApi(status)) {
      case TaskStatus.bekliyor:
        return StatusChip(
          key: key,
          label: 'Bekliyor',
          tone: StatusTone.warning,
          icon: Icons.radio_button_unchecked,
        );
      case TaskStatus.devamEdiyor:
        return StatusChip(
          key: key,
          label: 'Devam ediyor',
          tone: StatusTone.info,
          icon: Icons.timelapse,
        );
      case TaskStatus.tamamlandi:
        return StatusChip(
          key: key,
          label: 'Tamamlandı',
          tone: StatusTone.success,
          icon: Icons.check_circle_outline,
        );
      case null:
        return StatusChip(key: key, label: status ?? '-');
    }
  }

  (Color bg, Color fg) _colors(BuildContext context) {
    final c = context.colors;
    final x = context.xc;
    switch (tone) {
      case StatusTone.success:
        return (x.successContainer, x.success);
      case StatusTone.warning:
        return (x.warningContainer, x.warning);
      case StatusTone.danger:
        return (c.errorContainer, c.onErrorContainer);
      case StatusTone.info:
        return (x.infoContainer, x.info);
      case StatusTone.accent:
        return (c.primaryContainer, c.onPrimaryContainer);
      case StatusTone.neutral:
        return (x.neutralContainer, x.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(context);
    return Semantics(
      label: 'Durum: $label',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.chipHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: Space.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
