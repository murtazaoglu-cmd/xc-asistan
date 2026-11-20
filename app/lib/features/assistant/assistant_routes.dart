import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'data/briefing_models.dart';
import 'presentation/assistant_screen.dart';
import 'presentation/briefing_screen.dart';
import 'presentation/closure_screen.dart';
import 'presentation/consents_screen.dart';
import 'presentation/inbox_screen.dart';
import 'presentation/insights_screen.dart';
import 'presentation/notification_prefs_screen.dart';
import 'presentation/share_inbox_screen.dart';
import 'presentation/suggestions_screen.dart';

final List<RouteBase> assistantRoutes = <RouteBase>[
  GoRoute(
    path: Routes.assistant,
    builder: (context, state) => const AssistantScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'briefing',
        builder: (context, state) => const BriefingScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'history',
            builder: (context, state) => BriefingHistoryScreen(
              initialType: state.uri.queryParameters['type'],
            ),
          ),
          GoRoute(
            path: 'view',
            redirect: (context, state) =>
                state.extra is Briefing ? null : '/assistant/briefing/history',
            builder: (context, state) =>
                BriefingDetailScreen(briefing: state.extra! as Briefing),
          ),
        ],
      ),
      GoRoute(
        path: 'insights',
        builder: (context, state) => const InsightsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'rules',
            builder: (context, state) => const InsightRulesScreen(),
          ),
        ],
      ),
      GoRoute(
        path: 'closure',
        builder: (context, state) => const ClosureScreen(),
      ),
      GoRoute(path: 'inbox', builder: (context, state) => const InboxScreen()),
      GoRoute(
        path: 'prefs',
        builder: (context, state) => const NotificationPrefsScreen(),
      ),
      GoRoute(
        path: 'consents',
        builder: (context, state) => const ConsentsScreen(),
      ),
      GoRoute(
        path: 'suggestions',
        builder: (context, state) => SuggestionsScreen(
          conversationId: state.uri.queryParameters['conversation'],
          customerKey: state.uri.queryParameters['customer'],
        ),
      ),
      // "Paylaş" menüsünden gelen içerik (WhatsApp sohbet dışa aktarımı dahil).
      GoRoute(
        path: Routes.sharePattern,
        builder: (context, state) => ShareInboxScreen(
          customerKey: state.uri.queryParameters['customer'],
        ),
      ),
    ],
  ),
];
