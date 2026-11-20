// Bildirim tercihleri (GET/PUT /assistant/prefs): sabah/akşam saati, sessiz saat, günler, açma/kapama.
// `AssistantPrefsSection` Ayarlar ekranına gömülebilir (bkz. docs/CORE-REQUESTS.md).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../data/inbox_models.dart';
import 'widgets/assistant_ui.dart';

class NotificationPrefsScreen extends ConsumerWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Asistan bildirimleri',
      showMenuButton: false,
      body: const AssistantPrefsSection(),
    );
  }
}

/// Ekrana ya da Ayarlar'a gömülebilen tercih gövdesi (kendi kaydırma alanı vardır).
class AssistantPrefsSection extends ConsumerWidget {
  const AssistantPrefsSection({super.key, this.shrinkWrap = false});

  /// true: başka bir kaydırma alanı içinde kullanılır.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assistantPrefsProvider);
    Future<void> refresh() async {
      ref.invalidate(assistantPrefsProvider);
      try {
        await ref.read(assistantPrefsProvider.future);
      } on Object {
        // Hata ekranı gösterilir.
      }
    }

    // shrinkWrap (Ayarlar içine gömülü): sınırsız yükseklikte kaydırmalı durum widget'ları çizilemez;
    // yükleniyor/hata sabit yükseklikte, veri yenilemesiz (sayfanın kendi kaydırması vardır).
    return async.when(
      loading: () => shrinkWrap
          ? const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: SkeletonBox(height: 160, radius: Radii.card),
            )
          : const SkeletonList(itemCount: 5, itemHeight: 56),
      error: (e, _) {
        final err = ErrorState(
          error: e,
          onRetry: () => ref.invalidate(assistantPrefsProvider),
        );
        return shrinkWrap ? SizedBox(height: 260, child: err) : err;
      },
      data: (p) => shrinkWrap
          ? _PrefsList(prefs: p, shrinkWrap: true)
          : PullToRefresh(
              onRefresh: refresh,
              child: _PrefsList(prefs: p, shrinkWrap: false),
            ),
    );
  }
}

class _PrefsList extends ConsumerWidget {
  const _PrefsList({required this.prefs, required this.shrinkWrap});
  final AssistantPrefs prefs;
  final bool shrinkWrap;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> patch,
  ) async {
    try {
      await ref.read(assistantPrefsProvider.notifier).save(patch);
    } on Object catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    String key,
    String current,
  ) async {
    final t = AssistantPrefs.parseTime(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !context.mounted) return;
    await _save(context, ref, {
      key: AssistantPrefs.formatTime(picked.hour, picked.minute),
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = prefs;
    const dayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Asistan bildirimleri'),
          subtitle: const Text(
            'Kapalıysa brifing ve hatırlatmalar yalnız uygulamada görünür.',
          ),
          value: p.enabled,
          onChanged: (v) => _save(context, ref, {'enabled': v}),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sabah brifingi'),
          value: p.morningEnabled,
          onChanged: p.enabled
              ? (v) => _save(context, ref, {'morning_enabled': v})
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: Sizes.minTouch,
          title: const Text('Sabah saati'),
          trailing: Text(p.morningTime, style: context.text.titleMedium),
          enabled: p.enabled && p.morningEnabled,
          onTap: () => _pick(context, ref, 'morning_time', p.morningTime),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Akşam kapanışı'),
          value: p.eveningEnabled,
          onChanged: p.enabled
              ? (v) => _save(context, ref, {'evening_enabled': v})
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: Sizes.minTouch,
          title: const Text('Akşam saati'),
          trailing: Text(p.eveningTime, style: context.text.titleMedium),
          enabled: p.enabled && p.eveningEnabled,
          onTap: () => _pick(context, ref, 'evening_time', p.eveningTime),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sessiz saatler'),
          subtitle: const Text('Bu aralıkta bildirim gönderilmez.'),
          value: p.quietEnabled,
          onChanged: p.enabled
              ? (v) => _save(context, ref, {'quiet_enabled': v})
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: Sizes.minTouch,
          title: const Text('Başlangıç'),
          trailing: Text(p.quietStart, style: context.text.titleMedium),
          enabled: p.enabled && p.quietEnabled,
          onTap: () => _pick(context, ref, 'quiet_start', p.quietStart),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: Sizes.minTouch,
          title: const Text('Bitiş'),
          trailing: Text(p.quietEnd, style: context.text.titleMedium),
          enabled: p.enabled && p.quietEnabled,
          onTap: () => _pick(context, ref, 'quiet_end', p.quietEnd),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Kritik uyarılar sessiz saatte de gelsin'),
          value: p.criticalInQuiet,
          onChanged: p.enabled && p.quietEnabled
              ? (v) => _save(context, ref, {'critical_in_quiet': v})
              : null,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Text('Hangi günler', style: context.text.titleSmall),
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(dayNames[d - 1]),
                selected: p.weekdays.contains(d),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: p.enabled
                    ? (on) {
                        final next = {...p.weekdays};
                        on ? next.add(d) : next.remove(d);
                        if (next.isEmpty) {
                          toast(context, 'En az bir gün seçili olmalı.');
                          return;
                        }
                        _save(context, ref, {
                          'weekdays': (next.toList()..sort()),
                        });
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        OutlinedButton.icon(
          onPressed: () => context.push(AssistantPaths.consents),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Yazışma rızalarım'),
        ),
      ],
    );
  }
}
