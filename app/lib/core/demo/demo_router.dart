// DEMO (--dart-define=DEMO=true): bellek içi sahte API için istek/yanıt ve rota eşleme.
import '../auth/auth_models.dart';
import '../util/json.dart';

class DemoRequest {
  DemoRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.params,
    required this.token,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final Map<String, String> params;
  final String? token;

  JsonMap get bodyMap => asJsonMap(body);

  /// Demo jetonu `demo-token-<rol>` biçimindedir.
  UserRole? get role {
    final t = token;
    if (t == null || !t.startsWith('demo-token-')) return null;
    return UserRole.fromApi(t.substring('demo-token-'.length));
  }
}

class DemoResponse {
  DemoResponse(this.status, this.body, {this.headers = const {}});

  factory DemoResponse.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => DemoResponse(status, body, headers: headers);

  /// Sözleşme hata biçimi: {"error":"Türkçe mesaj"}
  factory DemoResponse.error(int status, String message) =>
      DemoResponse(status, {'error': message});

  final int status;
  final Object? body;
  final Map<String, String> headers;
}

typedef DemoHandler = DemoResponse Function(DemoRequest req);

class DemoRoute {
  DemoRoute(this.method, this.pattern, this.handler, {this.public = false});

  final String method;

  /// "/offers/:id/status" gibi; ":x" parça yakalar.
  final String pattern;
  final DemoHandler handler;

  /// true ise jeton gerekmez (giriş, sağlık).
  final bool public;

  Map<String, String>? match(String m, String path) {
    if (m.toUpperCase() != method) return null;
    final a = pattern.split('/'), b = path.split('/');
    if (a.length != b.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < a.length; i++) {
      if (a[i].startsWith(':')) {
        params[a[i].substring(1)] = Uri.decodeComponent(b[i]);
      } else if (a[i] != b[i]) {
        return null;
      }
    }
    return params;
  }
}
