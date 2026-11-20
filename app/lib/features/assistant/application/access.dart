// Rol görünürlüğü: asistan ekranlarında neyin gösterileceği TEK yerden. Sunucu her uçta yine denetler.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../data/briefing_models.dart';

class AssistantAccess {
  const AssistantAccess(this.role);
  final UserRole role;

  /// En kısıtlı varsayılan: saha.
  static const AssistantAccess field = AssistantAccess(UserRole.saha);

  bool get isField => role == UserRole.saha;

  /// Finans verisi (para özeti, tahsilat, tutarlar): admin, muhasebe, ortak.
  bool get showFinance =>
      role == UserRole.admin ||
      role == UserRole.muhasebe ||
      role == UserRole.ortak;

  /// Müdür önerileri ve haftalık/aylık rapor: admin, muhasebe, ortak (personel/saha 403).
  bool get showManager => showFinance;

  /// Müdür kuralları (eşik/aç-kapa): yalnız admin.
  bool get canEditRules => role == UserRole.admin;

  /// Yazışma içe aktarma: saha hariç.
  bool get canImport => !isField;

  /// Yeni teklif / stok blokları: saha hariç (saha sade brifing görür).
  bool get showSales => !isField;
}

final assistantAccessProvider = Provider<AssistantAccess>((ref) {
  final caps = ref.watch(capabilitiesProvider);
  return caps == null ? AssistantAccess.field : AssistantAccess(caps.role);
});

/// Brifing bloğu rol süzgeci (sunucu zaten süzer; istemci ikinci savunma katmanıdır).
/// Saha: para/tahsilat/teklif/stok/dikkat/soru YOK. Personel: para ve tahsilat YOK, müdür maddeleri YOK.
List<BriefingBlock> visibleBlocks(Briefing b, AssistantAccess a) {
  final out = <BriefingBlock>[];
  for (final blk in b.blocks) {
    if (!a.showFinance && BriefingBlock.financeTypes.contains(blk.type))
      continue;
    if (a.isField &&
        (BriefingBlock.managerTypes.contains(blk.type) ||
            BriefingBlock.salesTypes.contains(blk.type))) {
      continue;
    }
    if (!a.showFinance && blk.type == 'question') continue;
    if (blk.type == 'attention' && !a.showManager) {
      final simple = [
        for (final i in blk.items)
          if (i['insight_id'] == null) i,
      ];
      if (simple.isEmpty) continue;
      out.add(
        BriefingBlock(
          id: blk.id,
          type: blk.type,
          title: blk.title,
          count: simple.length,
          raw: {...blk.raw, 'items': simple, 'count': simple.length},
        ),
      );
      continue;
    }
    out.add(blk);
  }
  return out;
}
