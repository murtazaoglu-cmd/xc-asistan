import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../config/brand_profile.dart';
import '../theme/tokens.dart';
import '../util/phone.dart';
import 'contact_launcher.dart';
import 'ui_providers.dart';

final contactLauncherProvider = Provider<ContactLauncher>(
  (ref) => ContactLauncher(ref.watch(linkLauncherProvider)),
);

/// WhatsApp için hazır ilk mesaj: "Merhaba Ayşe Hanım, X Control Yapı'dan yazıyorum."
String defaultWhatsAppText(String companyName, {String? name}) {
  final who = (name == null || name.trim().isEmpty) ? '' : ' ${name.trim()}';
  return 'Merhaba$who, $companyName olarak yazıyoruz.';
}

/// Telefon numarası: dokununca "Ara / WhatsApp / Kopyala" alt sayfası açar.
/// Varsayılan görünüm biçimlenmiş numara; özel görünüm için [child] verin.
class PhoneActions extends ConsumerWidget {
  const PhoneActions({
    super.key,
    required this.phone,
    this.name,
    this.message,
    this.child,
  });

  final String? phone;
  final String? name;

  /// WhatsApp'a hazır yazılacak metin; verilmezse marka profilinden üretilir.
  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = phone?.trim() ?? '';
    if (p.isEmpty) return child ?? const Text('Telefon yok');
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () => showSheet(context, ref),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child:
              child ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: Sizes.iconSm,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    PhoneUtil.formatDisplay(p),
                    style: context.text.bodyLarge?.copyWith(
                      color: context.colors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Future<void> showSheet(BuildContext context, WidgetRef ref) {
    final launcher = ref.read(contactLauncherProvider);
    final company = ref.read(brandProfileProvider).companyName;
    final text = message ?? defaultWhatsAppText(company, name: name);
    final p = phone!.trim();
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Future<void> run(
          Future<bool> Function() action,
          String failMessage,
        ) async {
          Navigator.of(ctx).pop();
          final ok = await action();
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(failMessage)));
          }
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  0,
                  Space.lg,
                  Space.sm,
                ),
                child: Text(
                  PhoneUtil.formatDisplay(p),
                  style: ctx.text.titleMedium,
                ),
              ),
              ListTile(
                minTileHeight: Sizes.minTouch,
                leading: const Icon(Icons.call),
                title: const Text('Ara'),
                onTap: () =>
                    run(() => launcher.call(p), 'Arama başlatılamadı.'),
              ),
              ListTile(
                minTileHeight: Sizes.minTouch,
                leading: const Icon(Icons.chat),
                title: const Text('WhatsApp ile yaz'),
                onTap: () => run(
                  () => launcher.whatsapp(p, text: text),
                  'WhatsApp açılamadı.',
                ),
              ),
              ListTile(
                minTileHeight: Sizes.minTouch,
                leading: const Icon(Icons.copy),
                title: const Text('Numarayı kopyala'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await launcher.copy(p);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Numara kopyalandı.')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Yan yana "Ara" ve "WhatsApp" düğmeleri (kartlarda 1 dokunuşluk kısayol).
class PhoneActionButtons extends ConsumerWidget {
  const PhoneActionButtons({
    super.key,
    required this.phone,
    this.name,
    this.message,
  });
  final String? phone;
  final String? name;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = phone?.trim() ?? '';
    if (p.isEmpty) return const SizedBox.shrink();
    final launcher = ref.read(contactLauncherProvider);
    final company = ref.read(brandProfileProvider).companyName;
    final text = message ?? defaultWhatsAppText(company, name: name);
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => launcher.call(p),
          icon: const Icon(Icons.call, size: Sizes.iconSm),
          label: const Text('Ara'),
        ),
        OutlinedButton.icon(
          onPressed: () => launcher.whatsapp(p, text: text),
          icon: const Icon(Icons.chat, size: Sizes.iconSm),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }
}
