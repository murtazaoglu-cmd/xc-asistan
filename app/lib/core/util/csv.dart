// CSV üretimi (Türkçe Excel uyumlu: UTF-8 BOM + `;` ayırıcı, CRLF).
import 'dart:convert';
import 'dart:typed_data';

abstract final class Csv {
  static String _cell(String v) {
    var s = v;
    // Excel formül enjeksiyonu: `=`/`@` ile ya da `+`/`-` ardından harf/`(` ile başlayan metin
    // metin olarak işaretlenir (eksi tutarlar "-₺1.200,00" bozulmaz).
    if (s.isNotEmpty) {
      final c = s[0];
      final next = s.length > 1 ? s[1] : '';
      final risky =
          c == '=' ||
          c == '@' ||
          ((c == '+' || c == '-') &&
              RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü(=@]').hasMatch(next));
      if (risky) s = "'$s";
    }
    if (s.contains(';') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String encode(List<String> headers, List<List<String>> rows) {
    final b = StringBuffer()..write(headers.map(_cell).join(';'));
    for (final r in rows) {
      b
        ..write('\r\n')
        ..write(r.map(_cell).join(';'));
    }
    return b.toString();
  }

  /// BOM'lu UTF-8 baytlar (Excel Türkçe karakterleri doğru açar).
  static Uint8List bytes(List<String> headers, List<List<String>> rows) =>
      Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(encode(headers, rows)),
      ]);
}
