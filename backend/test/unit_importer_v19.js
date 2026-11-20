// WhatsApp ayrıştırıcı + zip okuyucu + çıkarıcı birim testleri (veritabanı gerekmez). Kullanım: node test/unit_importer_v19.js
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const { parseWhatsAppText, titleFromFileName } = require("../src/assistant/importer/whatsappParser");
const { extractChatText, ZipError, crc32 } = require("../src/assistant/importer/zipReader");
const { extractSuggestions } = require("../src/assistant/importer/extractor");
const FX = path.join(__dirname, "fixtures", "whatsapp");
const expected = JSON.parse(fs.readFileSync(path.join(FX, "expected.json"), "utf8")).files;

let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ""); } };

// ---- 1) ayrıştırıcı doğruluğu (mesaj bazında: gönderen+tür+zaman+metin)
const localIso = (d) => new Date(d.getTime() + 3 * 3600e3).toISOString().slice(0, 19);
let total = 0, good = 0;
for (const [file, exp] of Object.entries(expected)) {
  const r = parseWhatsAppText(fs.readFileSync(path.join(FX, file), "utf8"));
  ok(r.stats.platform === exp.platform, `${file}: platform`, r.stats.platform);
  ok(r.stats.date_order === exp.order, `${file}: tarih sırası`, r.stats.date_order);
  ok(r.stats.system === exp.system, `${file}: sistem satırı sayısı`, r.stats.system);
  ok(r.stats.is_group === exp.group, `${file}: grup tespiti`);
  ok(r.messages.length === exp.messages.length, `${file}: mesaj sayısı ${r.messages.length}/${exp.messages.length}`);
  exp.messages.forEach((em, i) => {
    total++;
    const m = r.messages[i];
    const okMsg = m && m.sender === em[0] && m.kind === em[1] && localIso(m.ts) === em[2] && (em[3] === null ? m.text === null : (m.text || "").startsWith(em[3]) || m.text === em[3]);
    if (okMsg) good++; else console.log("  ✗ ayrıştırma", file, i, JSON.stringify(m && { s: m.sender, k: m.kind, t: localIso(m.ts), x: (m.text || "").slice(0, 40) }), "!=", JSON.stringify(em));
  });
}
const acc = good / total;
ok(acc >= 0.9, `WhatsApp ayrıştırıcı doğruluğu ≥ %90 (${good}/${total} = ${(acc * 100).toFixed(1)}%)`);
console.log(`ayrıştırıcı doğruluğu: ${good}/${total} = ${(acc * 100).toFixed(1)}%`);

// ---- 2) sıra numarası (tekilleştirme)
{
  const r = parseWhatsAppText(fs.readFileSync(path.join(FX, "dup_same_minute.txt"), "utf8"));
  ok(r.messages[0].n === 1 && r.messages[1].n === 2 && r.messages[2].n === 1, "aynı dakika+gönderen+metin tekrarı sıra numarası alır", r.messages.map((m) => m.n));
  ok(r.messages[0].dedupeKey !== r.messages[2].dedupeKey, "farklı gönderen farklı anahtar");
}
// ---- 3) kenar durumlar
{
  const r1 = parseWhatsAppText("");
  ok(r1.messages.length === 0, "boş dosya → 0 mesaj");
  const r2 = parseWhatsAppText("Bu bir sohbet dosyası değil\nsatır 2");
  ok(r2.messages.length === 0 && r2.stats.ignored_leading_lines === 2, "başlık yok → 0 mesaj");
  const r3 = parseWhatsAppText("31.02.2026 10:00 - A: geçersiz tarih\n18.11.2026 10:00 - A: ok");
  ok(r3.messages.length === 1, "geçersiz tarih (31.02) mesaj sayılmaz", r3.messages.length);
  const r4 = parseWhatsAppText("\uFEFF\u200e18.11.2026\u00a010:00 - A: \u202aselam\u202c");
  ok(r4.messages.length === 1 && r4.messages[0].text === "selam", "BOM/LRM/NBSP/yön işaretleri temizlenir", r4.messages[0]);
  const big = "18.11.2026 10:00 - A: " + "x".repeat(20000);
  const r5 = parseWhatsAppText(big);
  ok(r5.messages.length === 0 || r5.messages[0].text.length <= 8000, "aşırı uzun satır kırpılır/yok sayılır");
  const many = Array.from({ length: 120 }, (_, i) => `18.11.2026 10:${String(i % 60).padStart(2, "0")} - A: m${i}`).join("\n");
  const r6 = parseWhatsAppText(many, { maxMessages: 50 });
  ok(r6.messages.length === 50 && r6.warnings.includes("message_limit"), "mesaj sınırı uygulanır", r6.messages.length);
  ok(titleFromFileName("WhatsApp Chat with Ayşe Test.txt") === "Ayşe Test", "dosya adı (EN)");
  ok(titleFromFileName("WhatsApp Sohbeti - Ayşe Test.zip") === "Ayşe Test", "dosya adı (TR)");
  ok(titleFromFileName("../../etc/WhatsApp Chat - Ahmet Test.txt") === "Ahmet Test", "dosya adı yol parçası atılır");
  ok(titleFromFileName("_chat.txt") === null, "_chat.txt başlık vermez");
}

// ---- 4) ZIP okuyucu (elle üretilen zip'ler)
function makeZip(entries) { // entries: [{name, data(Buffer), method?:0|8, flags?, fakeUsize?}]
  const locals = [], centrals = []; let off = 0;
  for (const e of entries) {
    const nameB = Buffer.from(e.name, "utf8");
    const method = e.method === undefined ? 8 : e.method;
    const comp = method === 8 ? zlib.deflateRawSync(e.data) : e.data;
    const crc = crc32(e.data);
    const usize = e.fakeUsize !== undefined ? e.fakeUsize : e.data.length;
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE((e.flags || 0) | 0x800, 6); lh.writeUInt16LE(method, 8);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(comp.length, 18); lh.writeUInt32LE(usize, 22); lh.writeUInt16LE(nameB.length, 26);
    const rec = Buffer.concat([lh, nameB, comp]);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE((e.flags || 0) | 0x800, 8); ch.writeUInt16LE(method, 10);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(usize, 24); ch.writeUInt16LE(nameB.length, 28); ch.writeUInt32LE(off, 42);
    locals.push(rec); centrals.push(Buffer.concat([ch, nameB])); off += rec.length;
  }
  const cd = Buffer.concat(centrals), eo = Buffer.alloc(22);
  eo.writeUInt32LE(0x06054b50, 0); eo.writeUInt16LE(entries.length, 8); eo.writeUInt16LE(entries.length, 10); eo.writeUInt32LE(cd.length, 12); eo.writeUInt32LE(off, 16);
  return Buffer.concat([...locals, cd, eo]);
}
const chat = fs.readFileSync(path.join(FX, "android_tr_24h.txt"));
const code = (fn) => { try { fn(); return null; } catch (e) { return e instanceof ZipError ? e.code : "other:" + e.message; } };
{
  const z = makeZip([{ name: "WhatsApp Chat - Ayşe Test.txt", data: chat }, { name: "IMG-1.jpg", data: Buffer.from("fakejpg") }]);
  const r = extractChatText(z);
  ok(r.text.equals(chat) && r.skipped === 1, "zip: sohbet .txt açılır, medya açılmaz", r.name);
  const z2 = makeZip([{ name: "_chat.txt", data: chat, method: 0 }]);
  ok(extractChatText(z2).text.equals(chat), "zip: depolanan (method 0) girdi");
  ok(code(() => extractChatText(makeZip([{ name: "../../etc/x.txt", data: chat }]))) === "zip_path_traversal", "zip: .. yol geçişi → ret");
  ok(code(() => extractChatText(makeZip([{ name: "a/../../x.txt", data: chat }]))) === "zip_path_traversal", "zip: a/../../ → ret");
  ok(code(() => extractChatText(makeZip([{ name: "/etc/passwd.txt", data: chat }]))) === "zip_path_traversal", "zip: mutlak yol → ret");
  ok(code(() => extractChatText(makeZip([{ name: "C:\\win\\x.txt", data: chat }]))) === "zip_path_traversal", "zip: sürücü/ters eğik çizgi → ret");
  ok(code(() => extractChatText(makeZip([{ name: "_chat.txt", data: chat }, { name: "..\\evil.png", data: Buffer.from("x") }]))) === "zip_path_traversal", "zip: açılmayacak girdide bile yol geçişi → ret");
  ok(code(() => extractChatText(makeZip([{ name: "foto.jpg", data: Buffer.from("x") }]))) === "zip_no_chat", "zip: .txt yok → ret");
  ok(code(() => extractChatText(makeZip([{ name: "_chat.txt", data: chat, flags: 1 }]))) === "zip_encrypted", "zip: şifreli → ret");
  // zip bombası: 40 MB sıfır → ~40 KB sıkıştırılmış (oran > 200) ; bildirilen boyut sınırı
  const bomb = Buffer.alloc(40 * 1024 * 1024);
  ok(code(() => extractChatText(makeZip([{ name: "_chat.txt", data: bomb }]))) === "zip_too_large", "zip bombası: 40MB açılmış boyut → ret");
  const bomb2 = Buffer.alloc(8 * 1024 * 1024);
  ok(code(() => extractChatText(makeZip([{ name: "_chat.txt", data: bomb2 }]))) === "zip_bomb", "zip bombası: yüksek sıkıştırma oranı → ret");
  // yalancı başlık: küçük boyut bildirir, gerçekte büyük açılır
  const lie = makeZip([{ name: "_chat.txt", data: Buffer.alloc(3 * 1024 * 1024), fakeUsize: 1000 }]);
  const lc = code(() => extractChatText(lie));
  ok(lc === "zip_bomb" || lc === "zip_invalid", "zip: bildirilenden büyük açılan veri → ret", lc);
  // CRC bozuk
  const bad = Buffer.from(makeZip([{ name: "_chat.txt", data: chat, method: 0 }])); bad[40] ^= 0xff;
  ok(code(() => extractChatText(bad)) === "zip_invalid", "zip: bozuk içerik (CRC) → ret");
  ok(code(() => extractChatText(Buffer.from("PK\x03\x04 çöp çöp çöp çöp çöp çöp"))) === "zip_invalid", "zip: çöp → ret");
  // çok girdi
  const many = Array.from({ length: 5001 }, (_, i) => ({ name: `m${i}.jpg`, data: Buffer.from("x") }));
  ok(code(() => extractChatText(makeZip(many))) === "zip_too_many", "zip: >5000 girdi → ret");
}

// ---- 5) çıkarıcı (kural tabanlı öneriler) — sabit "şimdi": 2026-11-20 08:00
{
  const now = new Date("2026-11-20T08:00:00+03:00");
  const r = parseWhatsAppText(fs.readFileSync(path.join(FX, "android_tr_24h.txt"), "utf8"));
  const msgs = r.messages.map((m) => ({ role: m.sender === "Usta Test" ? "owner" : "customer", sender: m.sender, content: m.text, sent_at: m.ts }));
  const sug = extractSuggestions(msgs, { now, customerName: "Ayşe Test" });
  const by = (i, k) => sug.filter((s) => s.msgIndex === i && s.kind === k);
  ok(by(4, "randevu").length === 0, "geçmişe düşen 'yarın' (mesaj 18 Kasım → 19 Kasım) için randevu önerilmez");
  const ap6 = by(6, "randevu")[0];
  ok(ap6 && ap6.payload.date === "2026-11-20" && ap6.payload.time === "14:00", "msg6: Çarşamba (18 Kas) gönderilen 'Cuma günü evdeyim, 14:00'te' → 20 Kasım 14:00 (göreli tarih MESAJ anına göre)", ap6 && ap6.payload);
  const pay = by(10, "hatirlatma")[0];
  ok(pay && pay.payload.date === "2026-11-23" && pay.payload.amount === 15000, "msg10: ödeme sözü → hatırlatma 23 Kasım, 15.000 TL", pay && pay.payload);
  ok(by(3, "not").some((s) => s.payload.tags.includes("olcu")), "msg3: ölçü notu");
  ok(by(2, "not").some((s) => s.payload.tags.includes("adres")), "msg2: adres notu");
  ok(by(9, "not").some((s) => /0500 000 00 01/.test(s.payload.body)), "msg9: telefon notu");
  ok(by(7, "not").some((s) => /45\.000 TL/.test(s.payload.body) && s.payload.tags.includes("fiyat")), "msg7: fiyat notu 45.000 TL");
  ok(by(11, "not").some((s) => s.payload.tags.includes("sikayet")), "msg11: şikâyet notu");
  ok(sug.some((s) => s.payload.tags && s.payload.tags.includes("son_durum")), "son durum özeti");
  ok(sug.every((s) => Number.isInteger(s.msgIndex) && s.msgIndex >= 0 && s.msgIndex < msgs.length), "her öneri kaynak mesaja bağlı");
  ok(new Set(sug.map((s) => s.dedupeKey)).size === sug.length, "öneri tekilleştirme anahtarları benzersiz");
  const sug2 = extractSuggestions(msgs, { now, customerName: "Ayşe Test" });
  ok(JSON.stringify(sug2.map((s) => s.dedupeKey)) === JSON.stringify(sug.map((s) => s.dedupeKey)), "çıkarım deterministik");
  // ios_tr: "Perşembe evdeyim" (19 Kasım Perşembe gönderildi → sonraki perşembe 26 Kasım)
  const r2 = parseWhatsAppText(fs.readFileSync(path.join(FX, "ios_tr.txt"), "utf8"));
  const m2 = r2.messages.map((m) => ({ role: m.sender === "Usta Test" ? "owner" : "customer", sender: m.sender, content: m.text, sent_at: m.ts }));
  const s2 = extractSuggestions(m2, { now, customerName: "Ayşe Test" });
  ok(s2.some((s) => s.kind === "randevu" && s.payload.date === "2026-11-26"), "ios: 'Perşembe evdeyim' → 26 Kasım randevu önerisi", s2.map((s) => [s.kind, s.payload.date]));
  ok(s2.some((s) => s.kind === "not" && /90x210/.test(s.payload.body)), "ios: kapı ölçüsü 90x210 notu");
  // kişisel veri sızıntısı: öneri gövdeleri yalnız mesaj parçalarını içerir
  ok(extractSuggestions([], { now }).length === 0, "boş girdi → öneri yok");
}
console.log(`\nunit_importer_v19: ${pass} geçti, ${fail} başarısız`);
process.exit(fail ? 1 : 0);
