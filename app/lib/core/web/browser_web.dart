// Tarayıcı uygulaması (package:web). Yalnız web derlemesinde içe aktarılır.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Baytları dosya olarak indirir (gizli <a download> + Blob adresi).
Future<bool> browserDownload(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    // İndirme başladıktan sonra adres serbest bırakılır.
    Future<void>.delayed(
      const Duration(seconds: 10),
      () => web.URL.revokeObjectURL(url),
    );
    return true;
  } catch (_) {
    return false;
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Tabloyu gizli bir iframe içinde basit bir sayfa olarak kurup yazdırma penceresini açar
/// (tuval tabanlı uygulamayı doğrudan yazdırmak boş sayfa verir).
bool browserPrintTable(
  String title,
  List<String> headers,
  List<List<String>> rows,
) {
  try {
    final sb = StringBuffer()
      ..write('<!doctype html><html lang="tr"><head><meta charset="utf-8">')
      ..write('<title>${_esc(title)}</title><style>')
      ..write(
        'body{font:12px Inter,Arial,sans-serif;color:#172033;margin:24px}',
      )
      ..write('h1{font-size:18px;margin:0 0 12px}')
      ..write('table{border-collapse:collapse;width:100%}')
      ..write('th,td{border:1px solid #cbd5e1;padding:6px 8px;text-align:left}')
      ..write('th{background:#eef2f7}')
      ..write('</style></head><body><h1>${_esc(title)}</h1><table><thead><tr>');
    for (final h in headers) {
      sb.write('<th>${_esc(h)}</th>');
    }
    sb.write('</tr></thead><tbody>');
    for (final r in rows) {
      sb.write('<tr>');
      for (final c in r) {
        sb.write('<td>${_esc(c)}</td>');
      }
      sb.write('</tr>');
    }
    sb.write('</tbody></table></body></html>');

    final frame = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..style.position = 'fixed'
      ..style.width = '0'
      ..style.height = '0'
      ..style.border = '0';
    web.document.body?.append(frame);
    final doc = frame.contentWindow?.document;
    if (doc == null) {
      frame.remove();
      return false;
    }
    doc.open();
    doc.write(sb.toString().toJS);
    doc.close();
    frame.contentWindow?.focus();
    frame.contentWindow?.print();
    Future<void>.delayed(const Duration(seconds: 30), () => frame.remove());
    return true;
  } catch (_) {
    return false;
  }
}

/// `blob:` adresindeki baytları okur (image_picker web çıktısı).
Future<Uint8List?> browserReadBlob(String url) async {
  try {
    final res = await web.window.fetch(url.toJS).toDart;
    final buf = await res.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
