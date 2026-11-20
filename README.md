# XC Asistan

İşletmeler için sekreter + müdür asistanı (Flutter mobil/web uygulaması + Node/PostgreSQL backend).

- `backend/` — API ve worker (Node 20, Express, PostgreSQL, PM2). Kurulum: `docs/SUNUCU-GUNCELLEME.md`
- `app/` — Flutter uygulaması (Android, iOS, web)
- `docs/` — API sözleşmesi, tasarım ve karşılaştırma raporları

Gizli bilgiler (`.env`, anahtar dosyaları) depoya konmaz; GitHub Secrets kullanılır.
