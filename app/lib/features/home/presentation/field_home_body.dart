// SAHİBİ: home ajanı. SAHA (rol) için sade Bugün ekranı (tasarım: 15 Saha Ekranı): lacivert zemin,
// büyük düğmeler (Bugünkü işler / Randevular / Konum-Yol tarifi / Fotoğraf yükle / İş tamamla) ve
// bugünkü iş kartları. Finans ve teklif bilgisi HİÇ çizilmez.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/dates.dart';
import '../../appointments/data/tr_text.dart';
import '../../appointments/presentation/appointment_card.dart';
import '../../appointments/presentation/appointment_ui.dart';
import '../../assistant/assistant_public.dart' show AssistantPaths;
import '../data/home_insights.dart';
import '../data/home_models.dart';
import 'field_actions.dart';
import 'widgets/home_sections.dart';

class FieldHomeBody extends ConsumerStatefulWidget {
  const FieldHomeBody({
    super.key,
    required this.summary,
    required this.updatedAt,
    this.banner,
  });
  final HomeSummary summary;
  final DateTime updatedAt;
  final Widget? banner;

  @override
  ConsumerState<FieldHomeBody> createState() => _FieldHomeBodyState();
}

class _FieldHomeBodyState extends ConsumerState<FieldHomeBody> {
  final _listKey = GlobalKey();

  void _scrollToJobs() {
    final c = _listKey.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(
        c,
        duration: Motion.normal,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final s = widget.summary;
    final x = context.xc;
    final jobs = fieldJobs(s);
    final open = jobs.where((a) => a.isOpen).length;
    final upcoming = s.tomorrow.where((a) => !a.isCancelled).length;
    final now = Ist.now();
    String typeLabel(String t) => terms.appointmentTypeLabel(t);

    return ColoredBox(
      color: x.navy,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: [
          if (widget.banner != null) ...[
            widget.banner!,
            const SizedBox(height: Space.md),
          ],
          Text(
            s.userName.isEmpty ? greetingFor(now) : 'Merhaba, ${s.userName}',
            style: context.text.headlineSmall?.copyWith(color: x.onNavy),
          ),
          Text(
            jobs.isEmpty
                ? 'Bugün ${trLower(terms.job)} yok.'
                : 'Bugün ${jobs.length} ${trLower(terms.job)} var'
                      '${open != jobs.length ? ' ($open açık)' : ''}.',
            style: context.text.bodyLarge?.copyWith(color: x.onNavy),
          ),
          const SizedBox(height: Space.lg),
          _FieldButton(
            icon: Icons.calendar_today_outlined,
            label: 'Bugünkü ${trLower(terms.jobs)}',
            badge: '${jobs.length}',
            primary: true,
            onTap: _scrollToJobs,
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: _FieldButton(
                  icon: Icons.event_outlined,
                  label: terms.appointments,
                  badge: upcoming > 0 ? '+$upcoming yarın' : null,
                  onTap: () => context.go(Routes.appointments),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _FieldButton(
                  icon: Icons.place_outlined,
                  label: 'Konum / Yol tarifi',
                  onTap: () =>
                      FieldActions.directions(context, ref, jobs, typeLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: _FieldButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Fotoğraf yükle',
                  onTap: () =>
                      FieldActions.uploadPhoto(context, ref, jobs, typeLabel),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _FieldButton(
                  icon: Icons.task_alt,
                  label: 'İş tamamla',
                  onTap: () =>
                      FieldActions.complete(context, ref, jobs, typeLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          _FieldButton(
            icon: Icons.auto_awesome_outlined,
            label: 'Günün brifingi',
            onTap: () => context.push(AssistantPaths.briefing),
          ),
          const SizedBox(height: Space.xl),
          Text(
            'Bugünkü ${trLower(terms.jobs)}',
            key: _listKey,
            style: context.text.titleMedium?.copyWith(color: x.onNavy),
          ),
          const SizedBox(height: Space.sm),
          if (jobs.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  children: [
                    const Icon(Icons.wb_sunny_outlined),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        'Bugün size atanmış ${trLower(terms.appointment)} görünmüyor.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final a in jobs) ...[
              AppointmentCard(
                key: ValueKey(a.id),
                appointment: a,
                onTap: () => context.push(Routes.appointment(a.id)),
                onStatus: (j, st) =>
                    AppointmentUi.changeStatus(context, ref, j, st),
                onSnooze: (j) => AppointmentUi.snooze(context, ref, j),
                onPhoto: (j) => FieldActions.uploadPhoto(
                  context,
                  ref,
                  jobs,
                  typeLabel,
                  target: j,
                ),
              ),
              const SizedBox(height: Space.md),
            ],
          if (s.reminderCount > 0) ...[
            const SizedBox(height: Space.sm),
            RemindersSection(summary: s),
          ],
        ],
      ),
    );
  }
}

/// Büyük saha düğmesi (≥72 dp yükseklik, ikon + etiket + isteğe bağlı rozet).
class _FieldButton extends StatelessWidget {
  const _FieldButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final String? badge;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final bg = primary ? context.colors.primary : x.navySecondary;
    final fg = primary ? context.colors.onPrimary : x.onNavy;
    return Semantics(
      button: true,
      label: badge == null ? label : '$label, $badge',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                mainAxisAlignment: primary
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: Sizes.iconLg),
                  const SizedBox(width: Space.md),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          if (badge != null) TextSpan(text: '  $badge'),
                        ],
                      ),
                      style: context.text.titleMedium?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
