// v16 güvenlik sertleştirme testleri (audit-security.md F-21..F-34). Her blok bir bulgunun İSTİSMAR senaryosudur:
// düzeltmeden önce başarısız, düzeltmeden sonra geçer.
// Önkoşul: TEMİZ veritabanı + migrate + seed; sunucu :4100'de (README bölüm 13 / 14 komutu), cwd = backend klasörü.
// Test, sahte WhatsApp (4101) ve SMTP (4102) sunucularını kendisi açar; bazı bloklar ek sunucu süreçleri (4110+) başlatır.
const http = require("http"), net = require("net"), fs = require("fs"), path = require("path"), crypto = require("crypto");
const { spawn } = require("child_process");
const db = require("../src/db"); // dotenv'i de yükler
const ROOT = path.resolve(__dirname, "..");
const B = "http://localhost:4100/api";
const ORIGIN = "http://localhost:4100";
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 700) : ""); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ipSeq = 0;
async function call(method, p, token, body, headers = {}, base = B) {
  // Anonim POST /offers 15 dk'da IP başına 20 ile sınırlı: her çağrıya ayrı (sahte) istemci IP'si ver (trust proxy 1)
  const xff = !token && method === "POST" && p.startsWith("/offers") && !headers["X-Forwarded-For"] ? { "X-Forwarded-For": `10.99.${Math.floor(++ipSeq / 250)}.${(ipSeq % 250) + 1}` } : {};
  const r = await fetch(base + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...xff, ...headers }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j, h: r.headers };
}
const login = async (e, pw = "pass1234") => (await call("POST", "/auth/login", null, { email: e, password: pw })).j?.token;
const DOCS_DIR = path.resolve(process.env.UPLOAD_DIR || path.join(ROOT, "uploads"), "documents");
const countDocs = () => (fs.existsSync(DOCS_DIR) ? fs.readdirSync(DOCS_DIR).length : 0);

// ---- sahte WhatsApp + SMTP ----
const wa = http.createServer((req, res) => {
  const chunks = []; req.on("data", (c) => chunks.push(c)); req.on("end", () => {
    res.setHeader("Content-Type", "application/json");
    if (req.url.endsWith("/media")) return res.end(JSON.stringify({ id: "media1" }));
    res.end(JSON.stringify({ messages: [{ id: "wamid.1" }] }));
  });
}).listen(4101);
const smtpRcpts = [];
const smtp = net.createServer((sock) => {
  let inData = false; sock.write("220 fake ESMTP\r\n"); let buf = "";
  sock.on("data", (d) => {
    buf += d.toString(); let idx;
    while ((idx = buf.indexOf("\r\n")) >= 0) {
      const line = buf.slice(0, idx); buf = buf.slice(idx + 2);
      if (inData) { if (line === ".") { inData = false; sock.write("250 queued\r\n"); } continue; }
      const u = line.toUpperCase();
      if (u.startsWith("EHLO") || u.startsWith("HELO")) sock.write("250 fake\r\n");
      else if (u.startsWith("MAIL")) sock.write("250 ok\r\n");
      else if (u.startsWith("RCPT")) { smtpRcpts.push(line); sock.write("250 ok\r\n"); }
      else if (u.startsWith("DATA")) { inData = true; sock.write("354 go\r\n"); }
      else if (u.startsWith("QUIT")) { sock.write("221 bye\r\n"); sock.end(); }
      else sock.write("250 ok\r\n");
    }
  });
  sock.on("error", () => {});
}).listen(4102);

// çoklu parça (multipart) yardımcı
async function upload(p, token, fieldName, filename, content, type = "application/octet-stream", extra = {}) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(extra)) fd.append(k, v);
  fd.append(fieldName, new Blob([content], { type }), filename);
  const r = await fetch(B + p, { method: "POST", headers: token ? { Authorization: "Bearer " + token } : {}, body: fd, signal: AbortSignal.timeout(20000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n");
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex");
const HTML = Buffer.from("<html><body><script>alert(1)</script></body></html>");

(async () => {
  const [A, M, OA, OB, PA] = await Promise.all(["admin@x.com", "muh@x.com", "oa@x.com", "ob@x.com", "pa@x.com"].map((e) => login(e)));
  ok(A && M && OA && OB && PA, "logins");
  const me = async (t) => (await call("GET", "/auth/me", t)).j.user;
  const [uA, uOA, uOB, uPA] = await Promise.all([A, OA, OB, PA].map(me));

  // ============ F-21: doğrulanmamış e-posta → nodemailer DoS ============
  {
    const base = { name: "Dos Deneme", phone: "0500 000 00 21", service: "Pergola" };
    const t0 = Date.now();
    const r1 = await call("POST", "/offers", null, { ...base, email: "a,".repeat(20000) });
    ok(r1.s === 400 && Date.now() - t0 < 2000, "F-21: 40KB virgüllü e-posta intake'te 400 ve hızlı reddedilir", { s: r1.s, ms: Date.now() - t0 });
    ok((await call("POST", "/offers", null, { ...base, email: "a@b.com, evil@x.com" })).s === 400, "F-21: iki adres/virgül reddedilir");
    ok((await call("POST", "/offers", null, { ...base, email: "ali veli@x.com" })).s === 400, "F-21: boşluklu e-posta reddedilir");
    ok((await call("POST", "/offers", null, { ...base, email: "Ali <ali@x.com>" })).s === 400, "F-21: görünen-ad biçimi reddedilir");
    ok((await call("POST", "/offers", null, { ...base, email: "a".repeat(300) + "@x.com" })).s === 400, "F-21: 254+ karakter reddedilir");
    ok((await call("POST", "/offers", null, { ...base, email: ["a@b.com"] })).s === 400, "F-21: dizi tipi reddedilir");
    ok((await call("POST", "/offers", null, { ...base, email: "x@y" })).s === 400, "F-21: noktasız alan adı reddedilir");
    const good = await call("POST", "/offers", null, { ...base, email: "  Musteri@Ornek.com.tr " });
    ok(good.s === 201, "F-21: geçerli e-posta kabul", good.j);
    const gOffer = (await call("GET", "/offers/" + good.j.id, A)).j;
    ok(gOffer.email === "Musteri@Ornek.com.tr", "F-21: e-posta kırpılarak saklanır", gOffer.email);
    const empty = await call("POST", "/offers", null, { ...base, email: "" });
    ok(empty.s === 201 && (await call("GET", "/offers/" + empty.j.id, A)).j.email === null, "F-21: boş e-posta → null (geriye uyum)");
    // PATCH
    ok((await call("PATCH", "/offers/" + good.j.id, A, { email: "x,".repeat(10000) })).s === 400, "F-21: PATCH geçersiz e-posta 400");
    ok((await call("PATCH", "/offers/" + good.j.id, A, { email: null })).j.email === null, "F-21: PATCH null e-postayı temizler");
    // Eski (doğrulanmamış) kayıt: veritabanında kötü e-posta; gönderim sürecin çökmesine/kilitlenmesine yol açmamalı
    await call("POST", "/quotes/" + good.j.id, A, { items: [{ desc: "x", qty: 1, price: 100 }] });
    // (v16 şeması aşırı uzun e-postayı veritabanında da engeller; eski veriyi taklit için kısıt geçici kaldırılır)
    await db.query("ALTER TABLE offers DROP CONSTRAINT offers_email_len_chk");
    await db.query("UPDATE offers SET email = $1 WHERE id = $2", ["a,".repeat(30000), good.j.id]);
    ok(true, "legacy kayıt hazır");
    const t1 = Date.now();
    const snd = await call("POST", "/quotes/" + good.j.id + "/send", A);
    ok(Date.now() - t1 < 4000 && snd.j && snd.j.channels && snd.j.channels.email.sent === false && /geçersiz/i.test(snd.j.channels.email.error || ""), "F-21: eski kötü e-posta gönderimde güvenle reddedilir (süreç yaşar)", { ms: Date.now() - t1, j: snd.j });
    ok((await fetch(ORIGIN + "/api/health")).status === 200, "F-21: API ayakta");
    ok(!smtpRcpts.some((l) => /a,a,a,/.test(l)), "F-21: SMTP'ye kötü alıcı gitmedi");
    await db.query("UPDATE offers SET email = NULL WHERE id = $1", [good.j.id]);
    await db.query("ALTER TABLE offers ADD CONSTRAINT offers_email_len_chk CHECK (email IS NULL OR length(email) <= 254)");
    let chk = null; try { await db.query("UPDATE offers SET email = $1 WHERE id = $2", ["x".repeat(300), good.j.id]); } catch (e) { chk = e.code; }
    ok(chk === "23514", "F-21: veritabanı CHECK kısıtı 254+ karakteri reddeder", chk);
    // kullanıcı e-postası da doğrulanır
    ok((await call("POST", "/users", A, { name: "Kotu", email: "a,b@x.com", password: "abcdef", role: "saha" })).s === 400, "F-21: kullanıcı e-postası doğrulanır");
  }

  // ============ F-22 / F-24: paylaşımlı projede başkasının defterine yazma + paid_amount ============
  const prj = (await call("POST", "/projects", OA, { customer_name: "Paylasimli Proje", service: "Demir", total_amount: 50000 })).j;
  {
    ok(prj.id, "proje oluştu", prj);
    const sh = await call("POST", "/shares", A, { resource_type: "project", resource_id: prj.id, user_id: uOB.id });
    ok(sh.s === 201, "admin projeyi OB ile paylaştı", sh.j);
    const own = (await call("POST", "/projects/" + prj.id + "/payments", OA, { amount: 1000, method: "Nakit", note: "OA gercek" })).j;
    ok(own.id, "OA ödeme girdi", own);
    const adm = await call("POST", "/projects/" + prj.id + "/payments", A, { amount: 5000, method: "Havale", note: "Admin kasa" });
    ok(adm.s === 201, "admin ödeme");
    // İSTİSMAR: OB, OA'nın defterine yazmaya çalışır
    const fake = await call("POST", "/projects/" + prj.id + "/payments", OB, { amount: 999999, method: "Nakit", owner_id: uOA.id, note: "sahte tahsilat" });
    ok(fake.s === 201 && String(fake.j.owner_id) === String(uOB.id), "F-22: OB'nin owner_id=OA isteği OB'nin kendi defterine düşer", fake.j);
    const oaList = (await call("GET", "/projects/" + prj.id + "/payments", OA)).j;
    ok(!oaList.some((p) => p.note === "sahte tahsilat") && oaList.length === 1, "F-22: OA defterinde sahte ödeme yok", oaList);
    const fakeE = await call("POST", "/projects/" + prj.id + "/expenses", OB, { category: "Sahte", amount: 123456, owner_id: uOA.id });
    ok(fakeE.s === 201 && String(fakeE.j.owner_id) === String(uOB.id), "F-22: sahte gider de OB'nin defterine düşer", fakeE.j);
    const oaExp = (await call("GET", "/projects/" + prj.id + "/expenses", OA)).j;
    ok(!oaExp.some((e) => e.category === "Sahte"), "F-22: OA gider defterinde sahte kayıt yok");
    // PATCH ile devretme denemesi (kendi kaydını OA'ya atamak)
    const pt = await call("PATCH", "/projects/payments/" + fake.j.id, OB, { owner_id: uOA.id });
    ok(pt.s === 200 && String(pt.j.owner_id) === String(uOB.id), "F-22: PATCH ile OA'ya devretme etkisiz", pt.j);
    // Meşru: proje sahibi (OA) paylaşılan OB'ye atayabilir; admin her kullanıcıya
    const asg = await call("POST", "/projects/" + prj.id + "/payments", OA, { amount: 10, method: "Nakit", owner_id: uOB.id });
    ok(asg.s === 201 && String(asg.j.owner_id) === String(uOB.id), "F-22: proje sahibi paylaşılan kişiye atayabilir (meşru akış korunur)", asg.j);
    const asgA = await call("POST", "/projects/" + prj.id + "/payments", A, { amount: 11, method: "Nakit", owner_id: uPA.id });
    ok(asgA.s === 201 && String(asgA.j.owner_id) === String(uPA.id), "F-22: admin başkasına atayabilir");
    // PA (paylaşılmamış) projeye hiç yazamaz
    ok((await call("POST", "/projects/" + prj.id + "/payments", PA, { amount: 1, method: "Nakit", owner_id: uOA.id })).s === 403, "F-22: paylaşılmamış kullanıcı 403");

    // F-24: paid_amount yalnız çağıranın defteri
    const lA = (await call("GET", "/projects", A)).j.find((p) => p.id === prj.id);
    const lOA = (await call("GET", "/projects", OA)).j.find((p) => p.id === prj.id);
    const lOB = (await call("GET", "/projects", OB)).j.find((p) => p.id === prj.id);
    ok(Number(lOA.paid_amount) === 1000, "F-24: OA paid_amount yalnız kendi defteri (1000)", lOA.paid_amount);
    ok(Number(lOB.paid_amount) === 999999 + 10, "F-24: OB paid_amount yalnız kendi defteri", lOB.paid_amount);
    ok(Number(lA.paid_amount) === 5000, "F-24: admin paid_amount işletme defteri (5000)", lA.paid_amount);
    // müşteri geçmişi
    const off = (await call("POST", "/offers", OA, { name: "Gecmis Musteri", phone: "0533 777 66 55", service: "Cam" })).j;
    await call("PATCH", "/offers/" + off.id + "/status", OA, { status: "Kabul Edildi" });
    const pr2 = (await call("GET", "/projects", OA)).j.find((p) => p.offer_id === off.id);
    await call("POST", "/projects/" + pr2.id + "/payments", OA, { amount: 300, method: "Nakit" });
    await call("POST", "/projects/" + pr2.id + "/payments", A, { amount: 900, method: "Nakit" });
    const cust = (await call("GET", "/customers/05337776655", OA)).j;
    ok(cust.projects.length === 1 && Number(cust.projects[0].paid_amount) === 300, "F-24: /customers/:phoneKey paid_amount yalnız çağıranın defteri", cust.projects);
  }

  // ============ F-23: görev PATCH atama doğrulaması ============
  {
    const tk = await call("POST", "/projects/" + prj.id + "/tasks", OB, { title: "OB gorevi" });
    ok(tk.s === 201, "OB görev oluşturdu", tk.j);
    const t = tk.j.id;
    const toAdmin = await call("PATCH", "/projects/tasks/" + t, OB, { assigned_user_id: uA.id });
    ok(toAdmin.s === 400, "F-23: projeyle ilgisiz admin'e atama 400", toAdmin.j);
    ok((await call("PATCH", "/projects/tasks/" + t, OB, { assigned_user_id: uPA.id })).s === 400, "F-23: paylaşılmamış kullanıcıya atama 400");
    const toOwner = await call("PATCH", "/projects/tasks/" + t, OB, { assigned_user_id: uOA.id });
    ok(toOwner.s === 200 && String(toOwner.j.assigned_user_id) === String(uOA.id), "F-23: proje sahibine atama serbest", toOwner.j);
    ok((await call("PATCH", "/projects/tasks/" + t, OB, { assigned_user_id: "kesin-uuid-degil" })).s === 400, "F-23: geçersiz uuid 400");
    const un = await call("PATCH", "/projects/tasks/" + t, OB, { assigned_user_id: null });
    ok(un.s === 200 && un.j.assigned_user_id === null, "F-23: null atamayı kaldırır (geriye uyum)", un.j);
  }

  // ============ F-27: push SSRF ============
  {
    let hits = 0;
    const trap = net.createServer((s) => { hits++; s.destroy(); }).listen(4443, "127.0.0.1");
    const keys = { p256dh: "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM", auth: "tBHItJI5svbpez7KI4CCXg" };
    const sub = (t, endpoint) => call("POST", "/push/subscribe", t, { endpoint, keys });
    for (const bad of ["https://127.0.0.1:4443/internal?x=1", "http://127.0.0.1:4100/api/health", "https://localhost:4443/x", "https://169.254.169.254/latest", "https://[::1]/x",
      "https://evil.example.com/fcm/send/abc", "https://fcm.googleapis.com.evil.com/fcm/send/abc", "https://user:pw@fcm.googleapis.com/fcm/send/abc",
      "https://fcm.googleapis.com:4443/fcm/send/abc", "ftp://fcm.googleapis.com/x", "javascript:alert(1)", "https://evilfcm.googleapis.com.attacker.io/", "not a url", "https://fcm.googleapis.com./x"]) {
      const r = await sub(PA, bad);
      ok(r.s === 400, "F-27: kötü endpoint reddedilir: " + bad, r.s);
    }
    const good = "https://fcm.googleapis.com/fcm/send/abcDEF123-" + Date.now();
    ok((await sub(PA, good)).s === 201, "F-27: fcm.googleapis.com kabul");
    ok((await sub(PA, "https://updates.push.services.mozilla.com/wpush/v2/abc" + Date.now())).s === 201, "F-27: mozilla kabul");
    ok((await sub(PA, "https://wns2-par02p.notify.windows.com/w/?token=abc" + Date.now())).s === 201, "F-27: windows kabul");
    ok((await call("POST", "/push/subscribe", PA, { endpoint: good, keys: { p256dh: "x", auth: "y" } })).s === 400, "F-27: geçersiz anahtar biçimi 400");
    // sahiplik: OB başkasının aboneliğini silemez
    const un = await call("POST", "/push/unsubscribe", OB, { endpoint: good });
    const still = (await db.query("SELECT 1 FROM push_subscriptions WHERE endpoint = $1", [good])).rowCount;
    ok(still === 1, "F-27: OB, PA'nın aboneliğini silemez", { s: un.s, still });
    await call("POST", "/push/unsubscribe", PA, { endpoint: good });
    ok((await db.query("SELECT 1 FROM push_subscriptions WHERE endpoint = $1", [good])).rowCount === 0, "F-27: sahibi kendi aboneliğini siler");
    // eski kötü satır: gönderimde asla bağlanılmaz ve silinir
    await db.query("INSERT INTO push_subscriptions (endpoint, p256dh, auth, user_id) VALUES ($1,$2,$3,$4)", ["https://127.0.0.1:4443/legacy", keys.p256dh, keys.auth, uA.id]);
    await call("POST", "/offers", null, { name: "Push Tetik", phone: "0500 000 00 27", service: "Cam" });
    await sleep(1500);
    ok(hits === 0, "F-27: sunucu dahili adrese bağlanmadı", hits);
    ok((await db.query("SELECT 1 FROM push_subscriptions WHERE endpoint = 'https://127.0.0.1:4443/legacy'")).rowCount === 0, "F-27: eski kötü abonelik gönderimde temizlendi");
    // kullanıcı başına üst sınır
    await db.query("DELETE FROM push_subscriptions WHERE user_id = $1", [uPA.id]);
    let last = 201;
    for (let i = 0; i < 22; i++) last = (await sub(PA, "https://fcm.googleapis.com/fcm/send/cap" + i + "-" + Date.now())).s;
    ok(last === 429 || last === 400, "F-27: kullanıcı başına abonelik sınırı", last);
    await db.query("DELETE FROM push_subscriptions WHERE user_id = $1", [uPA.id]);
    trap.close();
  }

  // ============ F-28: jeton iptali ============
  {
    const nu = await call("POST", "/users", A, { name: "Gecici Muh", email: "gecici@x.com", password: "abcdef", role: "muhasebe" });
    ok(nu.s === 201, "geçici muhasebe oluştu", nu.j);
    const tk = await login("gecici@x.com", "abcdef");
    ok((await call("GET", "/offers", tk)).s === 200, "F-28: silmeden önce jeton çalışır");
    ok((await call("DELETE", "/users/" + nu.j.id, A)).s === 200, "kullanıcı silindi");
    const after = await call("GET", "/offers", tk);
    ok(after.s === 401, "F-28: silinen kullanıcının jetonu ANINDA reddedilir", after.s);
    ok((await call("GET", "/dashboard-init", tk)).s === 401 && (await call("GET", "/customers", tk)).s === 401, "F-28: diğer uçlar da 401");
    // silinmiş kullanıcının jetonu hız sınırını atlatmamalı
    let lim = 0;
    for (let i = 0; i < 24; i++) { const r = await call("POST", "/offers", tk, { name: "x" }, { "X-Forwarded-For": "203.0.113.77" }); if (r.s === 429) { lim = i + 1; break; } }
    ok(lim > 0 && lim <= 22, "F-28: iptal edilmiş jeton anonim hız sınırını atlatamaz", lim);
    // rol düşürme: veritabanında rol değişince en geç 60 sn içinde yansır (önbellek 10 sn)
    const n2 = await call("POST", "/users", A, { name: "Rol Dus", email: "roldus@x.com", password: "abcdef", role: "ortak" });
    const t2 = await login("roldus@x.com", "abcdef");
    ok((await call("GET", "/users", t2)).s === 200, "F-28: ortak kullanıcı listesini görür");
    await db.query("UPDATE users SET role = 'saha' WHERE id = $1", [n2.j.id]);
    let demoted = false; const tt = Date.now();
    while (Date.now() - tt < 30000) { if ((await call("GET", "/users", t2)).s === 403) { demoted = true; break; } await sleep(1000); }
    ok(demoted && Date.now() - tt < 60000, "F-28: rolü düşürülen kullanıcının eski yetkisi ≤60 sn içinde kalkar", Date.now() - tt);
    // algoritma sabitleme (alg confusion)
    const forged = require("jsonwebtoken").sign({ id: uA.id, role: "admin", tv: 0 }, process.env.JWT_SECRET, { algorithm: "HS512" });
    ok((await call("GET", "/users", forged)).s === 401, "F-32: HS512 ile imzalı jeton reddedilir");
  }

  // ============ F-25 / F-26: belge yükleme + /uploads yetkisi ============
  {
    const offOA = (await call("POST", "/offers", OA, { name: "Belge Musteri", phone: "0500 000 00 25", service: "Cam" })).j;
    const n0 = countDocs();
    const forbid = await upload("/documents/offer/" + offOA.id, OB, "file", "yetkisiz.pdf", PDF);
    ok(forbid.s === 403 && countDocs() === n0, "F-25: yetkisiz yükleme 403 ve diske HİÇ yazılmaz", { s: forbid.s, d: countDocs() - n0 });
    const ghost = await upload("/documents/offer/" + crypto.randomUUID(), A, "file", "hayalet.pdf", PDF);
    ok(ghost.s === 404 && countDocs() === n0, "F-25: olmayan kayda yükleme 404 ve diske yazılmaz", { s: ghost.s, d: countDocs() - n0 });
    ok((await upload("/documents/offer/" + offOA.id, null, "file", "a.pdf", PDF)).s === 401, "F-25: oturumsuz yükleme 401");
    for (const name of ["x.shtml", "x.xhtml", "x.svgz", "x.svg", "x.html ", "x.php5", "x.mht", "x.xsl", "x.swf", "x.es", "x.html", "x.HTM", "x.js", "noext", "x.pdf.exe", "x.exe", "x.jsp", "x.xml", "x.hta"]) {
      const r = await upload("/documents/offer/" + offOA.id, OA, "file", name, HTML);
      ok(r.s === 400, "F-25: izinli olmayan tür reddedilir: " + JSON.stringify(name), r.s);
    }
    ok(countDocs() === n0, "F-25: reddedilen dosyalar diskte kalmadı", countDocs() - n0);
    const spoof = await upload("/documents/offer/" + offOA.id, OA, "file", "sahte.pdf", HTML, "application/pdf");
    ok(spoof.s === 400 && countDocs() === n0, "F-25: uzantı pdf ama içerik HTML → 400 (içerik doğrulaması)", spoof.s);
    ok((await upload("/documents/offer/" + offOA.id, OA, "file", "sahte.png", PDF, "image/png")).s === 400, "F-25: png uzantılı pdf içerik → 400");
    const up = await upload("/documents/offer/" + offOA.id, OA, "file", "Sözleşme Ş.pdf", PDF, "application/pdf");
    ok(up.s === 201 && up.j.file_url && /exp=\d+&sig=/.test(up.j.file_url), "F-25/F-26: geçerli pdf 201 ve file_url imzalı", up.j);
    const png = await upload("/documents/offer/" + offOA.id, OA, "file", "foto.PNG", PNG, "image/png");
    ok(png.s === 201, "F-25: png kabul", png.j);
    // F-26: erişim
    const signed = up.j.file_url;
    const bare = signed.split("?")[0];
    ok((await fetch(bare)).status === 401, "F-26: imzasız anonim erişim 401");
    const s1 = await fetch(signed);
    ok(s1.status === 200 && /pdf/.test(s1.headers.get("content-type") || "") && (await s1.arrayBuffer()).byteLength === PDF.length, "F-26: imzalı bağlantı Authorization olmadan açılır (<img>/<a> uyumlu)");
    const exp = Number(new URL(signed).searchParams.get("exp")); const left = exp - Math.floor(Date.now() / 1000);
    ok(left > 540 && left <= 600, "F-26: imza ömrü 10 dk", left);
    ok((await fetch(signed.replace(/sig=[^&]+/, "sig=AAAA"))).status === 401, "F-26: bozuk imza 401");
    ok((await fetch(signed.replace(/exp=\d+/, "exp=" + (exp + 86400)))).status === 401, "F-26: exp değiştirilirse 401");
    ok((await fetch(signed.replace(/exp=\d+/, "exp=" + (exp - 700)))).status === 401, "F-26: süresi geçmiş 401");
    const other = png.j.file_url.split("?")[0] + "?" + signed.split("?")[1];
    ok((await fetch(other)).status === 401, "F-26: imza başka dosyada geçmez");
    const hb = await fetch(bare, { headers: { Authorization: "Bearer " + OA } });
    ok(hb.status === 200, "F-26: Authorization başlığıyla (sahibi) erişim 200", hb.status);
    ok((await fetch(bare, { headers: { Authorization: "Bearer " + OB } })).status === 403, "F-26: başka ortağın jetonuyla 403");
    ok((await fetch(bare, { headers: { Authorization: "Bearer " + A } })).status === 200, "F-26: admin jetonuyla 200");
    ok((await fetch(bare, { headers: { Authorization: "Bearer bozuk" } })).status === 401, "F-26: geçersiz jeton 401");
    // liste uç noktası yeni imza üretir; /documents/file/:id akışı
    const lst = (await call("GET", "/documents/offer/" + offOA.id, OA)).j;
    ok(lst.length === 2 && lst.every((d) => /sig=/.test(d.file_url)), "F-26: liste imzalı adres döner", lst);
    ok((await call("GET", "/documents/offer/" + offOA.id, OB)).s === 403, "F-26: liste yetkisiz 403");
    const streamed = await fetch(B + "/documents/file/" + lst[0].id, { headers: { Authorization: "Bearer " + OA } });
    ok(streamed.status === 200, "F-26: GET /documents/file/:id yetkili akış", streamed.status);
    ok((await fetch(B + "/documents/file/" + lst[0].id, { headers: { Authorization: "Bearer " + OB } })).status === 403, "F-26: /documents/file/:id yetkisiz 403");
    ok((await fetch(B + "/documents/file/" + lst[0].id)).status === 401, "F-26: /documents/file/:id oturumsuz 401");
    // başlıklar: pdf inline, pdf-olmayan indirme
    ok(/nosniff/i.test(s1.headers.get("x-content-type-options") || ""), "F-26: nosniff");
    const txt = await upload("/documents/offer/" + offOA.id, OA, "file", "not.txt", Buffer.from("merhaba"), "text/plain");
    ok(txt.s === 201, "F-25: txt kabul");
    const tr = await fetch(txt.j.file_url);
    ok(/attachment/i.test(tr.headers.get("content-disposition") || ""), "F-26: görüntü/pdf dışı türler attachment olarak servis edilir", tr.headers.get("content-disposition"));
    // yol gezme / dizin listeleme
    for (const p of ["/uploads/", "/uploads/documents/", "/uploads/documents", "/uploads/../.env", "/uploads/%2e%2e/.env", "/uploads/documents/..%2f..%2f.env", "/uploads/documents/%2e%2e%2f%2e%2e%2f.env", "/uploads//etc/passwd"]) {
      const r = await fetch(ORIGIN + p, { headers: { Authorization: "Bearer " + A } });
      const body = await r.text();
      ok(r.status >= 400 && !/JWT_SECRET|DATABASE_URL|root:/.test(body), "F-26: yol gezme/dizin listeleme engelli " + p, r.status);
    }
    // silme: dosya diskten kalkar, bağlantı 404
    const delDoc = (await call("GET", "/documents/offer/" + offOA.id, OA)).j.find((d) => d.file_name === "not.txt");
    const diskName = decodeURIComponent(new URL(txt.j.file_url).pathname.split("/").pop());
    ok(fs.existsSync(path.join(DOCS_DIR, diskName)), "dosya diskte");
    ok((await call("DELETE", "/documents/" + delDoc.id, OB)).s === 403, "F-26: başkası belge silemez");
    ok((await call("DELETE", "/documents/" + delDoc.id, OA)).s === 200, "belge silindi");
    ok(!fs.existsSync(path.join(DOCS_DIR, diskName)), "F-26: silinen belge diskten de silindi");
    ok((await fetch(txt.j.file_url)).status === 404, "F-26: silinen belgenin imzalı bağlantısı 404");

    // Teklif PDF'i (quotes/send) imzalı; müşteriye giden WhatsApp bağlantısı takip sayfasıdır
    await call("POST", "/quotes/" + offOA.id, OA, { items: [{ desc: "Cam", qty: 1, price: 1000 }] });
    const snd = await call("POST", "/quotes/" + offOA.id + "/send", OA);
    ok(snd.j.pdfUrl && /sig=/.test(snd.j.pdfUrl), "F-26: pdfUrl imzalı", snd.j.pdfUrl);
    const pr = await fetch(snd.j.pdfUrl);
    ok(pr.status === 200 && /pdf/.test(pr.headers.get("content-type") || ""), "F-26: imzalı teklif PDF'i anonim açılır", pr.status);
    ok((await fetch(snd.j.pdfUrl.split("?")[0])).status === 401, "F-26: imzasız teklif PDF'i 401");
    ok((await fetch(snd.j.pdfUrl.split("?")[0], { headers: { Authorization: "Bearer " + OB } })).status === 403, "F-26: başka ortak teklif PDF'ini çekemez");
    ok((await fetch(snd.j.pdfUrl.split("?")[0], { headers: { Authorization: "Bearer " + OA } })).status === 200, "F-26: sahibi teklif PDF'ini Authorization ile çeker");
    ok(!/sig=/.test(decodeURIComponent(snd.j.whatsappUrl)), "F-26: müşteriye giden wa.me metnine kısa ömürlü imza konmaz");

    // Galeri
    const gp = (await call("POST", "/projects", A, { customer_name: "Galeri Proje", service: "Cam" })).j;
    ok((await upload("/gallery/project/" + gp.id, A, "photo", "x.svg", Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>"), "image/svg+xml")).s === 400, "F-25: galeri svg reddedilir");
    ok((await upload("/gallery/project/" + gp.id, A, "photo", "x.png", HTML, "image/png")).s === 400, "F-25: galeri sahte png (HTML içerik) reddedilir");
    const gN = fs.readdirSync(path.resolve(process.env.UPLOAD_DIR || path.join(ROOT, "uploads"), "gallery")).length;
    ok((await upload("/gallery/project/" + crypto.randomUUID(), A, "photo", "x.png", PNG, "image/png")).s === 404 && fs.readdirSync(path.resolve(process.env.UPLOAD_DIR || path.join(ROOT, "uploads"), "gallery")).length === gN, "F-25: olmayan projeye galeri yüklemesi 404, diske yazılmaz");
    const gu = await upload("/gallery/project/" + gp.id, A, "photo", "ok.png", PNG, "image/png", { published: "false" });
    ok(gu.s === 201 && /sig=/.test(gu.j.image_url), "galeri: yayınlanmamış görsel imzalı adres döner", gu.j);
    ok((await fetch(gu.j.image_url.split("?")[0])).status === 401, "F-26: yayınlanmamış galeri görseli imzasız 401");
    ok((await fetch(gu.j.image_url)).status === 200, "F-26: yayınlanmamış galeri görseli imzayla 200");
    await call("PATCH", "/gallery/" + gu.j.id, A, { published: true });
    ok((await fetch(gu.j.image_url.split("?")[0])).status === 200, "F-26: yayınlanmış galeri görseli herkese açık (site için)");
    const pubList = (await call("GET", "/gallery/published", null)).j;
    ok(Array.isArray(pubList) && pubList.some((g) => g.id === gu.j.id), "galeri: public liste çalışır");
    await call("DELETE", "/gallery/" + gu.j.id, A);
  }

  // ============ F-29: kabul edilmiş teklif geri alınamaz ============
  {
    const o = (await call("POST", "/offers", OA, { name: "Durum Test", phone: "0500 000 00 29", service: "Cam" })).j;
    ok((await call("PATCH", "/offers/" + o.id + "/status", OA, { status: "Kabul Edildi" })).s === 200, "kabul");
    ok((await call("PATCH", "/offers/" + o.id + "/status", OA, { status: "Kabul Edildi" })).s === 200, "F-29: aynı durumu tekrar göndermek zararsız (idempotent)");
    const back = await call("PATCH", "/offers/" + o.id + "/status", OA, { status: "Yeni" });
    ok(back.s === 409, "F-29: kabul edilmiş teklif ortak tarafından geri alınamaz", back.s);
    const bulk = await call("PATCH", "/offers/bulk-status", OA, { ids: [o.id], status: "Yeni" });
    ok(bulk.j.updated === 0, "F-29: toplu durumda da geri alınamaz", bulk.j);
    ok((await call("GET", "/offers/" + o.id, A)).j.status === "Kabul Edildi", "F-29: durum korundu");
    ok((await call("PATCH", "/offers/" + o.id + "/status", A, { status: "Reddedildi" })).s === 200, "F-29: admin düzeltebilir (bilinçli istisna)");
    const o2 = (await call("POST", "/offers", OA, { name: "Durum Test 2", phone: "0500 000 00 30", service: "Cam" })).j;
    ok((await call("PATCH", "/offers/" + o2.id + "/status", OA, { status: "Reddedildi" })).s === 200 && (await call("PATCH", "/offers/" + o2.id + "/status", OA, { status: "Yeni" })).s === 200, "F-29: reddedilen yeniden açılabilir (panel akışı korunur)");
  }

  // ============ F-30: public form girdi sınırları ============
  {
    const base = { name: "Form Test", phone: "0500 000 00 31", service: "Cam" };
    ok((await call("POST", "/offers", null, { ...base, message: "m".repeat(2001) })).s === 400, "F-30: 2001 karakter mesaj 400");
    ok((await call("POST", "/offers", null, { ...base, message: "m".repeat(2000) })).s === 201, "F-30: 2000 karakter mesaj kabul");
    const r = await call("POST", "/offers", null, { ...base, region: "R".repeat(500), source_site: "<x>", photo_urls: ["javascript:alert(1)", "http://169.254.169.254/", "https://127.0.0.1/x", "https://10.0.0.5/x", "https://localhost/x", "https://[::1]/x", "https://u:p@good.example.com/x", "https://good.example.com/a.jpg", "https://cdn.example.org/b.png", 42, "https://" + "a".repeat(600) + ".com/x"] });
    ok(r.s === 201, "F-30: kötü URL'ler form'u düşürmez", r.j);
    const row = (await call("GET", "/offers/" + r.j.id, A)).j;
    ok(JSON.stringify(row.photo_urls) === JSON.stringify(["https://good.example.com/a.jpg", "https://cdn.example.org/b.png"]), "F-30: yalnız genel https URL'leri saklanır", row.photo_urls);
    ok(row.source_site === "controlx", "F-30: bilinmeyen source_site varsayılana çekilir", row.source_site);
    ok(row.region.length === 200, "F-30: region 200 karaktere kırpılır", row.region.length);
    ok((await call("POST", "/offers", null, { ...base, source_site: "xmetal" })).s === 201 && (await call("POST", "/offers", null, { ...base, source_site: "nicebodrum" })).s === 201, "F-30: bilinen source_site değerleri kabul");
    ok((await call("POST", "/offers", null, { ...base, name: { a: 1 } })).s === 400, "F-30: nesne tipli ad 400");
    ok((await call("PATCH", "/offers/" + r.j.id, A, { message: "m".repeat(2001) })).s === 400, "F-30: PATCH uzun mesaj 400");
    const big = await fetch(B + "/offers", { method: "POST", headers: { "Content-Type": "application/json", "X-Forwarded-For": "10.98.0.1" }, body: JSON.stringify({ ...base, message: "z".repeat(300000) }) });
    ok(big.status === 413 || big.status === 400, "F-30: 300KB gövde reddedilir (public sınır 100KB)", big.status);
  }

  // ============ F-31 / bağımlılıklar ============
  {
    const ver = (n) => JSON.parse(fs.readFileSync(path.join(ROOT, "node_modules", n, "package.json"), "utf8")).version;
    const major = (n) => Number(ver(n).split(".")[0]);
    ok(major("nodemailer") >= 10, "F-31: nodemailer ≥ 10 (GHSA yamalı)", ver("nodemailer"));
    ok(major("multer") >= 2, "F-31: multer ≥ 2", ver("multer"));
    const pkg = require("../package.json");
    ok(/\^?10\./.test(pkg.dependencies.nodemailer) && /\^?2\./.test(pkg.dependencies.multer), "F-31: package.json sürümleri güncel", pkg.dependencies);
  }

  // ============ F-33 / F-34: şifre ============
  {
    for (const [pw, label] of [[1234567, "sayı"], [["a", "b", "c", "d", "e", "f"], "dizi"], [{ a: 1 }, "nesne"], ["123456", "yaygın şifre"], ["a".repeat(80), "72 bayt üstü"], ["short", "kısa"]]) {
      const r = await call("POST", "/users", A, { name: "Pw Test", email: "pwt" + Math.floor(Math.random() * 1e9) + "@x.com", password: pw, role: "saha" });
      ok(r.s === 400, "F-34: geçersiz şifre (" + label + ") 400 (500 değil)", r.s);
    }
    ok((await call("POST", "/users", A, { name: ["x"], email: "ad@x.com", password: "abcdef", role: "saha" })).s === 400, "F-34: dizi tipli ad 400");
    const nu = await call("POST", "/users", A, { name: "Sifre Test", email: "sifre@x.com", password: "abcdef", role: "personel" });
    ok(nu.s === 201, "kullanıcı oluştu");
    const t1 = await login("sifre@x.com", "abcdef");
    const wrong = await call("PATCH", "/users/me/password", t1, { current_password: "yanlis", new_password: "yeniSifre123" });
    ok(wrong.s === 400 || wrong.s === 403, "F-33: yanlış mevcut şifre reddedilir", wrong.s);
    ok((await call("PATCH", "/users/me/password", t1, { current_password: "abcdef", new_password: 123456789 })).s === 400, "F-33: yeni şifre tipi doğrulanır");
    const ch = await call("PATCH", "/users/me/password", t1, { current_password: "abcdef", new_password: "yeniSifre123" });
    ok(ch.s === 200 && ch.j.token && ch.j.user.email === "sifre@x.com", "F-33: şifre değişti, yeni jeton döndü", ch.j);
    ok((await call("GET", "/auth/me", t1)).s === 401, "F-33: eski jeton iptal");
    ok((await call("GET", "/auth/me", ch.j.token)).s === 200, "F-33: yeni jeton çalışır");
    ok((await call("POST", "/auth/login", null, { email: "sifre@x.com", password: "abcdef" })).s === 401 && (await login("sifre@x.com", "yeniSifre123")), "F-33: eski şifre geçmez, yenisi girer");
    // admin sıfırlama
    const rs = await call("PATCH", "/users/" + nu.j.id + "/password", A, { new_password: "adminSifirla1" });
    ok(rs.s === 200, "F-33: admin şifre sıfırlar", rs.j);
    ok((await call("GET", "/auth/me", ch.j.token)).s === 401, "F-33: sıfırlama sonrası oturumlar düşer");
    ok(!!(await login("sifre@x.com", "adminSifirla1")), "F-33: sıfırlanan şifre ile giriş");
    ok((await call("PATCH", "/users/" + nu.j.id + "/password", PA, { new_password: "hackle12345" })).s === 403, "F-33: personel başkasının şifresini sıfırlayamaz");
    ok((await call("PATCH", "/users/" + nu.j.id + "/password", OB, { new_password: "hackle12345" })).s === 403, "F-33: ortak, kendi ekibi olmayanı sıfırlayamaz");
    const mine = await call("POST", "/users", OA, { name: "OA Ekip", email: "oaekip@x.com", password: "abcdef", role: "saha" });
    ok((await call("PATCH", "/users/" + mine.j.id + "/password", OA, { new_password: "ekipSifre123" })).s === 200, "F-33: ortak kendi ekibinin şifresini sıfırlar");
  }

  // ============ hata mesajı sızıntısı, başlıklar ============
  {
    const bad = await fetch(B + "/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: '{"email": "a", ' });
    const bj = await bad.json();
    ok(bad.status === 400 && !/Unexpected|position|JSON\.parse|token/i.test(bj.error), "hata: bozuk JSON gövdesi iç ayrıntı sızdırmaz", bj);
    const hd = await fetch(ORIGIN + "/api/health");
    ok(!hd.headers.get("x-powered-by"), "başlık: x-powered-by yok");
    ok(/nosniff/i.test(hd.headers.get("x-content-type-options") || ""), "başlık: nosniff");
    ok(/default-src/.test(hd.headers.get("content-security-policy") || ""), "başlık: CSP");
    ok(/max-age=\d{7,}/.test(hd.headers.get("strict-transport-security") || ""), "başlık: HSTS", hd.headers.get("strict-transport-security"));
    ok(/no-referrer/.test(hd.headers.get("referrer-policy") || ""), "başlık: Referrer-Policy no-referrer", hd.headers.get("referrer-policy"));
    const ghost = await call("GET", "/customers/05000000000", OB);
    ok(ghost.s === 200, "müşteri geçmişi boş döner");
  }

  // ============ ek sunucu: CORS, trust proxy, DB ssl, log düzenleme (birim) ============
  const spawnServer = (port, env) => new Promise((resolve) => {
    const child = spawn(process.execPath, ["src/server.js"], { cwd: ROOT, env: { ...process.env, PORT: String(port), ...env }, stdio: ["ignore", "pipe", "pipe"] });
    let out = ""; child.stdout.on("data", (d) => (out += d)); child.stderr.on("data", (d) => (out += d));
    const t0 = Date.now();
    (async () => { while (Date.now() - t0 < 8000) { try { if ((await fetch(`http://localhost:${port}/api/health`)).ok) return resolve({ child, log: () => out }); } catch {} await sleep(200); } resolve({ child, log: () => out }); })();
  });
  {
    const s = await spawnServer(4110, { CORS_ORIGINS: "https://panel.example.com, https://app.example.com" });
    const okO = await fetch("http://localhost:4110/api/health", { headers: { Origin: "https://panel.example.com" } });
    const badO = await fetch("http://localhost:4110/api/health", { headers: { Origin: "https://evil.example.net" } });
    const none = await fetch("http://localhost:4110/api/health");
    ok(okO.headers.get("access-control-allow-origin") === "https://panel.example.com", "CORS: izinli origin yansıtılır", okO.headers.get("access-control-allow-origin"));
    ok(!badO.headers.get("access-control-allow-origin"), "CORS: izinsiz origin başlık almaz", badO.headers.get("access-control-allow-origin"));
    ok(none.status === 200, "CORS: Origin'siz istek (mobil) çalışır");
    const pre = await fetch("http://localhost:4110/api/offers", { method: "OPTIONS", headers: { Origin: "https://evil.example.net", "Access-Control-Request-Method": "POST" } });
    ok(!pre.headers.get("access-control-allow-origin"), "CORS: izinsiz preflight reddedilir");
    s.child.kill();
    // varsayılan (CORS_ORIGINS yok) davranış geriye uyumlu: yansıtır
    const d = await fetch(ORIGIN + "/api/health", { headers: { Origin: "https://panel.example.com" } });
    ok(d.headers.get("access-control-allow-origin") === "https://panel.example.com", "CORS: CORS_ORIGINS yoksa eski davranış (geriye uyum)");
  }
  {
    // TRUST_PROXY=false: sahte X-Forwarded-For ile giriş hız sınırı aşılamaz
    const s = await spawnServer(4111, { TRUST_PROXY: "false" });
    let blocked = 0;
    for (let i = 0; i < 14; i++) {
      const r = await fetch("http://localhost:4111/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json", "X-Forwarded-For": `198.51.100.${i + 1}` }, body: JSON.stringify({ email: "nope@x.com", password: "x" }) });
      if (r.status === 429) blocked++;
    }
    ok(blocked >= 3, "trust proxy: TRUST_PROXY=false iken XFF sahteciliği hız sınırını aşamaz", blocked);
    s.child.kill();
    // varsayılan (1 proxy): XFF istemci IP'si olarak kullanılır → farklı IP farklı kova
    let b2 = 0;
    for (let i = 0; i < 12; i++) {
      const r = await fetch(B + "/auth/login", { method: "POST", headers: { "Content-Type": "application/json", "X-Forwarded-For": `192.0.2.${100 + i}` }, body: JSON.stringify({ email: "nope@x.com", password: "x" }) });
      if (r.status === 429) b2++;
    }
    ok(b2 === 0, "trust proxy: varsayılan 1 proxy, XFF ile ayrışan istemciler ayrı sayılır (geriye uyum)", b2);
  }
  {
    const s = await spawnServer(4112, { JWT_SECRET: "kisa" });
    let up = false; try { up = (await fetch("http://localhost:4112/api/health")).ok; } catch {}
    ok(!up, "F-32: çok kısa JWT_SECRET ile sunucu başlamaz");
    s.child.kill();
    const w = await spawnServer(4113, { JWT_SECRET: "x".repeat(20) });
    ok(/32/.test(w.log()), "F-32: 16-31 karakterlik JWT_SECRET için uyarı yazdırılır", w.log().slice(0, 300));
    w.child.kill();
  }
  {
    const { buildSslConfig } = require("../src/dbssl");
    ok(buildSslConfig({ DATABASE_SSL: "false" }) === false, "DB ssl: DATABASE_SSL=false → ssl yok");
    ok(buildSslConfig({ NODE_ENV: "production" }).rejectUnauthorized === false, "DB ssl: üretimde varsayılan eski davranış (rejectUnauthorized:false, geriye uyum)");
    ok(buildSslConfig({ DATABASE_SSL: "true", DB_SSL_REJECT_UNAUTHORIZED: "true" }).rejectUnauthorized === true, "DB ssl: DB_SSL_REJECT_UNAUTHORIZED=true → sertifika doğrulanır");
    ok(buildSslConfig({ DATABASE_SSL: "true", DB_SSL_REJECT_UNAUTHORIZED: "false" }).rejectUnauthorized === false, "DB ssl: açıkça false");
    const tmp = path.join(require("os").tmpdir(), "ca-test.pem"); fs.writeFileSync(tmp, "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n");
    const withCa = buildSslConfig({ DATABASE_SSL: "true", DB_SSL_REJECT_UNAUTHORIZED: "true", DB_SSL_CA: tmp });
    ok(withCa.ca && /BEGIN CERTIFICATE/.test(String(withCa.ca)), "DB ssl: DB_SSL_CA okunur");
    ok(buildSslConfig({ DATABASE_SSL: "true", DB_SSL_CA: tmp }).rejectUnauthorized === true, "DB ssl: CA verilince doğrulama varsayılan açılır");
    fs.unlinkSync(tmp);
  }
  {
    const { redactUrl, describeErrorForLog } = require("../src/services/logging");
    ok(redactUrl("/uploads/documents/a.pdf?exp=1&sig=SECRET") === "/uploads/documents/a.pdf", "log: URL sorgu dizesi (imza) loglanmaz", redactUrl("/uploads/documents/a.pdf?exp=1&sig=SECRET"));
    ok(redactUrl("/api/track/XCY-ABC12?x=1") === "/api/track/[kod]", "log: takip kodu maskelenir", redactUrl("/api/track/XCY-ABC12"));
    const e = new Error("duplicate key value violates unique constraint — Key (email)=(secret@x.com)"); e.code = "23505"; e.detail = "Key (email)=(secret@x.com) already exists."; e.parameters = ["hash"];
    const line = describeErrorForLog(e);
    ok(!/secret@x\.com|parameters|hash/.test(line) && /23505/.test(line), "log: DB hata ayrıntısı/parametreleri loglanmaz", line);
  }

  // ============ kapanış ============
  console.log(`\nv16: ${pass} geçti, ${fail} kaldı`);
  wa.close(); smtp.close();
  await db.pool.end().catch(() => {});
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST CRASH", e); process.exit(2); });
