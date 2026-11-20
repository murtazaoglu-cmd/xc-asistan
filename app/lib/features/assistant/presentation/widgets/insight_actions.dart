// Müdür önerisi aksiyonları: Hatırlat / Ara / WhatsApp taslağı / Randevu ekle / Aç.
// WhatsApp mesajı OTOMATİK GÖNDERİLMEZ: şablon çözülür, wa.me ile sohbet metin dolu açılır;
// göndermeyi kullanıcı kendi elleriyle yapar (sözleşme B, tasarım 2.5).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/util/json.dart';
import '../../data/assistant_repository.dart';
import '../../data/import_models.dart';
import '../../data/insight_models.dart';
import 'assistant_ui.dart';

IconData insightActionIcon(InsightActionType t) => switch (t) {
  InsightActionType.call => Icons.call_outlined,
  InsightActionType.callList => Icons.contacts_outlined,
  InsightActionType.whatsappTemplate => Icons.chat_outlined,
  InsightActionType.reminderCreate => Icons.alarm_add_outlined,
  InsightActionType.appointmentCreate => Icons.event_available_outlined,
  InsightActionType.open => Icons.open_in_new,
  InsightActionType.screen => Icons.open_in_new,
  InsightActionType.unknown => Icons.circle_outlined,
};

/// Randevu ekle: ilgili forma metin yoluyla gider (appointments modülü içe aktarılmaz).
String appointmentFormPath(InsightAction a, Insight insight) {
  final b = a.body;
  final q = <String, String>{
    if (b.strOrNull('customerName') ?? b.strOrNull('customer_name')
        case final v?)
      'customerName': v,
    if (b.strOrNull('customerPhone') ?? b.strOrNull('customer_phone')
        case final v?)
      'customerPhone': v,
    if (b.strOrNull('type') case final v?) 'type': v,
    if (b.strOrNull('offer_id') ??
            (insight.entityType == 'offer' ? insight.entityId : null)
        case final v?)
      'offerId': v,
    if (b.strOrNull('project_id') ??
            (insight.entityType == 'project' ? insight.entityId : null)
        case final v?)
      'projectId': v,
    if (b.strOrNull('address') case final v?) 'address': v,
    if (a.suggestedDates.isNotEmpty) 'day': a.suggestedDates.first,
  };
  return Uri(
    path: '${Routes.appointments}/new',
    queryParameters: q.isEmpty ? null : q,
  ).toString();
}

Future<void> runInsightAction(
  BuildContext context,
  WidgetRef ref,
  Insight insight,
  InsightAction a,
) async {
  switch (a.type) {
    case InsightActionType.call:
      final tel = a.telUri ?? (a.phone == null ? null : 'tel:${a.phone}');
      await openExternalLink(ref, context, tel);
    case InsightActionType.whatsappTemplate:
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => WhatsAppDraftSheet(insight: insight, action: a),
      );
    case InsightActionType.reminderCreate:
      final ep = a.endpoint;
      final path = ep.strOr('path', '/reminders');
      try {
        await ref
            .read(assistantRepositoryProvider)
            .callApply(ep.strOr('method', 'POST'), path, a.body);
        if (context.mounted) toast(context, 'Hatırlatma eklendi.');
      } on Object catch (e) {
        if (context.mounted) toast(context, errorText(e));
      }
    case InsightActionType.appointmentCreate:
      goTo(context, appointmentFormPath(a, insight));
    case InsightActionType.callList:
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _CallListSheet(action: a),
      );
    case InsightActionType.open:
      goTo(context, routeForEntity(a.entityType, a.id));
    case InsightActionType.screen:
      goTo(context, routeForScreen(a.screen));
    case InsightActionType.unknown:
      break;
  }
}

/// WhatsApp taslağı: şablon çözülür (yoksa sunucunun hazır metni), düzenlenir, wa.me ile açılır.
class WhatsAppDraftSheet extends ConsumerStatefulWidget {
  const WhatsAppDraftSheet({
    super.key,
    required this.insight,
    required this.action,
  });
  final Insight insight;
  final InsightAction action;

  @override
  ConsumerState<WhatsAppDraftSheet> createState() => _WhatsAppDraftSheetState();
}

class _WhatsAppDraftSheetState extends ConsumerState<WhatsAppDraftSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.action.text ?? '',
  );
  RenderedMessage? _rendered;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    final code = widget.action.templateCode;
    RenderedMessage? r;
    if (code != null) {
      final i = widget.insight;
      try {
        r = await ref
            .read(assistantRepositoryProvider)
            .renderTemplate(
              code,
              offerId: i.entityType == 'offer' ? i.entityId : null,
              projectId: i.entityType == 'project' ? i.entityId : null,
              phone: widget.action.phone,
            );
      } on Object {
        r = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _rendered = r;
      _loading = false;
      // Çözülen metin eksiksizse hazır metnin yerine geçer.
      if (r != null && r.complete && r.text.isNotEmpty) _text.text = r.text;
    });
  }

  Future<void> _open() async {
    final text = _text.text.trim();
    final phone = widget.action.phone ?? _rendered?.phone;
    if (phone != null && phone.isNotEmpty) {
      final ok = await ref
          .read(contactLauncherProvider)
          .whatsapp(phone, text: text);
      if (!ok && mounted) toast(context, 'WhatsApp açılamadı.');
      if (ok && mounted) Navigator.of(context).pop();
      return;
    }
    final url = _rendered?.whatsappUrl ?? widget.action.url;
    await openExternalLink(ref, context, url);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final missing = _rendered?.missing ?? const [];
    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WhatsApp taslağı', style: context.text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Mesaj otomatik gönderilmez. WhatsApp açılır, metni kontrol edip gönder düğmesine siz basarsınız.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.md),
            if (_loading) const LinearProgressIndicator(),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Mesaj'),
            ),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Doldurulamayan alanlar: ${missing.join(', ')}. Göndermeden önce düzenleyin.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.xc.warning,
                  ),
                ),
              ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(contactLauncherProvider).copy(_text.text);
                    if (context.mounted) toast(context, 'Metin kopyalandı.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Kopyala'),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _text.text.trim().isEmpty && widget.action.url == null
                        ? null
                        : _open,
                    icon: const Icon(Icons.chat),
                    label: const Text("WhatsApp'ta aç"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallListSheet extends ConsumerWidget {
  const _CallListSheet({required this.action});
  final InsightAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = action.items;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.label.isEmpty ? 'Arama listesi' : action.label,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final it in items)
                    ListTile(
                      title: Text(it.strOr('name')),
                      subtitle: it['age_days'] == null
                          ? null
                          : Text('${it.intOr('age_days')} gündür bekliyor'),
                      trailing: IconButton(
                        tooltip: 'Ara',
                        icon: const Icon(Icons.call_outlined),
                        onPressed: () => openExternalLink(
                          ref,
                          context,
                          it.strOrNull('tel_uri') ??
                              (it.strOrNull('phone') == null
                                  ? null
                                  : 'tel:${it.strOr('phone')}'),
                        ),
                      ),
                    ),
                  if (items.isEmpty) const ListTile(title: Text('Liste boş.')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
