// SAHİBİ: appointments ajanı. Randevu kartı: Bugün ekranı, Randevular listesi ve Saha ekranı
// aynı kartı kullanır. Kart "aptal"dır: eylemleri çağıran ekran verir (kart yenilemede ölebilir).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/formatters.dart';
import '../data/appointment_models.dart';
import 'appointment_ui.dart';

class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.onTap,
    this.onStatus,
    this.onSnooze,
    this.onPhoto,
    this.showDate = false,
    this.showAssignee = false,
    this.showContactActions = true,
  });

  final Appointment appointment;
  final VoidCallback? onTap;

  /// Verilirse "Tamamlandı / Ertele / İptal" (kapalıysa "Yeniden aç") satırı çıkar.
  final void Function(Appointment a, String status)? onStatus;
  final void Function(Appointment a)? onSnooze;

  /// Saha: "Fotoğraf" eylemi (randevunun teklif/projesine yükler).
  final void Function(Appointment a)? onPhoto;
  final bool showDate;
  final bool showAssignee;
  final bool showContactActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final terms = ref.watch(brandProfileProvider).terms;
    final name = a.displayName ?? 'İsimsiz kayıt';
    final overdue = a.isOverdue();
    final subtitleParts = <String>[
      if (a.displayService != null) a.displayService!,
      if (showAssignee && a.assignedUserName != null) a.assignedUserName!,
      if (a.offerCode != null) a.offerCode!,
      if (a.projectCode != null) a.projectCode!,
    ];
    final label =
        '${terms.appointmentTypeLabel(a.type)}, $name, '
        '${DateText.format(a.scheduledAt, showDate ? DateTextMode.relativeDateTime : DateTextMode.time)}, '
        '${AppointmentValues.statusLabel(a.status)}';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DateText(
                          a.scheduledAt,
                          mode: DateTextMode.time,
                          style: context.text.titleLarge,
                        ),
                        if (showDate && a.scheduledAt != null)
                          Text(
                            Fmt.relativeDate(a.scheduledAt!),
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(width: Space.md),
                    // Uzun metin/büyük yazı ölçeğinde taşmasın: rozetler başlığın altında sarılır.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${terms.appointmentTypeLabel(a.type)} · $name',
                            style: context.text.titleMedium,
                          ),
                          if (subtitleParts.isNotEmpty)
                            Text(
                              subtitleParts.join(' · '),
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: Space.xs),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.xs,
                            children: [
                              StatusChip.appointment(a.status),
                              if (overdue)
                                const StatusChip(
                                  label: 'Gecikti',
                                  tone: StatusTone.danger,
                                  icon: Icons.schedule,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (a.notes != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    a.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium,
                  ),
                ],
                if (showContactActions) ...[
                  AddressActions(
                    address: a.address,
                    lat: a.lat,
                    lng: a.lng,
                    showButton: true,
                  ),
                  PhoneActionButtons(
                    phone: a.displayPhone,
                    name: a.displayName,
                  ),
                ],
                if (onStatus != null || onPhoto != null)
                  _ActionRow(
                    a: a,
                    onStatus: onStatus,
                    onSnooze: onSnooze,
                    onPhoto: onPhoto,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.a,
    this.onStatus,
    this.onSnooze,
    this.onPhoto,
  });
  final Appointment a;
  final void Function(Appointment a, String status)? onStatus;
  final void Function(Appointment a)? onSnooze;
  final void Function(Appointment a)? onPhoto;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (onStatus != null) {
      if (a.isOpen) {
        children.add(
          FilledButton.tonalIcon(
            onPressed: () => onStatus!(a, AppointmentStatus.done),
            icon: const Icon(Icons.check, size: Sizes.iconSm),
            label: const Text('Tamamlandı'),
          ),
        );
        if (onSnooze != null) {
          children.add(
            OutlinedButton.icon(
              onPressed: () => onSnooze!(a),
              icon: const Icon(Icons.update, size: Sizes.iconSm),
              label: const Text('Ertele'),
            ),
          );
        }
        children.add(
          TextButton.icon(
            onPressed: () => onStatus!(a, AppointmentStatus.cancelled),
            icon: const Icon(Icons.block, size: Sizes.iconSm),
            label: const Text('İptal'),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
          ),
        );
      } else {
        children.add(
          OutlinedButton.icon(
            onPressed: () => onStatus!(a, AppointmentStatus.pending),
            icon: const Icon(Icons.undo, size: Sizes.iconSm),
            label: const Text('Yeniden aç'),
          ),
        );
      }
    }
    if (onPhoto != null && a.hasLink) {
      children.add(
        OutlinedButton.icon(
          onPressed: () => onPhoto!(a),
          icon: const Icon(Icons.photo_camera_outlined, size: Sizes.iconSm),
          label: const Text('Fotoğraf'),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// Zaman bilgisini gün başlığı olarak yazar: "Bugün — Cuma 20 Kasım".
String dayHeadingText(DateTime day) {
  final rel = Ist.relativeDayLabel(day);
  final h = Fmt.dayHeading(day);
  return rel == null ? h : '$rel — $h';
}
