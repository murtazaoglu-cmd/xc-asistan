// Uçtan uca DUMAN testi: `node src/server.js` + `node src/worker.js` AYRI süreçler olarak başlatılır (sahte saat: 2026-11-25 10:00 İstanbul).
// Kapsam: giriş, /config, /mobile/home, worker kalp atışı, brifing üretimi, komut çubuğu onay kartı → onay, fatura + KDV dönemi, içe aktarma (metin) + onay,
// bildirim kutusu, ortak A/B izolasyonu, saha finans kapalı. Önkoşul: TEMİZ veritabanı + migrate + seed (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234); cwd = backend.
// Kullanım: node test/smoke_e2e.js   (TEST_PORT varsayılan 4106)
const path = require("path");
const { spawn } = require("child_process");
const db = require("../src/db");
const ROOT = path.resolve(__dirname, "..");
const PORT = Number(process.env.TEST_PORT || 4106);
const B = `http://localhost:${PORT}/api`;
const FAKE = "2026-11-25T07:00:00Z";
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) { pass++; console.log("  ok  ", m); } else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 500) : ""); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function call(method, p, token, body) {
  const r = await fetch(B + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
const login = async (e) => (await call("POST", "/auth/login", null, { email: e, password: "pass1234" })).j?.token;

(async () => {
  const env = { ...process.env, PORT: String(PORT), APP_URL: `http://localhost:${PORT}`, ASSISTANT_FAKE_NOW: FAKE, WORKER_TICK_MS: "1000" };
  const api = spawn("node", ["src/server.js"], { cwd: ROOT, env, stdio: "ignore" });
  const wk = spawn("node", ["src/worker.js"], { cwd: ROOT, env, stdio: "ignore" });
  const stop = async () => { api.kill("SIGTERM"); wk.kill("SIGTERM"); await sleep(500); };
  try {
    for (let i = 0; i < 40; i++) { await sleep(250); try { if ((await fetch(B + "/health")).ok) break; } catch {} }
    ok((await call("GET", "/health")).j?.status === "ok", "GET /api/health");
    const [A, M, OA, OB, PA] = await Promise.all(["admin@x.com", "muh@x.com", "oa@x.com", "ob@x.com", "pa@x.com"].map(login));
    ok(A && M && OA && OB && PA, "5 rol girişi");
    let r = await call("GET", "/config", A); ok(r.s === 200 && r.j.server && r.j.flags, "GET /config", r.j && Object.keys(r.j));
    r = await call("GET", "/mobile/home", OA); ok(r.s === 200, "GET /mobile/home", r.s);
    // worker kalp atışı
    let hb = null; for (let i = 0; i < 20 && !hb; i++) { await sleep(500); const h = await call("GET", "/health/worker"); if (h.j && h.j.status === "ok") hb = h.j; }
    ok(!!hb, "GET /health/worker: worker canlı", hb);
    // brifing (worker planlar/çalıştırır; yoksa uç isteğe bağlı üretir)
    r = await call("GET", "/assistant/briefing/today", A); ok(r.s === 200 && r.j.kind === "morning" && r.j.date === "2026-11-25", "brifing üretildi (sahte saat 25 Kas)", r.j && { k: r.j.kind, d: r.j.date });
    // komut çubuğu
    r = await call("POST", "/assistant/commands", OA, { text: "yarın saat 15:00 Ali Veli ile keşif randevusu ekle" });
    ok(r.s < 300 && ["action_card", "clarify"].includes(r.j.kind), "komut çubuğu yanıtı", r.j);
    const offer = (await call("POST", "/offers", OA, { name: "Ali Veli", phone: "0532 111 22 33", service: "Pergola" })).j;
    r = await call("POST", "/assistant/commands", OA, { text: "yarın saat 15:00 Ali Veli ile keşif randevusu ekle" });
    ok(r.j.kind === "action_card", "onay kartı üretildi", r.j);
    if (r.j.kind === "action_card") {
      const id = r.j.action.id;
      ok(!(await db.query("SELECT 1 FROM appointments WHERE owner_id=(SELECT id FROM users WHERE email='oa@x.com') AND scheduled_at::date='2026-11-26'")).rows[0], "onaydan önce randevu YAZILMADI");
      const cf = await call("POST", `/assistant/actions/${id}/confirm`, OA, {}); ok(cf.s === 200 && cf.j.status === "uygulandi", "kart onaylandı → uygulandı", cf.j);
      ok(!!(await db.query("SELECT 1 FROM appointments WHERE scheduled_at::date='2026-11-26'")).rows[0], "onaydan sonra randevu yazıldı");
      ok((await call("POST", `/assistant/actions/${id}/confirm`, OB, {})).s === 404, "B, A'nın kartını onaylayamaz");
      const un = await call("POST", `/assistant/actions/${id}/undo`, OA, {}); ok(un.s === 200 && un.j.status === "geri_alindi", "geri al", un.j);
    }
    // fatura + KDV
    r = await call("POST", "/invoices", OA, { direction: "giden", issue_date: "2026-11-10", matrah_kurus: 1000000, kdv_oran: 20, invoice_no: "SMK-1", counterparty: "Ali Veli", due_date: "2026-12-10" });
    ok(r.s === 201 && r.j.kdv_kurus === 200000 && r.j.tutar_kurus === 1200000, "fatura + KDV hesabı (%20 → 2.000 TL)", r.j);
    r = await call("POST", "/vat/periods/2026-11/calculate", OA, {}); ok(r.s === 200, "KDV dönemi hesaplandı", r);
    r = await call("GET", "/vat/periods/2026-11", OA); ok(r.s === 200 && JSON.stringify(r.j).includes("200000"), "KDV dönem özeti hesaplanan KDV 200000 kuruş", r.s);
    { const lb = await call("GET", "/invoices", OB); ok(lb.s === 200 && Array.isArray(lb.j) && lb.j.length === 0, "B faturaları görmez", lb.j); }
    ok((await call("GET", "/invoices", await mkSaha(OA))).s === 403, "saha faturaya 403");
    // içe aktarma
    const chat = "[24.11.2026 10:15:00] Ali Veli: Merhaba, cuma günü keşfe gelebilir misiniz?\n[24.11.2026 10:16:00] Ben: Tabii, cuma 14:00 uygun mu\n[24.11.2026 10:17:00] Ali Veli: Olur, teşekkürler\n";
    r = await call("POST", "/assistant/imports", OA, { text: chat, source: "share", consent: true, consent_version: "2026-11-v1" });
    ok(r.s === 201, "içe aktarma önizlemesi", r);
    if (r.s === 201) { const cf = await call("POST", `/assistant/imports/${r.j.id || r.j.import.id}/confirm`, OA, { consent: true }); ok(cf.s < 300, "içe aktarma onayı", cf); }
    ok((await call("GET", "/assistant/conversations", OB)).j.items.length === 0, "B yazışmaları görmez");
    // bildirim kutusu (worker + brifing → inbox)
    await sleep(2500);
    r = await call("GET", "/assistant/inbox", A); ok(r.s === 200 && Array.isArray(r.j.items), "bildirim kutusu", r.s);
    // worker hatasız mı
    const q = await db.query("SELECT status, count(*)::int n FROM jobs GROUP BY status");
    ok(!q.rows.some((x) => x.status === "failed"), "kuyrukta KALICI başarısız iş yok", q.rows);
  } finally { await stop(); await db.pool.end(); }
  console.log(`\nsmoke_e2e: ${pass} geçti, ${fail} başarısız`);
  process.exit(fail ? 1 : 0);

  async function mkSaha(OAtok) {
    await call("POST", "/users", OAtok, { name: "Saha", email: "saha_smoke@x.com", password: "pass1234", role: "saha" });
    return login("saha_smoke@x.com");
  }
})().catch((e) => { console.error("ÇÖKTÜ:", e); process.exit(2); });
