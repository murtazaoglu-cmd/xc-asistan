// DEMO modu: Dio'nun HTTP katmanını bellek içi sahte API ile değiştirir. Repository'ler
// gerçek HTTP koduyla çalışır; yalnızca ağ yerine örnek veri döner (sözleşme biçiminde).
//
// Yeni uç eklemek: ilgili feature'ın `data/<feature>_demo.dart` dosyasına DemoRoute ekleyin
// (veri için core/demo/demo_db.dart'taki DemoDb okunur/yazılır).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/appointments/data/appointments_demo.dart';
import '../../features/assistant/assistant_public.dart'
    show assistantDemoRoutes;
import '../../features/customers/data/customers_demo.dart';
import '../../features/finance/data/finance_demo.dart';
import '../../features/home/data/home_demo.dart';
import '../../features/invoices_vat/data/invoices_vat_demo.dart';
import '../../features/jobs/data/jobs_demo.dart';
import '../../features/reports/data/reports_demo.dart';
import '../../features/settings/data/settings_demo.dart';
import '../../features/stock/data/stock_demo.dart';
import 'demo_core_routes.dart';
import 'demo_db.dart';
import 'demo_router.dart';

class DemoHttpAdapter implements HttpClientAdapter {
  DemoHttpAdapter(this.db, {this.latency = const Duration(milliseconds: 150)})
    : routes = [
        ...demoCoreRoutes(db),
        ...homeDemoRoutes(db),
        ...appointmentsDemoRoutes(db),
        // settings önce: GET /users gerçek kullanıcı listesini döner (jobs'un kısa listesinin önünde).
        ...settingsDemoRoutes(db),
        ...jobsDemoRoutes(db),
        ...customersDemoRoutes(db),
        ...financeDemoRoutes(db),
        ...stockDemoRoutes(db),
        ...reportsDemoRoutes(db),
        ...invoicesVatDemoRoutes(db),
        ...assistantDemoRoutes(db),
      ];

  final DemoDb db;
  final Duration latency;
  final List<DemoRoute> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    final uri = options.uri;
    var path = uri.path;
    final basePath = Uri.parse(options.baseUrl).path;
    if (basePath.isNotEmpty && basePath != '/' && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }
    if (path.length > 1 && path.endsWith('/'))
      path = path.substring(0, path.length - 1);

    final auth = options.headers['Authorization']?.toString();
    final token = (auth != null && auth.startsWith('Bearer '))
        ? auth.substring(7)
        : null;

    DemoResponse res;
    final method = options.method.toUpperCase();
    DemoRoute? hit;
    Map<String, String>? params;
    for (final r in routes) {
      final p = r.match(method, path);
      if (p != null) {
        hit = r;
        params = p;
        break;
      }
    }
    if (hit == null) {
      res = DemoResponse.error(404, 'Kayıt bulunamadı.');
    } else if (!hit.public &&
        (token == null || !token.startsWith('demo-token-'))) {
      res = DemoResponse.error(401, 'Oturum geçersiz.');
    } else {
      try {
        res = hit.handler(
          DemoRequest(
            method: method,
            path: path,
            query: uri.queryParameters,
            body: options.data,
            params: params!,
            token: token,
          ),
        );
      } catch (_) {
        res = DemoResponse.error(500, 'Sunucu hatası.');
      }
    }

    return ResponseBody.fromString(
      jsonEncode(res.body),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in res.headers.entries) e.key.toLowerCase(): [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final demoDbProvider = Provider<DemoDb>((ref) => DemoDb());

final demoAdapterProvider = Provider<HttpClientAdapter>(
  (ref) => DemoHttpAdapter(ref.watch(demoDbProvider)),
);
