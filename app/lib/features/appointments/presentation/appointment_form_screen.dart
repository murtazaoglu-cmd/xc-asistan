// SAHİBİ: appointments ajanı. Randevu ekle/düzenle formu.
//  - Yönetici/personel: tür, kime (teklif/proje/müşteri araması), gün+saat çipleri, atanan, adres, not.
//  - Saha (restricted): yalnız durum, zaman ve not (sözleşme §9: diğer alanlar 403).
//  - Çakışma uyarısı (aynı kişi ±60 dk), klavye uyumu (BottomSaveBar gövdeyle birlikte yükselir),
//    kaydedilmemiş değişiklik koruması, 400/409/403 sunucu mesajları.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/formatters.dart';
import '../application/appointment_providers.dart';
import '../data/appointment_logic.dart';
import '../data/appointment_models.dart';
import '../data/tr_text.dart';
import 'appointment_ui.dart';
import 'link_picker_sheet.dart';

/// Yeni randevu formunun önceden doldurulacak alanları (rota sorgu parametrelerinden).
@immutable
class AppointmentPrefill {
  const AppointmentPrefill({
    this.day,
    this.offerId,
    this.projectId,
    this.customerName,
    this.customerPhone,
    this.address,
    this.type,
  });
  final DateTime? day;
  final String? offerId;
  final String? projectId;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final String? type;
}

class AppointmentFormScreen extends ConsumerStatefulWidget {
  const AppointmentFormScreen({super.key, this.editId, this.prefill});

  /// Doluysa düzenleme; boşsa yeni kayıt.
  final String? editId;
  final AppointmentPrefill? prefill;

  @override
  ConsumerState<AppointmentFormScreen> createState() =>
      _AppointmentFormScreenState();
}

const List<(int, int)> _quickTimes = [
  (9, 0),
  (10, 0),
  (11, 0),
  (13, 0),
  (14, 0),
  (16, 0),
];

class _AppointmentFormScreenState extends ConsumerState<AppointmentFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  Appointment? _original;
  bool _initialized = false;
  bool _dirty = false;
  bool _submitted = false;
  bool _saving = false;
  bool _saved = false;
  String? _serverError;

  String _type = '';
  String _status = '';
  DateTime? _at;
  String? _assigneeId;
  String? _offerId;
  String? _projectId;
  String? _linkLabel;
  String? _derivedName;
  String? _derivedPhone;
  String? _derivedAddress;

  bool get _isEdit => widget.editId != null;
  bool get _restricted => ref.read(capabilitiesProvider)?.isField ?? false;
  bool get _hasLink => _offerId != null || _projectId != null;

  @override
  void initState() {
    super.initState();
    if (!_isEdit) _initCreate();
    for (final c in [_name, _phone, _address, _notes]) {
      c.addListener(_touch);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (_initialized && !_dirty) _dirty = true;
  }

  void _initCreate() {
    final p = widget.prefill;
    final user = ref.read(currentUserProvider);
    _assigneeId = user?.id;
    _type = p?.type ?? '';
    if (p?.day != null) {
      final w = Ist.wall(p!.day!);
      // Gün verildiyse ve saat bilgisi yoksa (gün başlangıcı) 09:00 öner.
      _at = (w.hour == 0 && w.minute == 0)
          ? Ist.fromWall(w.year, w.month, w.day, 9)
          : Ist.fromWall(w.year, w.month, w.day, w.hour, w.minute);
    }
    _offerId = p?.offerId;
    _projectId = p?.projectId;
    final terms = ref.read(brandProfileProvider).terms;
    if (_offerId != null) _linkLabel = 'Seçili ${trLower(terms.offer)}';
    if (_projectId != null) _linkLabel = 'Seçili ${trLower(terms.job)}';
    _name.text = p?.customerName ?? '';
    _phone.text = p?.customerPhone ?? '';
    _address.text = p?.address ?? '';
    _initialized = true;
  }

  void _initEdit(Appointment a) {
    _original = a;
    _type = a.type;
    _status = a.status;
    _at = a.scheduledAt;
    _assigneeId = a.assignedUserId;
    _offerId = a.offerId;
    _projectId = a.projectId;
    final parts = <String>[
      if (a.offerCode != null) a.offerCode!,
      if (a.projectCode != null) a.projectCode!,
    ];
    _linkLabel = parts.isEmpty ? null : parts.join(' · ');
    _name.text = a.displayName ?? '';
    _phone.text = a.displayPhone ?? '';
    _address.text = a.address ?? '';
    _notes.text = a.notes ?? '';
    _initialized = true;
    _dirty = false;
  }

  void _set(VoidCallback fn) {
    setState(() {
      fn();
      _dirty = true;
      _serverError = null;
    });
  }

  // ---------------- zaman ----------------

  DateTime _withDay(DateTime day) {
    final cur = _at == null ? null : Ist.wall(_at!);
    final d = Ist.wall(day);
    return Ist.fromWall(
      d.year,
      d.month,
      d.day,
      cur?.hour ?? 9,
      cur?.minute ?? 0,
    );
  }

  DateTime _withTime(int h, int m) {
    final base = Ist.wall(_at ?? Ist.now());
    return Ist.fromWall(base.year, base.month, base.day, h, m);
  }

  Future<void> _pickDay() async {
    final d = await AppointmentUi.pickDate(context, initial: _at);
    if (d != null) _set(() => _at = _withDay(d));
  }

  Future<void> _pickTime() async {
    final w = Ist.wall(_at ?? Ist.now());
    final t = await AppointmentUi.pickTime(
      context,
      hour: _at == null ? 9 : w.hour,
      minute: _at == null ? 0 : w.minute,
    );
    if (t != null) _set(() => _at = _withTime(t.hour, t.minute));
  }

  // ---------------- bağlantı ----------------

  Future<void> _pickLink() async {
    final c = await LinkPickerSheet.show(context);
    if (c == null) return;
    _set(() {
      switch (c.kind) {
        case LinkKind.offer:
          _offerId = c.id;
          _projectId = null;
        case LinkKind.project:
          _projectId = c.id;
          _offerId = null;
        case LinkKind.customer:
          _offerId = null;
          _projectId = null;
      }
      _linkLabel = c.title;
      _derivedName = c.title;
      _derivedPhone = c.phone;
      _derivedAddress = c.address;
      _name.text = c.title;
      _phone.text = c.phone ?? '';
      _address.text = c.address ?? '';
    });
  }

  void _clearLink() => _set(() {
    _offerId = null;
    _projectId = null;
    _linkLabel = null;
    _derivedName = _derivedPhone = _derivedAddress = null;
  });

  // ---------------- doğrulama + kayıt ----------------

  AppointmentFormErrors _validate() => validateAppointmentForm(
    type: _type,
    scheduledAt: _at,
    hasLink: _hasLink,
    customerName: _name.text,
    customerPhone: _phone.text,
    address: _address.text,
    notes: _notes.text,
    restricted: _restricted,
  );

  AppointmentDraft _draft() {
    String? send(String text, String? derived) {
      final t = text.trim();
      if (t.isEmpty) return null;
      // Yeni kayıtta bağlantıdan gelen değer tekrar gönderilmez (sunucu çözümler).
      if (!_isEdit && _hasLink && t == derived) return null;
      return t;
    }

    return AppointmentDraft(
      type: _type,
      scheduledAt: _at!,
      notes: _notes.text,
      offerId: _offerId,
      projectId: _projectId,
      assignedUserId: _assigneeId,
      customerName: send(_name.text, _derivedName),
      customerPhone: send(_phone.text, _derivedPhone),
      address: send(_address.text, _derivedAddress),
    );
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    final errors = _validate();
    if (!errors.isValid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Eksik ya da hatalı alanları düzeltin.'),
          ),
        );
      return;
    }
    setState(() => _saving = true);
    final actions = ref.read(appointmentActionsProvider);
    final terms = ref.read(brandProfileProvider).terms;
    try {
      if (_isEdit) {
        final o = _original!;
        final Map<String, dynamic> body;
        if (_restricted) {
          body = {
            if (_status.isNotEmpty && _status != o.status) 'status': _status,
            if (_at != o.scheduledAt) 'scheduled_at': Ist.toApiIso(_at!),
            if ((_notes.text.trim().isEmpty ? null : _notes.text.trim()) !=
                o.notes)
              'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          };
        } else {
          body = _draft().toPatchJson(o);
          if (_status.isNotEmpty && _status != o.status)
            body['status'] = _status;
        }
        if (body.isNotEmpty) await actions.patch(o.id, body);
        if (!mounted) return;
        _saved = true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
        context.pop();
      } else {
        final created = await actions.create(_draft());
        if (!mounted) return;
        _saved = true;
        UndoSnackbar.show(
          context,
          message: '${terms.appointment} eklendi.',
          onUndo: () => actions.delete(created.id).catchError((Object _) {}),
        );
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      setState(() {
        _saving = false;
        _serverError = switch (ex.code) {
          AppErrorCode.conflict => 'Çakışma: ${ex.message}',
          _ => ex.message,
        };
      });
    }
  }

  Future<bool> _confirmDiscard() => ConfirmDialog.show(
    context,
    title: 'Değişiklikler kaydedilmedi',
    message: 'Çıkarsanız girdiğiniz bilgiler kaybolur.',
    confirmLabel: 'Çık',
    cancelLabel: 'Kal',
    destructive: true,
  );

  // ---------------- arayüz ----------------

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    if (!_isEdit && _restricted) {
      return AppScaffold(
        title: 'Yeni ${trLower(terms.appointment)}',
        showMenuButton: false,
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu işlem için yetkiniz yok',
          message:
              '${terms.appointments} yöneticiniz tarafından eklenir; siz durumunu güncelleyebilirsiniz.',
        ),
      );
    }
    if (_isEdit && !_initialized) {
      final v = ref.watch(appointmentDetailProvider(widget.editId!));
      final a = v.value;
      if (a != null) {
        _initEdit(a);
      } else {
        return AppScaffold(
          title: '${terms.appointment} düzenle',
          showMenuButton: false,
          body: v.hasError
              ? ErrorState(
                  error: v.error,
                  onRetry: () =>
                      ref.invalidate(appointmentDetailProvider(widget.editId!)),
                )
              : const SkeletonList(itemCount: 4, itemHeight: 64),
        );
      }
    }

    final errors = _submitted ? _validate() : const AppointmentFormErrors({});
    final restricted = _restricted;
    final title = _isEdit
        ? '${terms.appointment} düzenle'
        : 'Yeni ${trLower(terms.appointment)}';

    return PopScope(
      canPop: !_dirty || _saved || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard() && mounted) nav.pop();
      },
      child: AppScaffold(
        title: title,
        showMenuButton: false,
        bottomBar: BottomSaveBar(
          onSave: _saving ? null : _save,
          loading: _saving,
          saveLabel: _isEdit ? 'Kaydet' : '${terms.appointment} ekle',
          onCancel: () => Navigator.of(context).maybePop(),
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            if (_serverError != null) ...[
              _Banner(text: _serverError!, error: true),
              const SizedBox(height: Space.md),
            ],
            if (!restricted) ...[
              _FieldLabel('Tür', error: errors['type']),
              _typeChips(terms),
              const SizedBox(height: Space.lg),
              _FieldLabel('Kime?', error: errors['customer']),
              _linkTile(terms),
              const SizedBox(height: Space.md),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: '${terms.customer} adı',
                  errorText: errors['customer'] != null && !_hasLink
                      ? errors['customer']
                      : null,
                ),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  labelText: 'Telefon',
                  errorText: errors['phone'],
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
            _FieldLabel('Gün', error: errors['scheduledAt']),
            _dayChips(),
            const SizedBox(height: Space.md),
            const _FieldLabel('Saat'),
            _timeChips(),
            if (_at != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                'Seçilen: ${Fmt.dateWithWeekday(_at!)}, ${Fmt.time(_at!)}',
                style: context.text.bodyMedium,
              ),
            ],
            _conflictBanner(),
            const SizedBox(height: Space.lg),
            if (!restricted) ...[
              const _FieldLabel('Atanan kişi'),
              _assigneeChips(),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _address,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                autofillHints: const [AutofillHints.fullStreetAddress],
                decoration: InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: const Icon(Icons.place_outlined),
                  errorText: errors['address'],
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            if (restricted && _isEdit) ...[
              const _FieldLabel('Durum'),
              _statusChips(),
              const SizedBox(height: Space.lg),
            ],
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Not',
                alignLabelWithHint: true,
                errorText: errors['notes'],
              ),
            ),
            const SizedBox(height: Space.xl),
          ],
        ),
      ),
    );
  }

  Widget _typeChips(Glossary terms) {
    final options = [...terms.appointmentTypeOptions];
    if (_type.isNotEmpty && !options.any((o) => o.api == _type)) {
      options.add((api: _type, label: terms.appointmentTypeLabel(_type)));
    }
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label),
            selected: _type == o.api,
            onSelected: (_) => _set(() => _type = o.api),
          ),
      ],
    );
  }

  Widget _linkTile(Glossary terms) {
    final linked = _linkLabel != null;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minTileHeight: Sizes.minTouch + 8,
        leading: Icon(linked ? Icons.link : Icons.person_search_outlined),
        title: Text(
          linked
              ? _linkLabel!
              : '${terms.customer}, ${trLower(terms.offer)} ya da ${trLower(terms.job)} seç',
        ),
        subtitle: linked ? const Text('Bağlı kayıt') : null,
        trailing: linked
            ? IconButton(
                tooltip: 'Bağlantıyı kaldır',
                icon: const Icon(Icons.close),
                onPressed: _clearLink,
              )
            : const Icon(Icons.chevron_right),
        onTap: _pickLink,
      ),
    );
  }

  Widget _dayChips() {
    final now = Ist.now();
    final days = [for (var i = 0; i < 7; i++) Ist.dayRange(now, i).start];
    final selDay = _at == null ? null : Ist.startOfDay(_at!);
    String label(DateTime d, int i) {
      if (i == 0) return 'Bugün';
      if (i == 1) return 'Yarın';
      final w = Ist.wall(d);
      return '${Fmt.weekdaysShort[w.weekday - 1]} ${w.day}';
    }

    final inQuick = selDay != null && days.contains(selDay);
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (var i = 0; i < days.length; i++)
          ChoiceChip(
            label: Text(label(days[i], i)),
            selected: selDay == days[i],
            onSelected: (_) => _set(() => _at = _withDay(days[i])),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_month_outlined, size: Sizes.iconSm),
          label: Text(selDay != null && !inQuick ? Fmt.date(selDay) : 'Seç…'),
          selected: selDay != null && !inQuick,
          onSelected: (_) => _pickDay(),
        ),
      ],
    );
  }

  Widget _timeChips() {
    final w = _at == null ? null : Ist.wall(_at!);
    final inQuick =
        w != null && _quickTimes.any((t) => t.$1 == w.hour && t.$2 == w.minute);
    String two(int n) => n.toString().padLeft(2, '0');
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final t in _quickTimes)
          ChoiceChip(
            label: Text('${two(t.$1)}:${two(t.$2)}'),
            selected: w != null && w.hour == t.$1 && w.minute == t.$2,
            onSelected: (_) => _set(() => _at = _withTime(t.$1, t.$2)),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.schedule, size: Sizes.iconSm),
          label: Text(w != null && !inQuick ? Fmt.time(_at!) : 'Seç…'),
          selected: w != null && !inQuick,
          onSelected: (_) => _pickTime(),
        ),
      ],
    );
  }

  Widget _assigneeChips() {
    final options = ref.watch(assigneeOptionsProvider);
    if (options.isEmpty) return const Text('Atanabilecek kişi yok.');
    final known = options.any((o) => o.id == _assigneeId);
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final o in options)
          ChoiceChip(
            avatar: const Icon(Icons.person_outline, size: Sizes.iconSm),
            label: Text(
              o.isMe ? '${o.name} (ben)' : '${o.name} · ${o.roleLabel}',
            ),
            selected: _assigneeId == o.id,
            onSelected: (sel) => _set(() => _assigneeId = sel ? o.id : null),
          ),
        if (!known && _assigneeId != null)
          ChoiceChip(
            label: Text(_original?.assignedUserName ?? 'Atanmış kişi'),
            selected: true,
            onSelected: (_) => _set(() => _assigneeId = null),
          ),
      ],
    );
  }

  Widget _statusChips() {
    const values = [
      ('beklemede', 'Beklemede'),
      ('onaylandı', 'Onaylandı'),
      ('tamamlandı', 'Tamamlandı'),
      ('iptal', 'İptal'),
    ];
    final cur = AppointmentValues.normalize(_status);
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(v.$2),
            selected: AppointmentValues.normalize(v.$1) == cur,
            onSelected: (_) => _set(() => _status = v.$1),
          ),
      ],
    );
  }

  Widget _conflictBanner() {
    final at = _at;
    final who =
        _assigneeId ??
        (_restricted ? ref.watch(currentUserProvider)?.id : null);
    if (at == null || who == null) return const SizedBox.shrink();
    final c = ref.watch(
      conflictsProvider(
        ConflictQuery(at: at, assigneeId: who, excludeId: widget.editId),
      ),
    );
    final list = c.value ?? const <Appointment>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final terms = ref.watch(brandProfileProvider).terms;
    final first = list.first;
    final more = list.length > 1 ? ' (+${list.length - 1})' : '';
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: _Banner(
        text:
            'Aynı kişide bu saate yakın başka ${trLower(terms.appointment)} var: '
            '${Fmt.time(first.scheduledAt!)} ${terms.appointmentTypeLabel(first.type)}'
            '${first.displayName == null ? '' : ' · ${first.displayName}'}$more. '
            'Yine de kaydedebilirsiniz.',
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.error});
  final String text;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: context.text.labelLarge),
          if (error != null)
            Text(
              error!,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final c = context.colors;
    final bg = error ? c.errorContainer : x.warningContainer;
    final fg = error ? c.onErrorContainer : x.onWarning;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.warning_amber_rounded,
              color: fg,
              size: Sizes.iconSm,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                text,
                style: context.text.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
