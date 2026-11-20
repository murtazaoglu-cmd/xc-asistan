// SAHİBİ: appointments ajanı. Randevu durum yönetimi (Riverpod): aralık listesi, detay,
// değişiklik sayacı (Bugün ekranı bunu dinleyip sessizce yeniler), gizli (silinmek üzere)
// kayıtlar, atanan seçenekleri ve çakışma sorgusu.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/util/dates.dart';
import '../data/appointment_logic.dart';
import '../data/appointment_models.dart';
import '../data/appointments_repository.dart';

@immutable
class AppointmentQuery {
  const AppointmentQuery(this.range, {this.mine = false});
  final InstantRange range;

  /// true → `assigned_user_id=me` (saha her zaman; diğer roller "Yalnız benim" süzgeci).
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is AppointmentQuery && other.range == range && other.mine == mine;
  @override
  int get hashCode => Object.hash(range, mine);
}

/// Riverpod 3 varsayılan olarak hatalı sağlayıcıyı kendi kendine yeniden dener ve bu sürede
/// "yükleniyor" kalır; ApiClient zaten güvenli GET'leri yeniden denediği için burada KAPALI
/// (hata hemen "Tekrar dene" ekranına düşer).
Duration? noProviderRetry(int retryCount, Object error) => null;

final appointmentsRangeProvider = FutureProvider.autoDispose
    .family<List<Appointment>, AppointmentQuery>((ref, q) {
      // Kullanıcı değişirse (çıkış/giriş) eski kullanıcının verisi kalmasın.
      ref.watch(currentUserProvider.select((u) => u?.id));
      return ref
          .watch(appointmentsRepositoryProvider)
          .list(range: q.range, assignedUserId: q.mine ? 'me' : null);
    }, retry: noProviderRetry);

final appointmentDetailProvider = FutureProvider.autoDispose
    .family<Appointment, String>((ref, id) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return ref.watch(appointmentsRepositoryProvider).get(id);
    }, retry: noProviderRetry);

/// Her başarılı yazmada (oluştur/düzenle/durum/sil) artar. Bugün ekranı dinler.
class AppointmentsMutationNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final appointmentsMutationProvider =
    NotifierProvider<AppointmentsMutationNotifier, int>(
      AppointmentsMutationNotifier.new,
    );

/// "Geri al" penceresinde silinmek üzere olan randevular: listelerde gizlenir.
class HiddenAppointmentsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void hide(String id) => state = {...state, id};
  void unhide(String id) => state = {...state}..remove(id);
}

final hiddenAppointmentIdsProvider =
    NotifierProvider<HiddenAppointmentsNotifier, Set<String>>(
      HiddenAppointmentsNotifier.new,
    );

/// Yazma işlemleri. Widget ömründen bağımsızdır (geri al penceresi ekran kapanınca da işler).
class AppointmentActions {
  AppointmentActions(this._ref);
  final Ref _ref;

  AppointmentsRepository get _repo => _ref.read(appointmentsRepositoryProvider);

  void _changed() {
    _ref.read(appointmentsMutationProvider.notifier).bump();
    _ref.invalidate(appointmentsRangeProvider);
    _ref.invalidate(appointmentDetailProvider);
  }

  Future<Appointment> create(AppointmentDraft draft) async {
    final r = await _repo.create(draft);
    _changed();
    return r;
  }

  Future<Appointment> patch(String id, Map<String, dynamic> body) async {
    final r = await _repo.patch(id, body);
    _changed();
    return r;
  }

  Future<Appointment> setStatus(String id, String status) async {
    final r = await _repo.setStatus(id, status);
    _changed();
    return r;
  }

  Future<Appointment> reschedule(String id, DateTime at) async {
    final r = await _repo.reschedule(id, at);
    _changed();
    return r;
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    _changed();
  }

  void hide(String id) =>
      _ref.read(hiddenAppointmentIdsProvider.notifier).hide(id);
  void unhide(String id) =>
      _ref.read(hiddenAppointmentIdsProvider.notifier).unhide(id);

  /// Elle yenileme (çekip yenile).
  void refreshAll() {
    _ref.invalidate(appointmentsRangeProvider);
    _ref.invalidate(appointmentDetailProvider);
  }
}

final appointmentActionsProvider = Provider<AppointmentActions>(
  (ref) => AppointmentActions(ref),
);

// ---------------- Atanan kişi seçenekleri (rol kapsamı: /auth/me team + lider) ----------------

@immutable
class Assignee {
  const Assignee({
    required this.id,
    required this.name,
    required this.roleLabel,
    this.isMe = false,
  });
  final String id;
  final String name;
  final String roleLabel;
  final bool isMe;
}

String _roleLabel(String api) => UserRole.fromApi(api)?.label ?? api;

/// Kendisi + lider + ekip. Sunucu atamayı yine denetler (kapsam dışı → 403).
final assigneeOptionsProvider = Provider<List<Assignee>>((ref) {
  final s = ref.watch(sessionProvider);
  if (s is! SessionAuthenticated) return const [];
  final out = <Assignee>[
    Assignee(
      id: s.user.id,
      name: s.user.name,
      roleLabel: s.user.role.label,
      isMe: true,
    ),
  ];
  final seen = {s.user.id};
  final leader = s.me.leader;
  final others = [if (leader != null) leader, ...s.me.team];
  for (final u in others) {
    if (u.id.isEmpty || !seen.add(u.id)) continue;
    out.add(Assignee(id: u.id, name: u.name, roleLabel: _roleLabel(u.role)));
  }
  return out;
});

// ---------------- Çakışma sorgusu ----------------

@immutable
class ConflictQuery {
  const ConflictQuery({required this.at, this.assigneeId, this.excludeId});
  final DateTime at;
  final String? assigneeId;
  final String? excludeId;

  @override
  bool operator ==(Object other) =>
      other is ConflictQuery &&
      other.at == at &&
      other.assigneeId == assigneeId &&
      other.excludeId == excludeId;
  @override
  int get hashCode => Object.hash(at, assigneeId, excludeId);
}

/// Aynı kişi, aynı saat (±60 dk) başka açık randevu var mı. Hata → çakışma yok sayılır
/// (uyarı bilgilendirmedir, kaydı engellemez).
final conflictsProvider = FutureProvider.autoDispose
    .family<List<Appointment>, ConflictQuery>((ref, q) async {
      if (q.assigneeId == null) return const [];
      try {
        final day = await ref
            .watch(appointmentsRepositoryProvider)
            .list(range: Ist.dayRange(q.at), assignedUserId: q.assigneeId);
        return findConflicts(
          day,
          at: q.at,
          assigneeId: q.assigneeId,
          excludeId: q.excludeId,
        );
      } catch (_) {
        return const [];
      }
    }, retry: noProviderRetry);
