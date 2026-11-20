import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'jobs_paths.dart';
import 'presentation/jobs_screen.dart';
import 'presentation/offer_detail_screen.dart';
import 'presentation/offer_form_screen.dart';
import 'presentation/project_detail_screen.dart';
import 'presentation/project_form_screen.dart';
import 'presentation/quote_editor_screen.dart';

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
/// Sıra önemlidir: sabit yollar (`offers/new`, `projects/new`) `:id` kalıplarından ÖNCE gelir.
final List<RouteBase> jobsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.jobs,
    builder: (context, state) => const JobsScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: JobsPaths.newOfferPattern,
        builder: (context, state) => const OfferFormScreen(),
      ),
      GoRoute(
        path: JobsPaths.newProjectPattern,
        builder: (context, state) => const ProjectFormScreen(),
      ),
      GoRoute(
        path: Routes.offerPattern,
        builder: (context, state) =>
            OfferDetailScreen(id: state.pathParameters['id']!),
        routes: <RouteBase>[
          GoRoute(
            path: JobsPaths.editPattern,
            builder: (context, state) =>
                OfferFormScreen(offerId: state.pathParameters['id']),
          ),
          GoRoute(
            path: JobsPaths.quotePattern,
            builder: (context, state) =>
                QuoteEditorScreen(offerId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.projectPattern,
        builder: (context, state) =>
            ProjectDetailScreen(id: state.pathParameters['id']!),
      ),
    ],
  ),
];
