// Giriş yönlendirmesi (saf fonksiyon: kolay test edilir).
import '../api/health_service.dart';
import '../auth/session.dart';
import 'routes.dart';

String? _safeFrom(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//'))
    return null;
  final path = Uri.tryParse(from)?.path;
  if (path == null) return null;
  if (path == Routes.login ||
      path == Routes.splash ||
      path == Routes.updateRequired)
    return null;
  return from;
}

String _withFrom(String target, Uri uri) {
  // /splash?from=X → X korunur (açılışta derin bağlantı kaybolmasın).
  final carried = uri.path == Routes.splash
      ? _safeFrom(uri.queryParameters['from'])
      : null;
  final loc = carried ?? uri.toString();
  if (_safeFrom(loc) == null || uri.path == Routes.today) return target;
  return '$target?from=${Uri.encodeComponent(loc)}';
}

/// null → olduğu yerde kal.
String? computeRedirect({
  required SessionState session,
  required Uri uri,
  UpdateRequirement update = UpdateRequirement.none,
}) {
  final path = uri.path;
  switch (session) {
    case SessionBooting():
    case SessionBootFailed():
      return path == Routes.splash ? null : _withFrom(Routes.splash, uri);
    case SessionUnauthenticated():
      return path == Routes.login ? null : _withFrom(Routes.login, uri);
    case SessionAuthenticated():
      if (update.isRequired)
        return path == Routes.updateRequired ? null : Routes.updateRequired;
      if (path == Routes.login || path == Routes.splash) {
        return _safeFrom(uri.queryParameters['from']) ?? Routes.today;
      }
      if (path == Routes.updateRequired) return Routes.today;
      if (!RouteGuard.isAllowed(path, session.capabilities))
        return Routes.today;
      return null;
  }
}
