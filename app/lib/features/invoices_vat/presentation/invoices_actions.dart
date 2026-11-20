// Ortak eylem sayfaları: "Ödendi işaretle" ve "WhatsApp'ta hatırlat".
// Gönderim her zaman kullanıcının dokunuşuyla (wa.me / uygulama bağlantısı); otomatik gönderim yok.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../../../core/util/phone.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import 'inv_widgets.dart';

// ================================================================ Ödendi işaretle

typedef MarkPaidAction = Future<void> Function(
  String paidAt,
  ScheduleMethod? method,
  bool createPayment,
);

/// Ödendi sayfası. Başarıda true döner. [onConfirm] repository çağrısını yapar.
Future<bool> showMarkPaidSheet(
  BuildContext context, {
  required String title,
  required Money amount,
  required MarkPaidAction onConfirm,
  bool canCreatePayment = false,
  ScheduleMethod? initialMethod,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MarkPaidSheet(
      title: title,
      amount: amount,
      onConfirm: onConfirm,
      canCreatePayment: canCreatePayment,
      initialMethod: initialMethod,
    ),
  );
  return ok ?? false;
}

class _MarkPaidSheet extends StatefulWidget {
  const _MarkPaidSheet({
    required this.title,
    required this.amount,
    required this.onConfirm,
    required this.canCreatePayment,
    this.initialMethod,
  });
  final String title;
  final Money amount;
  final MarkPaidAction onConfirm;
  final bool canCreatePayment;
  final ScheduleMethod? initialMethod;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  late String _date = dayKey(Ist.now());
  late ScheduleMethod? _method = widget.initialMethod;
  late bool _createPayment = widget.canCreatePayment;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(
        _date,
        _method,
        _createPayment && widget.canCreatePayment,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = InvoicesVatErrors.message(e, InvoicesVatOp.markPaid);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ödendi işaretle', style: context.text.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              '${widget.title} · ${widget.amount.format()}',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.lg),
            DayField(
              label: 'Ödeme tarihi',
              value: _date,
              onChanged: (v) => setState(() => _date = v ?? _date),
            ),
            const SizedBox(height: Space.lg),
            Text('Yöntem', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final m in ScheduleMethod.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (s) => setState(() => _method = s ? m : null),
                  ),
              ],
            ),
            if (widget.canCreatePayment)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gerçekleşen ödeme kaydı oluştur'),
                subtitle: const Text(
                  'Para sekmesindeki tahsilatlara da yazılır.',
                ),
                value: _createPayment,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _createPayment = v),
              ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(_error!, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Ödendi olarak işaretle'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ WhatsApp hatırlatma

/// WhatsApp'ta hatırlat: ton seç → şablonu sunucuda doldur → önizle → wa.me aç.
Future<void> showReminderSheet(
  BuildContext context, {
  String? scheduleId,
  String? invoiceId,
  String? projectId,
  String? phone,
  String? name,
  int daysOverdue = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReminderSheet(
      scheduleId: scheduleId,
      invoiceId: invoiceId,
      projectId: projectId,
      phone: phone,
      name: name,
      daysOverdue: daysOverdue,
    ),
  );
}

class ReminderSheet extends ConsumerStatefulWidget {
  const ReminderSheet({
    super.key,
    this.scheduleId,
    this.invoiceId,
    this.projectId,
    this.phone,
    this.name,
    this.daysOverdue = 0,
  });
  final String? scheduleId;
  final String? invoiceId;
  final String? projectId;
  final String? phone;
  final String? name;
  final int daysOverdue;

  @override
  ConsumerState<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends ConsumerState<ReminderSheet> {
  late ReminderTone _tone = ReminderTone.forDaysOverdue(widget.daysOverdue);
  late final TextEditingController _phone = TextEditingController(
    text: widget.phone ?? '',
  );
  RenderedMessage? _msg;
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  MessageTemplate? _pick(List<MessageTemplate> all) {
    for (final t in all) {
      if (t.key == _tone.templateKey) return t;
    }
    for (final t in all) {
      if (t.tone == _tone.api) return t;
    }
    return null;
  }

  Future<void> _render() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(invoicesVatRepositoryProvider);
      final templates = await ref.read(reminderTemplatesProvider.future);
      final t = _pick(templates);
      if (t == null) {
        throw const AppException(
          AppErrorCode.notFound,
          'Bu ton için mesaj şablonu bulunamadı.',
        );
      }
      final phone = _phone.text.trim();
      final m = await repo.renderTemplate(
        t.id,
        scheduleId: widget.scheduleId,
        invoiceId: widget.invoiceId,
        projectId: widget.projectId,
        phone: phone.isEmpty ? null : phone,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _msg = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open() async {
    final m = _msg;
    if (m == null) return;
    final launcher = ref.read(linkLauncherProvider);
    final phone = (m.phone ?? _phone.text).trim();
    var opened = false;
    if (m.urlTooLong) {
      // Metin bağlantıya sığmaz: panoya kopyala, yalnız sohbeti aç.
      await launcher.copy(m.text);
      final web = phone.isEmpty ? null : PhoneUtil.whatsappWebUri(phone);
      if (web != null) opened = await launcher.open(web);
      _toast('Mesaj kopyalandı; sohbete yapıştırın.');
    } else {
      for (final u in [m.whatsappAppUrl, m.whatsappUrl]) {
        final uri = safeWhatsappUri(u);
        if (uri != null && await launcher.open(uri)) {
          opened = true;
          break;
        }
      }
      if (!opened && phone.isNotEmpty) {
        final web = PhoneUtil.whatsappWebUri(phone, text: m.text);
        if (web != null) opened = await launcher.open(web);
      }
    }
    if (!opened && mounted)
      _toast('WhatsApp açılamadı. Mesajı kopyalayıp elle gönderebilirsiniz.');
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final m = _msg;
    final needsPhone =
        m != null && (m.missing.contains('telefon') || (m.phone ?? '').isEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WhatsApp\'ta hatırlat', style: context.text.titleLarge),
            if (widget.name != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(widget.name!, style: context.text.bodyMedium),
              ),
            const SizedBox(height: Space.md),
            Text('Ton', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final t in ReminderTone.values)
                  ChoiceChip(
                    key: Key('tone_${t.api}'),
                    label: Text(t.label),
                    selected: _tone == t,
                    onSelected: (_) {
                      if (_tone == t) return;
                      setState(() => _tone = t);
                      _render();
                    },
                  ),
              ],
            ),
            if (_tone == ReminderTone.kesin)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Kesin ton de saygılı kalmalı: tehdit, aşağılama ya da üçüncü kişilere borç bildirimi yapmayın.',
                  style: context.text.bodySmall,
                ),
              ),
            const SizedBox(height: Space.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                children: [
                  Text(
                    InvoicesVatErrors.message(_error!, InvoicesVatOp.remind),
                    style: TextStyle(color: context.colors.error),
                  ),
                  TextButton.icon(
                    onPressed: _render,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar dene'),
                  ),
                ],
              )
            else if (m != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: SelectableText(m.text, key: const Key('reminder_text')),
              ),
              if (!m.complete && m.missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Eksik bilgi: ${m.missing.join(', ')}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.xc.warning,
                    ),
                  ),
                ),
              for (final w in m.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(w, style: context.text.bodySmall),
                ),
              if (needsPhone) ...[
                const SizedBox(height: Space.md),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefon (WhatsApp)',
                    helperText:
                        'Kayıtlı telefon yok; numarayı girip yenileyin.',
                  ),
                  onSubmitted: (_) => _render(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _render,
                    child: const Text('Mesajı yenile'),
                  ),
                ),
              ],
              const SizedBox(height: Space.md),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(linkLauncherProvider).copy(m.text);
                      _toast('Mesaj kopyalandı.');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopyala'),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('open_whatsapp'),
                      onPressed:
                          (m.whatsappUrl == null &&
                              m.whatsappAppUrl == null &&
                              _phone.text.trim().isEmpty)
                          ? null
                          : _open,
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp\'ta aç'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.md),
            Text(
              'Hatırlatma bilgilendirme amaçlıdır: kampanya/tanıtım eklemeyin. '
              'Mesaj sizin dokunuşunuzla gönderilir; otomatik gönderim yoktur.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yalnız `https://wa.me/...` ve `whatsapp://send...` bağlantıları açılır (sunucudan gelen değere güvenilmez).
Uri? safeWhatsappUri(String? url) {
  if (url == null || url.isEmpty) return null;
  final u = Uri.tryParse(url);
  if (u == null) return null;
  if (u.scheme == 'https' &&
      (u.host == 'wa.me' || u.host == 'api.whatsapp.com'))
    return u;
  if (u.scheme == 'whatsapp') return u;
  return null;
}
