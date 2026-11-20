import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/appointment_detail_screen.dart';
import 'presentation/appointment_form_screen.dart';
import 'presentation/appointments_screen.dart';

/// Bu feature'ın DIŞARIYA AÇIK yol yardımcıları (diğer feature'lar yalnız metin yolu kullanır).
///
/// Örnek: teklif detayından "Randevu ekle" →
/// `context.push(AppointmentsRoutes.newPath(offerId: id))`.
abstract final class AppointmentsRoutes {
  static const newSegment = 'new';
  static const editSegment = 'edit';

  /// Yeni randevu formu. Verilen alanlar formda ÖNCEDEN dolu gelir.
  static String newPath({
    DateTime? day,
    String? offerId,
    String? projectId,
    String? customerName,
    String? customerPhone,
    String? address,
    String? type,
  }) {
    final q = <String, String>{
      if (day != null) 'day': day.toUtc().toIso8601String(),
      if (offerId != null) 'offerId': offerId,
      if (projectId != null) 'projectId': projectId,
      if (customerName != null) 'customerName': customerName,
      if (customerPhone != null) 'customerPhone': customerPhone,
      if (address != null) 'address': address,
      if (type != null) 'type': type,
    };
    return Uri(
      path: '${Routes.appointments}/$newSegment',
      queryParameters: q.isEmpty ? null : q,
    ).toString();
  }

  static String edit(String id) => '${Routes.appointment(id)}/$editSegment';
}

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
/// `new` kalıbı `:id` kalıbından ÖNCE gelmelidir.
final List<RouteBase> appointmentsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.appointments,
    builder: (context, state) => const AppointmentsScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: AppointmentsRoutes.newSegment,
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return AppointmentFormScreen(
            prefill: AppointmentPrefill(
              day: DateTime.tryParse(q['day'] ?? '')?.toUtc(),
              offerId: q['offerId'],
              projectId: q['projectId'],
              customerName: q['customerName'],
              customerPhone: q['customerPhone'],
              address: q['address'],
              type: q['type'],
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.appointmentPattern,
        builder: (context, state) =>
            AppointmentDetailScreen(id: state.pathParameters['id']!),
        routes: <RouteBase>[
          GoRoute(
            path: AppointmentsRoutes.editSegment,
            builder: (context, state) =>
                AppointmentFormScreen(editId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  ),
];
