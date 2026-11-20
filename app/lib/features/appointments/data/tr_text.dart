// Türkçe büyük/küçük harf yardımcıları. Dart'ın `toLowerCase()` "İ" harfini
// birleşik noktalı "i̇" yapar; sözlük terimlerini cümle içinde küçültürken bu kullanılır.
String trLower(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// İlk harfi büyütür ("randevu" → "Randevu", "iş" → "İş").
String trCapitalize(String s) {
  if (s.isEmpty) return s;
  final first = s[0];
  final up = first == 'i'
      ? 'İ'
      : first == 'ı'
      ? 'I'
      : first.toUpperCase();
  return '$up${s.substring(1)}';
}
