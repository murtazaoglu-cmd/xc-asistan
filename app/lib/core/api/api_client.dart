// Dio üzerinde ince bir sarmalayıcı: hep AppException fırlatır.
//
// Kalıp (repository içinde):
//   final json = await _api.getMap('/appointments', query: {'from': ...});
//   return Appointment.fromJson(json);
// Sayfalı liste: getPaged('/offers', query: {'limit': 50, 'offset': 0}).
// Özel durum kodları (ör. teklif gönderimi 200/207/502): send(..., acceptStatuses: {207, 502}).
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../files/picked_files.dart';
import '../util/json.dart';
import 'api_exception.dart';

/// Ham yanıt (kabul edilen özel durum kodlarında kullanılır).
@immutable
class ApiResponse {
  const ApiResponse(this.statusCode, this.data, this.headers);
  final int statusCode;
  final Object? data;
  final Map<String, List<String>> headers;

  /// `X-Total-Count` başlığı (arama/sayfalamada toplam eşleşme).
  int? get totalCount {
    final v = headers['x-total-count'];
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v.first);
  }

  JsonMap get map => asJsonMap(data);
  List<JsonMap> get list => asJsonList(data);
}

@immutable
class Paged<T> {
  const Paged(this.items, this.total);
  final List<T> items;

  /// Sunucunun bildirdiği toplam; başlık yoksa [items].length.
  final int total;

  bool hasMore(int offset) => offset + items.length < total;
}

class ApiClient {
  ApiClient(this.dio);

  final Dio dio;

  /// Ham istek. [acceptStatuses] 2xx dışında hata saymayacağınız kodlar (207, 502 gibi).
  Future<ApiResponse> send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Set<int> acceptStatuses = const {},
    CancelToken? cancelToken,
    Map<String, dynamic>? extra,
    Options? options,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final opts = (options ?? Options()).copyWith(
      method: method,
      extra: {...?options?.extra, ...?extra},
      validateStatus: (s) =>
          s != null && ((s >= 200 && s < 300) || acceptStatuses.contains(s)),
    );
    try {
      final res = await dio.request<Object?>(
        path,
        data: data,
        queryParameters: query == null ? null : _cleanQuery(query),
        cancelToken: cancelToken,
        options: opts,
        onSendProgress: onSendProgress,
      );
      return ApiResponse(res.statusCode ?? 0, res.data, res.headers.map);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  Map<String, dynamic> _cleanQuery(Map<String, dynamic> q) {
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && !(v is String && v.isEmpty)) out[k] = v;
    });
    return out;
  }

  Future<Object?> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async =>
      (await send('GET', path, query: query, cancelToken: cancelToken)).data;

  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async => (await send('POST', path, data: data, query: query)).data;

  Future<Object?> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async => (await send('PATCH', path, data: data, query: query)).data;

  Future<Object?> put(String path, {Object? data}) async =>
      (await send('PUT', path, data: data)).data;

  Future<Object?> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async => (await send('DELETE', path, data: data, query: query)).data;

  Future<JsonMap> getMap(String path, {Map<String, dynamic>? query}) async =>
      asJsonMap(await get(path, query: query));

  Future<List<JsonMap>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async => asJsonList(await get(path, query: query));

  /// Sayfalı/aramalı liste: gövde düz dizi, toplam `X-Total-Count` başlığında.
  Future<Paged<JsonMap>> getPaged(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await send('GET', path, query: query);
    final items = res.list;
    return Paged(items, res.totalCount ?? items.length);
  }

  /// multipart/form-data yükleme (`/documents/...` alan adı `file`; galeri `photo`).
  /// Content-Type'ı elle ayarlamayın; Dio sınırı (boundary) kendisi ekler.
  Future<JsonMap> upload(
    String path, {
    required String field,
    required String filePath,
    String? fileName,
    Map<String, String> fields = const {},
    void Function(int sent, int total)? onProgress,
  }) async {
    // Web'de seçiciler yol yerine bayt verir (`xcmem://` / `blob:`): bayttan oluştur.
    final bytes = await PickedFileStore.read(filePath);
    if (PickedFileStore.isMemory(filePath) || filePath.startsWith('blob:')) {
      if (bytes == null) {
        throw const AppException(
          AppErrorCode.unknown,
          'Dosya okunamadı. Lütfen dosyayı yeniden seçin.',
        );
      }
    }
    final form = FormData.fromMap({
      ...fields,
      field: bytes != null
          ? MultipartFile.fromBytes(bytes, filename: fileName ?? 'dosya')
          : await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await send(
      'POST',
      path,
      data: form,
      onSendProgress: onProgress,
    );
    return res.map;
  }
}
