// SAHİBİ: appointments ajanı. Randevu detayı: tüm bilgiler, tek dokunuş durum, ertele,
// telefon/adres eylemleri, düzenle ve sil (+ geri al). Saha yalnız durum/zaman/not değiştirir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../appointments_routes.dart';
import '../application/appointment_providers.dart';
import '../../../core/util/domain_enums.dart';
import '../data/appointment_models.dart';
import 'appointment_ui.dart';

class AppointmentDetailScreen extends ConsumerWidget {
  const AppointmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final caps = ref.watch(capabilitiesProvider);
    final isField = caps?.isField ?? false;
    final value = ref.watch(appointmentDetailProvider(id));
    final hidden = ref.watch(hiddenAppointmentIdsProvider).contains(id);
    // Yenileme sırasında önceki veri korunur (iskelet titremesi olmasın).
    final a = hidden ? null : value.value;

    Future<void> refresh() async {
      ref.invalidate(appointmentDetailProvider(id));
      try {
        await ref.read(appointmentDetailProvider(id).future);
      } catch (_) {}
    }

    return AppScaffold(
      title: '${terms.appointment} detayı',
      showMenuButton: false,
      actions: [
        if (a != null)
          PopupMenuButton<String>(
            tooltip: 'Diğer işlemler',
            onSelected: (v) {
              if (v == 'edit') context.push(AppointmentsRoutes.edit(id));
              if (v == 'delete') {
                AppointmentUi.delete(context, ref, a);
                context.pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                height: Sizes.minTouch,
                child: Text(isField ? 'Not / zaman düzenle' : 'Düzenle'),
              ),
              if (!isField)
                const PopupMenuItem(
                  value: 'delete',
                  height: Sizes.minTouch,
                  child: Text('Sil'),
                ),
            ],
          ),
      ],
      body: a != null
          ? PullToRefresh(
              onRefresh: refresh,
              child: _Body(a: a, isField: isField, caps: caps),
            )
          : hidden
          ? const EmptyState(icon: Icons.delete_outline, title: 'Kayıt silindi')
          : value.hasError
          ? PullToRefresh.fill(
              onRefresh: refresh,
              child: ErrorState(
                error: value.error,
                onRetry: () => ref.invalidate(appointmentDetailProvider(id)),
              ),
            )
          : const SkeletonList(itemCount: 3, itemHeight: 120),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.a, required this.isField, required this.caps});
  final Appointment a;
  final bool isField;
  final AppCapabilities? caps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final name = a.displayName ?? 'İsimsiz kayıt';
    final showJobsLinks = caps?.showJobs ?? false;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      terms.appointmentTypeLabel(a.type),
                      style: context.text.headlineSmall,
                    ),
                  ),
                  StatusChip.appointment(a.status),
                ],
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  const Icon(Icons.event_outlined, size: Sizes.iconSm),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      '${DateText.format(a.scheduledAt, DateTextMode.dateWeekday)}'
                      '  ${DateText.format(a.scheduledAt, DateTextMode.time)}',
                      style: context.text.titleMedium,
                    ),
                  ),
                ],
              ),
              if (a.isOverdue()) ...[
                const SizedBox(height: Space.sm),
                const StatusChip(
                  label: 'Gecikti',
                  tone: StatusTone.danger,
                  icon: Icons.schedule,
                ),
              ],
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  if (a.isOpen) ...[
                    if (AppointmentValues.normalize(a.status) == 'beklemede' &&
                        !isField)
                      OutlinedButton.icon(
                        onPressed: () => AppointmentUi.changeStatus(
                          context,
                          ref,
                          a,
                          AppointmentStatus.confirmed,
                        ),
                        icon: const Icon(
                          Icons.event_available,
                          size: Sizes.iconSm,
                        ),
                        label: const Text('Onayla'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: () => AppointmentUi.changeStatus(
                        context,
                        ref,
                        a,
                        AppointmentStatus.done,
                      ),
                      icon: const Icon(Icons.check, size: Sizes.iconSm),
                      label: const Text('Tamamlandı'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => AppointmentUi.snooze(context, ref, a),
                      icon: const Icon(Icons.update, size: Sizes.iconSm),
                      label: const Text('Ertele'),
                    ),
                    TextButton.icon(
                      onPressed: () => AppointmentUi.changeStatus(
                        context,
                        ref,
                        a,
                        AppointmentStatus.cancelled,
                      ),
                      icon: const Icon(Icons.block, size: Sizes.iconSm),
                      label: const Text('İptal'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.error,
                      ),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: () => AppointmentUi.changeStatus(
                        context,
                        ref,
                        a,
                        AppointmentStatus.pending,
                      ),
                      icon: const Icon(Icons.undo, size: Sizes.iconSm),
                      label: const Text('Yeniden aç'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SectionCard(
          title: terms.customer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: context.text.titleMedium),
              if (a.displayService != null)
                Text(a.displayService!, style: context.text.bodyMedium),
              PhoneActions(phone: a.displayPhone, name: a.displayName),
              PhoneActionButtons(phone: a.displayPhone, name: a.displayName),
              AddressActions(
                address: a.address,
                lat: a.lat,
                lng: a.lng,
                showButton: true,
              ),
              if (a.displayPhone == null && a.address == null && a.lat == null)
                Text(
                  'İletişim bilgisi yok.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Ayrıntılar',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: 'Atanan',
                value: a.assignedUserName ?? 'Atanmamış',
              ),
              if (a.offerId != null)
                _LinkRow(
                  icon: Icons.request_quote_outlined,
                  label: terms.offer,
                  value: a.offerCode ?? 'Bağlı kayıt',
                  onTap: showJobsLinks
                      ? () => context.push(Routes.offer(a.offerId!))
                      : null,
                ),
              if (a.projectId != null)
                _LinkRow(
                  icon: Icons.work_outline,
                  label: terms.job,
                  value: a.projectCode ?? 'Bağlı kayıt',
                  onTap: showJobsLinks
                      ? () => context.push(Routes.project(a.projectId!))
                      : null,
                ),
              _InfoRow(
                icon: Icons.notes_outlined,
                label: 'Not',
                value: a.notes ?? 'Not yok',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: () => context.push(AppointmentsRoutes.edit(a.id)),
          icon: const Icon(Icons.edit_outlined),
          label: Text(isField ? 'Not / zaman düzenle' : 'Düzenle'),
        ),
        if (!isField) ...[
          const SizedBox(height: Space.sm),
          TextButton.icon(
            onPressed: () {
              AppointmentUi.delete(context, ref, a);
              context.pop();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Sil'),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: Sizes.iconSm,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: Space.sm),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.text.bodyLarge)),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return _InfoRow(icon: icon, label: label, value: value);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch),
        child: Row(
          children: [
            Icon(icon, size: Sizes.iconSm, color: context.colors.primary),
            const SizedBox(width: Space.sm),
            SizedBox(
              width: 72,
              child: Text(label, style: context.text.bodyMedium),
            ),
            Expanded(
              child: Text(
                value,
                style: context.text.bodyLarge?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
