// Testler için ortak sahte (fake) sınıflar.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/api/connectivity.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/auth_repository.dart';
import 'package:xc_asistan/core/auth/biometric.dart';
import 'package:xc_asistan/core/config/app_config.dart';
import 'package:xc_asistan/core/notifications/notification_models.dart';
import 'package:xc_asistan/core/notifications/notification_providers.dart';
import 'package:xc_asistan/core/notifications/notification_service.dart';
import 'package:xc_asistan/core/notifications/push_service.dart';
import 'package:xc_asistan/core/share/share_service.dart';
import 'package:xc_asistan/core/storage/storage_providers.dart';
import 'package:xc_asistan/core/storage/token_store.dart';
import 'package:xc_asistan/core/ui/ui_providers.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Sahte AuthRepository: çağrıları kaydeder, davranış dışarıdan ayarlanır.
class FakeAuthRepository implements AuthRepository {
  final List<String> calls = [];
  Object? meError;
  Object? loginError;
  Object? refreshError;
  Object? logoutAllError;
  MeResponse me_ = MeResponse.fromUser(
    const AuthUser(
      id: 'u1',
      name: 'Admin',
      email: 'a@x.com',
      role: UserRole.admin,
    ),
  );
  String loginToken = 'tok-login';
  String refreshToken = 'tok-refreshed';
  Completer<void>? meGate;

  @override
  Future<TokenResult> login(String email, String password) async {
    calls.add('login:$email');
    if (loginError != null) throw loginError!;
    return TokenResult(token: loginToken, user: me_.user);
  }

  @override
  Future<MeResponse> me() async {
    calls.add('me');
    if (meGate != null) await meGate!.future;
    if (meError != null) throw meError!;
    return me_;
  }

  @override
  Future<TokenResult> refresh() async {
    calls.add('refresh');
    if (refreshError != null) throw refreshError!;
    return TokenResult(token: refreshToken);
  }

  @override
  Future<void> logoutAll() async {
    calls.add('logoutAll');
    if (logoutAllError != null) throw logoutAllError!;
  }

  @override
  Future<void> unregisterDevice(String pushToken) async =>
      calls.add('unregister');
}

class FakePushService implements PushService {
  FakePushService(this.token, this.log);
  final String? token;
  final List<String> log;
  @override
  Future<void> init() async {}
  @override
  Future<String?> currentToken() async => token;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

class FakeBiometric implements BiometricService {
  bool supported = true;
  bool result = true;
  int authCalls = 0;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    return result;
  }
}

class FakeLinkLauncher implements LinkLauncher {
  final List<Uri> opened = [];
  final List<String> copied = [];
  final Set<String> failSchemes = {};
  @override
  Future<bool> open(Uri uri) async {
    if (failSchemes.contains(uri.scheme)) return false;
    opened.add(uri);
    return true;
  }

  @override
  Future<bool> canOpen(Uri uri) async => !failSchemes.contains(uri.scheme);
  @override
  Future<void> copy(String text) async => copied.add(text);
}

class FakeNotificationsGateway implements LocalNotificationsGateway {
  final List<String> log = [];
  final Map<int, DailyNotification> daily = {};
  final Map<int, tz.TZDateTime> firstFire = {};
  bool permission = true;
  String? launch;
  void Function(String?)? onTap;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    this.onTap = onTap;
    log.add('init');
  }

  @override
  Future<void> createChannel(NotificationChannelId channel) async =>
      log.add('channel:${channel.id}');
  @override
  Future<bool> requestPermission() async {
    log.add('permission');
    return permission;
  }

  @override
  Future<bool> areEnabled() async => permission;
  @override
  Future<void> scheduleDaily(DailyNotification n, tz.TZDateTime first) async {
    daily[n.id] = n;
    firstFire[n.id] = first;
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    required tz.TZDateTime when,
    String? payload,
  }) async => log.add('at:$id');
  @override
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required NotificationContent content,
    String? payload,
  }) async => log.add('show:$id');
  @override
  Future<void> cancel(int id) async {
    daily.remove(id);
    log.add('cancel:$id');
  }

  @override
  Future<void> cancelAll() async {
    daily.clear();
    log.add('cancelAll');
  }

  @override
  Future<String?> launchPayload() async => launch;
}

class FakeShareSource implements ShareSource {
  FakeShareSource([this.initial = const []]);
  final List<SharedMediaFile> initial;
  final StreamController<List<SharedMediaFile>> ctrl =
      StreamController.broadcast();
  int resets = 0;
  @override
  Future<List<SharedMediaFile>> initialMedia() async => initial;
  @override
  Stream<List<SharedMediaFile>> mediaStream() => ctrl.stream;
  @override
  Future<void> reset() async => resets++;
}

/// Testte kullanılan standart override'lar. [repo] verilmezse bellek içi demo yerine
/// FakeAuthRepository kullanılır.
Future<List<Override>> baseOverrides({
  FakeAuthRepository? repo,
  MemoryTokenStore? store,
  FakeBiometric? bio,
  FakeLinkLauncher? launcher,
  FakeNotificationsGateway? gateway,
  AppConfig config = const AppConfig(retryBaseDelay: Duration.zero),
  Map<String, Object> prefsValues = const {},
  Stream<bool>? connectivity,
  String? pushToken,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appConfigProvider.overrideWithValue(config),
    tokenStoreProvider.overrideWithValue(store ?? MemoryTokenStore()),
    if (repo != null) authRepositoryProvider.overrideWithValue(repo),
    biometricServiceProvider.overrideWithValue(bio ?? FakeBiometric()),
    linkLauncherProvider.overrideWithValue(launcher ?? FakeLinkLauncher()),
    notificationsGatewayProvider.overrideWithValue(
      gateway ?? FakeNotificationsGateway(),
    ),
    connectivityStreamProvider.overrideWithValue(
      connectivity ?? Stream<bool>.value(true),
    ),
    shareSourceProvider.overrideWithValue(FakeShareSource()),
    pushServiceProvider.overrideWithValue(FakePushService(pushToken, [])),
  ];
}

/// Dio için kurallı sahte HTTP bağdaştırıcı: her isteği kaydeder, sıradaki yanıtı verir.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.script);

  /// Her istek için çağrılır; (istek sırası, seçenekler) → yanıt ya da fırlatma.
  final FutureOr<ScriptedResponse> Function(int index, RequestOptions options)
  script;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final i = requests.length;
    requests.add(options);
    final r = await script(i, options);
    if (r.error != null) throw r.error!;
    return ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in r.headers.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class ScriptedResponse {
  ScriptedResponse(
    this.status, [
    this.body,
    this.headers = const {},
    this.error,
  ]);
  ScriptedResponse.error(DioExceptionType type, RequestOptions o)
    : status = 0,
      body = null,
      headers = const {},
      error = DioException(requestOptions: o, type: type);
  final int status;
  final Object? body;
  final Map<String, String> headers;
  final DioException? error;
}

AppException ex(AppErrorCode c, [String m = 'x']) => AppException(c, m);
