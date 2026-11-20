// SAHİBİ: appointments ajanı. Başka feature bu dosyaya yazmaz.
// Randevular veri erişimi. Uçlar (sözleşme /mnt/user-data/outputs/mobile-api-contract.md §9):
//   - GET/POST /appointments (?from ?to ?assigned_user_id=me ?status)
//   - GET/PATCH/DELETE /appointments/:id (saha: yalnız status, notes, scheduled_at)
//   - Seçici için: GET /offers?q, /projects?q, /customers?q (sözleşme §6; limit ≤200)
//
// Metotlar AppException fırlatır (ApiClient bunu zaten yapar); tarihler UTC DateTime'dır.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import 'appointment_models.dart';

abstract class AppointmentsRepository {
  /// [range] yarı açık [başlangıç, bitiş): sunucuda `from` (dahil) / `to` (hariç).
  /// [assignedUserId] `me` olabilir.
  Future<List<Appointment>> list({
    InstantRange? range,
    String? assignedUserId,
    String? status,
  });

  Future<Appointment> get(String id);
  Future<Appointment> create(AppointmentDraft draft);

  /// Ham PATCH (yalnız değişen alanlar). Saha yalnız status/notes/scheduled_at gönderebilir.
  Future<Appointment> patch(String id, Map<String, dynamic> body);

  Future<Appointment> setStatus(String id, String status);
  Future<Appointment> reschedule(String id, DateTime at);
  Future<void> delete(String id);

  /// Seçici araması. [query] boş olsa da ilk [limit] kayıt gelir.
  Future<List<LinkCandidate>> search(
    LinkKind kind,
    String query, {
    int limit = 20,
  });
}

class HttpAppointmentsRepository implements AppointmentsRepository {
  HttpAppointmentsRepository(this.api);
  final ApiClient api;

  @override
  Future<List<Appointment>> list({
    InstantRange? range,
    String? assignedUserId,
    String? status,
  }) async {
    final rows = await api.getList(
      '/appointments',
      query: {
        'from': range?.start.toUtc().toIso8601String(),
        'to': range?.end.toUtc().toIso8601String(),
        'assigned_user_id': assignedUserId,
        'status': status,
      },
    );
    final list = rows.map(Appointment.fromJson).toList();
    list.sort(_byTime);
    return list;
  }

  static int _byTime(Appointment a, Appointment b) {
    final x = a.scheduledAt, y = b.scheduledAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  @override
  Future<Appointment> get(String id) async =>
      Appointment.fromJson(await api.getMap('/appointments/$id'));

  @override
  Future<Appointment> create(AppointmentDraft draft) async =>
      Appointment.fromJson(
        asJsonMap(await api.post('/appointments', data: draft.toCreateJson())),
      );

  @override
  Future<Appointment> patch(String id, Map<String, dynamic> body) async =>
      Appointment.fromJson(
        asJsonMap(await api.patch('/appointments/$id', data: body)),
      );

  @override
  Future<Appointment> setStatus(String id, String status) =>
      patch(id, {'status': status});

  @override
  Future<Appointment> reschedule(String id, DateTime at) =>
      patch(id, {'scheduled_at': Ist.toApiIso(at)});

  @override
  Future<void> delete(String id) async {
    await api.delete('/appointments/$id');
  }

  @override
  Future<List<LinkCandidate>> search(
    LinkKind kind,
    String query, {
    int limit = 20,
  }) async {
    var q = query.trim();
    if (q.length > 100) q = q.substring(0, 100); // sözleşme §6: ≤100 karakter
    final params = {'q': q, 'limit': limit};
    switch (kind) {
      case LinkKind.offer:
        return (await api.getList(
          '/offers',
          query: params,
        )).map(LinkCandidate.fromOffer).toList();
      case LinkKind.project:
        return (await api.getList(
          '/projects',
          query: params,
        )).map(LinkCandidate.fromProject).toList();
      case LinkKind.customer:
        return (await api.getList(
          '/customers',
          query: params,
        )).map(LinkCandidate.fromCustomer).toList();
    }
  }
}

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>(
  (ref) => HttpAppointmentsRepository(ref.watch(apiClientProvider)),
);
