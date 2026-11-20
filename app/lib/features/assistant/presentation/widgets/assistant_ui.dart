// Asistan ekranlarının ortak küçük parçaları ve yardımcıları.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../application/assistant_routes_paths.dart';
import '../../data/insight_models.dart';

String errorText(Object e) => AppException.from(e).message;

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Dış bağlantıyı (tel:, wa.me, geo:) açar; açılamazsa bildirir.
Future<void> openExternalLink(
  WidgetRef ref,
  BuildContext context,
  String? raw,
) async {
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null) {
    toast(context, 'Bağlantı açılamadı.');
    return;
  }
  final ok = await ref.read(linkLauncherProvider).open(uri);
  if (!ok && context.mounted) toast(context, 'Bağlantı açılamadı.');
}

/// Sunucunun `screen` aksiyonundaki ekran adını uygulama rotasına çevirir (bilinmeyen → null).
String? routeForScreen(String? screen) {
  switch (screen) {
    case 'receivables':
    case 'collections':
    case 'finance':
      return Routes.finance;
    case 'closure':
      return AssistantPaths.closure;
    case 'offers':
    case 'jobs':
      return Routes.jobs;
    case 'appointments':
    case 'calendar':
      return Routes.appointments;
    case 'stock':
    case 'materials':
      return Routes.stock;
    case 'reports':
      return Routes.reports;
    case 'insights':
      return AssistantPaths.insights;
    case 'briefing':
      return AssistantPaths.briefing;
    case 'customers':
      return Routes.customers;
    case 'invoices':
    case 'vat':
      return Routes.invoicesVat;
  }
  return null;
}

/// `entity_type` + `id` → ayrıntı rotası (bilinmeyen → null).
String? routeForEntity(String? type, String? id) {
  if (id == null || id.isEmpty) return null;
  switch (type) {
    case 'project':
      return Routes.project(id);
    case 'offer':
      return Routes.offer(id);
    case 'appointment':
      return Routes.appointment(id);
  }
  return null;
}

void goTo(BuildContext context, String? route) {
  if (route == null) {
    toast(context, 'Bu ekran henüz açılamıyor.');
    return;
  }
  context.push(route);
}

/// Müdür etiketi: Uyarı / Fırsat / Bilgi (renk + ikon + metin).
class InsightTagChip extends StatelessWidget {
  const InsightTagChip({super.key, required this.tag, this.critical = false});
  final InsightTag tag;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final (label, icon, bg, fg) = switch (tag) {
      InsightTag.warning => (
        critical ? 'Kritik' : 'Uyarı',
        Icons.warning_amber_rounded,
        critical ? context.colors.errorContainer : x.warningContainer,
        critical ? context.colors.onErrorContainer : x.onWarning,
      ),
      InsightTag.opportunity => (
        'Fırsat',
        Icons.trending_up,
        x.successContainer,
        x.onSuccess == Colors.white ? context.colors.onSurface : x.onSuccess,
      ),
      InsightTag.info => (
        'Bilgi',
        Icons.info_outline,
        x.infoContainer,
        context.colors.onSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: Space.xs),
          Text(label, style: context.text.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// "Yenile" göstergesi olan kaydırılabilir boş/hata gövdesi.
class FillRefresh extends StatelessWidget {
  const FillRefresh({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      PullToRefresh.fill(onRefresh: onRefresh, child: child);
}

/// Bölüm başlığı (küçük).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.text.titleSmall)),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// ≥48 dp dokunma alanlı düz metin düğmesi.
ButtonStyle get touchButtonStyle => TextButton.styleFrom(
  minimumSize: const Size(Sizes.minTouch, Sizes.minTouch),
);

/// Türkçe küçük harfe çevirir (I → ı, İ → i).
String trLower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Baz puan → "%39,8".
String formatBp(int bp) {
  final v = bp / 100;
  final s = v.toStringAsFixed(1).replaceAll('.', ',');
  return '%${s.endsWith(',0') ? s.substring(0, s.length - 2) : s}';
}
