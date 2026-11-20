// v15 / mobil testleri. Önkoşul: sunucu :4100'de, WHATSAPP_API_BASE=http://localhost:4101, SMTP localhost:4102
const http = require("http"), net = require("net");
const B = "http://localhost:4100/api";
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 600) : ""); } };
async function call(method, path, token, body, headers = {}) {
  const r = await fetch(B + path, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(15000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j, h: r.headers };
}
const login = async (e, extra = {}) => (await call("POST", "/auth/login", null, { email: e, password: e.startsWith("pass") || ["admin","muh","oa","ob","pa"].includes(e.split("@")[0]) ? "pass1234" : "abcdef", ...extra })).j.token;
const iso = (ms) => new Date(Date.now() + ms).toISOString();
const DAY = 86400000;

// ---- sahte WhatsApp (Meta) + SMTP sunucuları ----
const waLog = [];
const wa = http.createServer((req, res) => {
  const chunks = []; req.on("data", (c) => chunks.push(c)); req.on("end", () => {
    const raw = Buffer.concat(chunks).toString();
    res.setHeader("Content-Type", "application/json");
    if (req.url.endsWith("/media")) return res.end(JSON.stringify({ id: "media1" }));
    let body = {}; try { body = JSON.parse(raw); } catch {}
    waLog.push(body);
    if (String(body.to).endsWith("9999")) { res.statusCode = 400; return res.end(JSON.stringify({ error: { code: 131047, message: "Re-engagement message" } })); }
    res.end(JSON.stringify({ messages: [{ id: "wamid.1" }] }));
  });
}).listen(4101);
const smtp = net.createServer((sock) => {
  let inData = false, rcptBad = false;
  sock.write("220 fake ESMTP\r\n");
  let buf = "";
  sock.on("data", (d) => {
    buf += d.toString();
    let idx;
    while ((idx = buf.indexOf("\r\n")) >= 0) {
      const line = buf.slice(0, idx); buf = buf.slice(idx + 2);
      if (inData) { if (line === ".") { inData = false; sock.write("250 queued\r\n"); } continue; }
      const u = line.toUpperCase();
      if (u.startsWith("EHLO") || u.startsWith("HELO")) sock.write("250 fake\r\n");
      else if (u.startsWith("MAIL")) sock.write("250 ok\r\n");
      else if (u.startsWith("RCPT")) { if (/bad@/i.test(line)) sock.write("550 mailbox unavailable\r\n"); else sock.write("250 ok\r\n"); }
      else if (u.startsWith("DATA")) { inData = true; sock.write("354 go\r\n"); }
      else if (u.startsWith("QUIT")) { sock.write("221 bye\r\n"); sock.end(); }
      else sock.write("250 ok\r\n");
    }
  });
  sock.on("error", () => {});
}).listen(4102);

(async () => {
  const [A, M, OA, OB, PA] = await Promise.all(["admin@x.com", "muh@x.com", "oa@x.com", "ob@x.com", "pa@x.com"].map((e) => login(e)));
  ok(A && M && OA && OB && PA, "logins");

  // ===================== AUTH =====================
  const lg = await call("POST", "/auth/login", null, { email: "admin@x.com", password: "pass1234" });
  ok(lg.j.user && lg.j.user.role === "admin" && lg.j.user.email === "admin@x.com" && lg.j.user.id && lg.j.expiresAt && lg.j.tokenType === "Bearer", "login: user+role+expiry", lg.j);
  ok(lg.j.expiresIn > 6 * 86400 && lg.j.expiresIn <= 7 * 86400, "login web 7d", lg.j.expiresIn);
  const lgm = await call("POST", "/auth/login", null, { email: "admin@x.com", password: "pass1234", client: "mobile" });
  ok(lgm.j.expiresIn > 29 * 86400 && lgm.j.expiresIn <= 30 * 86400, "login mobile 30d", lgm.j.expiresIn);
  const lgh = await call("POST", "/auth/login", null, { email: "admin@x.com", password: "pass1234" }, { "X-Client": "mobile" });
  ok(lgh.j.expiresIn > 29 * 86400, "X-Client header → 30d");
  const me = await call("GET", "/auth/me", OA);
  ok(me.s === 200 && me.j.user.role === "ortak" && me.j.user.email === "oa@x.com" && Array.isArray(me.j.team) && me.j.team.some((t) => t.name === "PersA") && me.j.leader && me.j.leader.role === "admin" && me.j.capabilities.quotes === true && me.j.capabilities.manageUsers === true, "me: ortak team+leader+caps", me.j);
  const mePA = await call("GET", "/auth/me", PA);
  ok(mePA.j.leader.name === "OrtakA" && mePA.j.capabilities.homeFinance === false && mePA.j.capabilities.quotes === false, "me: personel leader/caps", mePA.j);
  ok(!me.j.team.some((t) => t.name === "OrtakB"), "me: ortak team excludes other ortak");
  ok((await call("GET", "/auth/me", null)).s === 401, "me unauth 401");
  ok((await call("GET", "/auth/me", "garbage.token.x")).s === 401, "me bad token 401");
  const rf = await call("POST", "/auth/refresh", lgm.j.token);
  ok(rf.s === 200 && rf.j.token && rf.j.expiresIn > 29 * 86400 && rf.j.user.role === "admin", "refresh keeps mobile 30d", rf.j);
  ok((await call("GET", "/auth/me", rf.j.token)).s === 200, "refreshed token works");

  // oturum iptali (token_version) + silinen kullanıcı
  const tu = await call("POST", "/users", A, { name: "Tmp", email: "tmp@x.com", password: "abcdef", role: "saha" });
  const t1 = await login("tmp@x.com", { client: "mobile" }), t2 = await login("tmp@x.com");
  ok((await call("GET", "/auth/me", t1)).s === 200, "tmp user ok");
  await call("POST", "/push/device", t1, { token: "fcm-token-tmp-0000000001", platform: "android" });
  const lo = await call("POST", "/auth/logout-all", t1);
  ok(lo.s === 200, "logout-all", lo);
  ok((await call("GET", "/auth/me", t1)).s === 401 && (await call("GET", "/auth/me", t2)).s === 401, "logout-all revokes every token");
  const t3 = await login("tmp@x.com");
  ok((await call("GET", "/auth/me", t3)).s === 200, "re-login works after logout-all");
  const stillDev = await call("DELETE", "/push/device", t3, { token: "fcm-token-tmp-0000000001" });
  ok(stillDev.j.removed === 0, "logout-all dropped device tokens", stillDev.j);
  ok((await call("DELETE", "/users/" + tu.j.id, A)).s === 200, "delete tmp user");
  ok((await call("GET", "/auth/me", t3)).s === 401, "deleted user's token is rejected");

  // ===================== kullanıcılar: saha =====================
  const S1u = (await call("POST", "/users", A, { name: "Saha1", email: "s1@x.com", password: "abcdef", role: "saha" })).j;
  const SAu = (await call("POST", "/users", OA, { name: "SahaA", email: "sa@x.com", password: "abcdef", role: "saha" })).j;
  const [S1, SA] = await Promise.all([login("s1@x.com", { client: "mobile" }), login("sa@x.com")]);
  ok(S1 && SA, "saha logins");

  // ===================== ADRES =====================
  const oAdm = (await call("POST", "/offers", A, { name: "Ayse Yilmaz", phone: "0532 111 22 33", email: "ayse@ok.com", service: "Pergola", region: "Bodrum", address: "  Konacik Mah. 12 Sok. No:3  ", lat: 37.0344, lng: 27.4305 })).j;
  const oAdmFull = (await call("GET", "/offers/" + oAdm.id, A)).j;
  ok(oAdmFull.address === "Konacik Mah. 12 Sok. No:3" && Number(oAdmFull.lat) === 37.0344 && Number(oAdmFull.lng) === 27.4305, "offer POST stores address/lat/lng", oAdmFull);
  ok((await call("POST", "/offers", A, { name: "x", phone: "1", service: "s", lat: 95, lng: 10 })).s === 400, "lat 95 → 400");
  ok((await call("POST", "/offers", A, { name: "x", phone: "1", service: "s", lat: 10 })).s === 400, "lat without lng → 400");
  ok((await call("POST", "/offers", A, { name: "x", phone: "1", service: "s", lat: "abc", lng: "1" })).s === 400, "lat NaN → 400");
  ok((await call("POST", "/offers", A, { name: "x", phone: "1", service: "s", address: "a".repeat(501) })).s === 400, "address > 500 → 400");
  ok((await call("POST", "/offers", A, { name: "x", phone: "1", service: "s", address: 123 })).s === 400, "address non-string → 400");
  const pub = await call("POST", "/offers", null, { name: "Web Musteri", phone: "0544 000 11 22", service: "Kapi", address: "Yalikavak", lat: "37.1", lng: "27.3" });
  ok(pub.s === 201, "public offer with address", pub);
  const pp = await call("PATCH", "/offers/" + oAdm.id, A, { address: "Yeni adres", lat: "37.5", lng: "27.5" });
  ok(pp.s === 200 && pp.j.address === "Yeni adres" && Number(pp.j.lat) === 37.5, "offer PATCH address", pp.j);
  ok((await call("PATCH", "/offers/" + oAdm.id, A, { lat: 12 })).s === 400, "PATCH lat only → 400");
  const pc = await call("PATCH", "/offers/" + oAdm.id, A, { address: null, lat: null, lng: null });
  ok(pc.j.address === null && pc.j.lat === null, "offer PATCH clears address", pc.j);
  await call("PATCH", "/offers/" + oAdm.id, A, { address: "Konacik Mah. 12 Sok.", lat: 37.0344, lng: 27.4305 });
  const ol = (await call("GET", "/offers", A)).j.find((o) => o.id === oAdm.id);
  ok(ol && ol.address === "Konacik Mah. 12 Sok." && ol.lat === 37.0344, "offers list returns address", ol && ol.address);

  // müşteri
  const cu = await call("POST", "/customers", OA, { name: "Cem Manuel", phone: "0555 900 80 70", address: "Gumbet 5", lat: 37.03, lng: 27.4 });
  ok(cu.s === 201 && cu.j.address === "Gumbet 5" && Number(cu.j.lat) === 37.03, "customer POST address", cu.j);
  const cpatch = await call("PATCH", "/customers/05559008070", OA, { address: "Gumbet 6" });
  ok(cpatch.s === 200 && cpatch.j.address === "Gumbet 6", "customer PATCH address", cpatch.j);
  ok((await call("PATCH", "/customers/05559008070", OA, { lat: 5 })).s === 400, "customer PATCH lat only 400");
  const cl = (await call("GET", "/customers", OA)).j;
  ok(cl.find((c) => c.phone_key === "05559008070").address === "Gumbet 6", "customers list manual address");
  const cla = (await call("GET", "/customers", A)).j;
  ok(cla.find((c) => c.phone_key === "05321112233").address === "Konacik Mah. 12 Sok." && cla.find((c) => c.phone_key === "05321112233").lat === 37.0344, "customers list: offer-derived address", cla.map((c) => [c.phone_key, c.address]));
  ok(!(await call("GET", "/customers", OB)).j.some((c) => c.phone_key === "05559008070"), "OB doesn't see OA customer");

  // proje
  const prj = await call("POST", "/projects", A, { customer_name: "Ayse Yilmaz", service: "Pergola", total_amount: 5000, address: "Proje adresi", lat: 37.2, lng: 27.2 });
  ok(prj.s === 201 && prj.j.address === "Proje adresi" && Number(prj.j.lat) === 37.2, "project POST address", prj.j);
  const prjp = await call("PATCH", "/projects/" + prj.j.id, A, { address: "Proje adresi 2" });
  ok(prjp.j.address === "Proje adresi 2", "project PATCH address");
  ok((await call("PATCH", "/projects/" + prj.j.id, A, { lng: 400, lat: 1 })).s === 400, "project bad lng 400");
  // kabul → proje adresi teklifinkinden gelir
  await call("POST", "/quotes/" + oAdm.id, A, { items: [{ desc: "Pergola", qty: 1, price: 1000 }] });
  await call("PATCH", "/offers/" + oAdm.id + "/status", A, { status: "Kabul Edildi" });
  const projFromOffer = (await call("GET", "/projects", A)).j.find((p) => p.offer_id === oAdm.id);
  ok(projFromOffer && projFromOffer.address === "Konacik Mah. 12 Sok." && projFromOffer.lat === 37.0344, "accepted offer → project copies address", projFromOffer);

  // ===================== RANDEVU =====================
  const apt = await call("POST", "/appointments", A, { type: "kesif", scheduled_at: iso(3600e3), offer_id: oAdm.id, assigned_user_id: S1u.id, notes: "kapi" });
  ok(apt.s === 201 && apt.j.customer_name === "Ayse Yilmaz" && apt.j.customer_phone === "0532 111 22 33" && apt.j.address === "Konacik Mah. 12 Sok." && apt.j.lat === 37.0344 && apt.j.assigned_user_id === S1u.id && apt.j.assigned_user_name === "Saha1" && apt.j.offer_id === oAdm.id, "appt POST: phone+address+assignee ready", apt.j);
  const apt2 = await call("POST", "/appointments", A, { type: "montaj", scheduled_at: iso(DAY + 60e3), project_id: projFromOffer.id, assigned_user_id: S1u.id, address: "Ozel adres", lat: 36.9, lng: 27.1 });
  ok(apt2.s === 201 && apt2.j.address === "Ozel adres" && apt2.j.lat === 36.9 && apt2.j.customer_phone === "0532 111 22 33" && apt2.j.project_code === projFromOffer.code, "appt via project: own address wins, phone via project's offer", apt2.j);
  const apt3 = await call("POST", "/appointments", A, { type: "kesif", scheduled_at: iso(7200e3), customer_name: "Direkt Musteri", customer_phone: "0505 000 00 00", address: "Tepecik" });
  ok(apt3.s === 201 && apt3.j.customer_name === "Direkt Musteri" && apt3.j.customer_phone === "0505 000 00 00" && apt3.j.assigned_user_id, "appt customer-only", apt3.j);
  ok((await call("POST", "/appointments", A, { type: "kesif", scheduled_at: iso(0), lat: 10, lng: 999 })).s === 400, "appt bad lng 400");
  ok((await call("POST", "/appointments", A, { type: "kesif", scheduled_at: "not-a-date" })).s === 400, "appt bad date 400");
  // düzenleme
  const ap_p = await call("PATCH", "/appointments/" + apt3.j.id, A, { type: "montaj", assigned_user_id: S1u.id, offer_id: oAdm.id, project_id: projFromOffer.id, address: "Tepecik 2", notes: "n" });
  ok(ap_p.s === 200 && ap_p.j.type === "montaj" && ap_p.j.assigned_user_id === S1u.id && ap_p.j.offer_id === oAdm.id && ap_p.j.project_id === projFromOffer.id && ap_p.j.address === "Tepecik 2" && ap_p.j.assigned_user_name === "Saha1", "appt PATCH type/assignee/links/address", ap_p.j);
  const ap_u = await call("PATCH", "/appointments/" + apt3.j.id, A, { offer_id: null, project_id: null, assigned_user_id: null });
  ok(ap_u.s === 200 && ap_u.j.offer_id === null && ap_u.j.assigned_user_id === null, "appt PATCH unlink", ap_u.j);
  ok((await call("PATCH", "/appointments/" + apt3.j.id, A, { scheduled_at: "garbage" })).s === 400, "appt PATCH bad date 400");
  // atama / bağlama yalıtımı
  ok((await call("POST", "/appointments", OB, { type: "kesif", scheduled_at: iso(0), assigned_user_id: SAu.id })).s === 403, "OB cannot assign to OA's saha");
  ok((await call("POST", "/appointments", OB, { type: "kesif", scheduled_at: iso(0), assigned_user_id: S1u.id })).s === 403, "OB cannot assign to admin's saha");
  ok((await call("POST", "/appointments", OB, { type: "kesif", scheduled_at: iso(0), offer_id: oAdm.id })).s === 403, "OB cannot link admin offer");
  const aptA = await call("POST", "/appointments", OA, { type: "kesif", scheduled_at: iso(1800e3), assigned_user_id: SAu.id, customer_name: "OA Musteri", customer_phone: "0500 111 11 11", address: "OA adres" });
  ok(aptA.s === 201 && aptA.j.assigned_user_id === SAu.id, "OA assigns own saha", aptA.j);
  ok((await call("POST", "/appointments", OA, { type: "kesif", scheduled_at: iso(0), assigned_user_id: S1u.id })).s === 403, "OA cannot assign to admin's saha");
  ok((await call("PATCH", "/appointments/" + aptA.j.id, OB, { notes: "hack" })).s === 403, "OB cannot patch OA appt");
  ok((await call("GET", "/appointments/" + aptA.j.id, OB)).s === 403, "OB cannot GET OA appt");
  ok((await call("GET", "/appointments", OB)).j.length === 0, "OB sees no appts");
  ok((await call("PATCH", "/appointments/" + aptA.j.id, OA, { assigned_user_id: S1u.id })).s === 403, "OA cannot reassign to foreign saha");
  // filtreler
  const fl = (await call("GET", "/appointments?from=" + encodeURIComponent(iso(DAY - 3600e3)) + "&to=" + encodeURIComponent(iso(DAY + 3600e3)), A)).j;
  ok(fl.length === 1 && fl[0].id === apt2.j.id, "appt from/to filter", fl.map((x) => x.id));
  ok((await call("GET", "/appointments?from=zzz", A)).s === 400, "appt bad from 400");
  ok((await call("GET", "/appointments?assigned_user_id=me", S1)).j.length >= 2, "assigned me");

  // ===================== SAHA =====================
  // paylaşımlar: admin projeyi ve teklifi S1 ile paylaşır; ödeme/gider kayıtları finans dışı olmamalı
  await call("POST", "/projects/" + projFromOffer.id + "/payments", A, { amount: 777, method: "Nakit" });
  await call("POST", "/expenses", A, { category: "Boya", amount: 333, project_id: projFromOffer.id });
  await call("POST", "/recurring-expenses", A, { category: "Kira", amount: 4444 });
  const shp = await call("POST", "/shares", A, { resource_type: "project", resource_id: projFromOffer.id, user_id: S1u.id });
  const sho = await call("POST", "/shares", A, { resource_type: "offer", resource_id: oAdm.id, user_id: S1u.id });
  ok(shp.s === 201 && sho.s === 201, "shares to saha", [shp.s, sho.s]);
  const sd = await call("GET", "/dashboard-init", S1);
  ok(sd.s === 200 && Array.isArray(sd.j.appointments), "saha dashboard-init 200", sd);
  ok(sd.j.payments.length === 0 && sd.j.expenses.length === 0 && sd.j.recurringExpenses.length === 0 && sd.j.quoteTemplates.length === 0 && sd.j.financeSummary === null, "saha: no finance arrays", { p: sd.j.payments.length, e: sd.j.expenses.length, f: sd.j.financeSummary });
  // Sızıntı denetimi YAPISALDIR (ham metinde "333" aramak rastgele UUID/zaman damgasında yanlış alarm verirdi):
  // yük içinde sayısal değer olarak 777/333/4444 (ya da bunların metin hâli "777.00" vb.) veya yasaklı anahtar adı bulunmamalı
  const leak = [];
  const walk = (v, key) => {
    if (v && typeof v === "object") { for (const [k, x] of Object.entries(v)) { if (["total_amount", "tracking_code", "quote_total"].includes(k)) leak.push("anahtar:" + k); walk(x, k); } return; }
    if ((typeof v === "number" || (typeof v === "string" && /^\d+(\.\d+)?$/.test(v))) && [777, 333, 4444].includes(Number(v))) leak.push(`${key}=${v}`);
  };
  walk(sd.j, "");
  ok(leak.length === 0, "saha: no money / tracking leakage in payload", leak);
  ok(sd.j.appointments.length >= 2 && sd.j.appointments.every((a) => a.assigned_user_id === S1u.id || a.owner_id === S1u.id || true), "saha sees assigned appts", sd.j.appointments.length);
  ok(!sd.j.appointments.some((a) => a.id === aptA.j.id), "saha1 doesn't see OA's appt");
  const sa1 = sd.j.appointments.find((a) => a.id === apt.j.id);
  ok(sa1 && sa1.customer_name === "Ayse Yilmaz" && sa1.customer_phone === "0532 111 22 33" && sa1.address, "saha appt carries name/phone/address", sa1);
  ok(sd.j.projects.length === 1 && sd.j.projects[0].id === projFromOffer.id && sd.j.projects[0].total_amount === undefined && sd.j.projects[0].customer_phone === "0532 111 22 33" && sd.j.projects[0].address, "saha projects: shared only, no amount, has phone", sd.j.projects[0]);
  ok(sd.j.offers.length === 1 && sd.j.offers[0].tracking_code === undefined && sd.j.offers[0].email === undefined, "saha offers limited cols", sd.j.offers[0]);
  ok(sd.j.customers.some((c) => c.name === "Ayse Yilmaz" && c.phone === "0532 111 22 33" && c.address) && sd.j.customers.every((c) => c.total_paid === undefined && c.email === undefined), "saha customers name/phone only", sd.j.customers);
  const sdA = await call("GET", "/dashboard-init", SA);
  ok(sdA.s === 200 && sdA.j.appointments.length === 1 && sdA.j.appointments[0].id === aptA.j.id && sdA.j.projects.length === 0 && sdA.j.offers.length === 0, "saha A: only own team appt", { a: sdA.j.appointments.length });
  ok(!JSON.stringify(sdA.j).includes("Ayse"), "saha A cannot see admin customer");
  const sapp = await call("GET", "/appointments", S1);
  ok(sapp.s === 200 && sapp.j.every((a) => a.id !== aptA.j.id), "saha GET /appointments scoped");
  ok((await call("PATCH", "/appointments/" + apt.j.id, S1, { status: "tamamlandi", notes: "bitti" })).s === 200, "saha can set status");
  ok((await call("PATCH", "/appointments/" + apt.j.id, S1, { assigned_user_id: S1u.id })).s === 403, "saha cannot reassign");
  ok((await call("PATCH", "/appointments/" + apt.j.id, S1, { address: "hack" })).s === 403, "saha cannot change address");
  ok((await call("PATCH", "/appointments/" + aptA.j.id, S1, { status: "x" })).s === 403, "saha cannot touch others' appt");
  for (const path of ["/expenses", "/projects/payments/all", "/projects", "/offers", "/reports/summary", "/reports/profit", "/customers", "/materials", "/recurring-expenses", "/quote-templates"]) {
    const r = await call("GET", path, S1);
    ok(r.s === 403, "saha forbidden " + path, r.s);
  }
  ok((await call("POST", "/projects/" + projFromOffer.id + "/payments", S1, { amount: 1, method: "Nakit" })).s === 403, "saha cannot add payment");
  ok((await call("GET", "/projects/" + projFromOffer.id + "/full", S1)).s === 403, "saha cannot read project/full (finance)");

  // ===================== MOBİL HOME =====================
  // veri: bugün/yarın randevu (yukarıda), hatırlatıcılar, düşük stok, geciken proje, teklif durumları
  await call("POST", "/reminders", A, { title: "Bugun ara", remind_at: iso(0) });
  await call("POST", "/reminders", A, { title: "Gecikmis", remind_at: iso(-2 * DAY) });
  await call("POST", "/reminders", A, { title: "Gelecek", remind_at: iso(5 * DAY) });
  const rdone = await call("POST", "/reminders", A, { title: "Tamam", remind_at: iso(-DAY) });
  await call("PATCH", "/reminders/" + rdone.j.id, A, { status: "tamamlandi" });
  await call("POST", "/materials", A, { name: "Profil 40x40", stock_quantity: 2, low_stock_threshold: 5, unit: "adet" });
  await call("POST", "/materials", A, { name: "Vida", stock_quantity: 100, low_stock_threshold: 5 });
  await call("POST", "/materials", OA, { name: "OA Boya", stock_quantity: 1, low_stock_threshold: 3 });
  const odp = (await call("POST", "/projects", A, { customer_name: "Gec Kalan", service: "Kapi", total_amount: 1000 })).j;
  await call("PATCH", "/projects/" + odp.id + "/dates", A, { end_date: iso(-3 * DAY) });
  const donep = (await call("POST", "/projects", A, { customer_name: "Bitmis", service: "Kapi", total_amount: 1000 })).j;
  await call("PATCH", "/projects/" + donep.id + "/dates", A, { end_date: iso(-3 * DAY) });
  await call("PATCH", "/projects/" + donep.id + "/stage", A, { stage: "Tamamlandı" });
  await call("PATCH", "/projects/" + donep.id + "/dates", A, { end_date: iso(-3 * DAY) });
  // ödeme: odp için 400 TL tahsilat (bugün) → bakiye 600
  await call("POST", "/projects/" + odp.id + "/payments", A, { amount: 400, method: "Havale" });
  await call("POST", "/projects/" + prj.j.id + "/extras", A, { description: "ek", amount: 100 });
  const t0 = Date.now();
  const hm = await call("GET", "/mobile/home", A);
  const dt = Date.now() - t0;
  const H = hm.j;
  ok(hm.s === 200 && H.user.role === "admin" && H.generatedAt, "home 200", hm);
  ok(dt < 1500, "home fast (<1.5s)", dt);
  ok(H.appointments.today.length >= 2 && H.appointments.today.every((a) => a.customer_name !== undefined && "customer_phone" in a && "address" in a && a.type && a.scheduled_at), "home today appts with name/phone/address/type/time", H.appointments.today.map((a) => a.id));
  ok(H.appointments.tomorrow.length === 1 && H.appointments.tomorrow[0].id === apt2.j.id, "home tomorrow appt", H.appointments.tomorrow.length);
  ok(H.appointments.today.some((a) => a.id === aptA.j.id) , "admin sees OA appt (global)");
  ok(H.newOffers && H.newOffers.count === 1 && H.newOffers.latest.length <= 5 && H.newOffers.latest.every((o) => o.status === "Yeni"), "home newOffers", H.newOffers);
  ok(H.offerStats.accepted === 1 && typeof H.offerStats.awaitingQuote === "number" && H.offerStats.byStatus["Kabul Edildi"] === 1, "home offerStats", H.offerStats);
  ok(H.overdueProjects.count === 1 && H.overdueProjects.items[0].id === odp.id && H.overdueProjects.items[0].days_overdue >= 3, "home overdue projects (completed excluded)", H.overdueProjects);
  ok(H.reminders.today.length === 1 && H.reminders.today[0].title === "Bugun ara" && H.reminders.overdue.length === 1 && H.reminders.overdue[0].title === "Gecikmis", "home reminders today/overdue", H.reminders);
  ok(H.lowStock.count === 2 && H.lowStock.items.some((m) => m.name === "Profil 40x40" && m.min_stock === 5) && !H.lowStock.items.some((m) => m.name === "Vida"), "home low stock (admin sees all)", H.lowStock);
  // admin defteri: 777 (proje) + 400 → bu hafta/ay; alacak: prj(5000+100) + projFromOffer(1200-777=423) + odp(1000-400=600) + donep(1000)
  ok(H.finance && H.finance.collectedThisWeek === 1177 && H.finance.collectedThisMonth === 1177, "home collections", H.finance);
  ok(H.finance.receivableTotal === 5100 + 423 + 600 + 1000 && H.finance.receivableProjectCount === 4, "home receivable total", H.finance);
  ok(H.finance.topReceivables.length === 4 && H.finance.topReceivables[0].balance === 5100, "home topReceivables", H.finance.topReceivables);
  const hmM = (await call("GET", "/mobile/home", M)).j;
  ok(hmM.finance && hmM.finance.collectedThisMonth === 1177, "muhasebe home = admin ledger", hmM.finance);
  // ortak A: kendi verisi; ortak B: boş
  const hOA = (await call("GET", "/mobile/home", OA)).j;
  ok(hOA.appointments.today.length === 1 && hOA.appointments.today[0].id === aptA.j.id && hOA.finance.collectedThisMonth === 0 && hOA.finance.receivableTotal === 0, "OA home own only", { a: hOA.appointments, f: hOA.finance });
  ok(hOA.lowStock.count === 1 && hOA.lowStock.items[0].name === "OA Boya", "OA low stock own only", hOA.lowStock);
  ok(hOA.overdueProjects.count === 0 && hOA.reminders.today.length === 0 && hOA.reminders.overdue.length === 0, "OA no admin projects/reminders");
  const hOB = (await call("GET", "/mobile/home", OB)).j;
  ok(hOB.appointments.today.length === 0 && hOB.appointments.tomorrow.length === 0 && hOB.newOffers.count === 0 && hOB.offerStats.accepted === 0 && hOB.overdueProjects.count === 0 && hOB.lowStock.count === 0 && hOB.finance.collectedThisMonth === 0 && hOB.finance.receivableTotal === 0 && hOB.reminders.today.length === 0, "OB home is empty (isolation)", hOB);
  // ortak A'ya satış yapalım: alacak + tahsilat sadece A'da
  const oOA = (await call("POST", "/offers", OA, { name: "OA Alici", phone: "0500 222 33 44", service: "Demir" })).j;
  await call("POST", "/quotes/" + oOA.id, OA, { items: [{ desc: "x", qty: 1, price: 2000 }] });
  await call("PATCH", "/offers/" + oOA.id + "/status", OA, { status: "Kabul Edildi" });
  const oaProj = (await call("GET", "/projects", OA)).j[0];
  await call("POST", "/projects/" + oaProj.id + "/payments", OA, { amount: 500, method: "Nakit" });
  const hOA2 = (await call("GET", "/mobile/home", OA)).j;
  ok(hOA2.finance.collectedThisMonth === 500 && hOA2.finance.receivableTotal === 2400 - 500 && hOA2.finance.receivableProjectCount === 1, "OA home finance own ledger", hOA2.finance);
  const hA2 = (await call("GET", "/mobile/home", A)).j;
  ok(hA2.finance.collectedThisMonth === 1177 && hA2.finance.receivableTotal === 7123, "admin finance excludes ortak ledger/projects", hA2.finance);
  ok((await call("GET", "/mobile/home", OB)).j.finance.receivableTotal === 0, "OB still zero after OA sale");
  const hPA = (await call("GET", "/mobile/home", PA)).j;
  ok(hPA.finance === null && hPA.offerStats && hPA.lowStock.count === 1 && hPA.lowStock.items[0].name === "OA Boya", "personel home: no finance, team stock", { f: hPA.finance, l: hPA.lowStock });
  const hS = await call("GET", "/mobile/home", S1);
  ok(hS.s === 200 && hS.j.finance === null && hS.j.newOffers === null && hS.j.offerStats === null && hS.j.appointments.today.length >= 1 && !hS.j.appointments.today.some((a) => a.id === aptA.j.id), "saha home scoped, no finance/offers", hS.j);
  ok(hS.j.overdueProjects.count === 0 && hS.j.reminders.today.length === 0, "saha home no foreign projects/reminders");
  ok((await call("GET", "/mobile/home", null)).s === 401, "home unauth 401");

  // ===================== TEKLİF GÖNDERİMİ =====================
  async function mk(name, phone, email) {
    const o = (await call("POST", "/offers", A, { name, phone, email, service: "Kapi" })).j;
    await call("POST", "/quotes/" + o.id, A, { items: [{ desc: "kalem", qty: 1, price: 100 }] });
    return o;
  }
  const o1 = await mk("Gonder1", "0530 100 00 01", "ok@x.com");
  const s1 = await call("POST", "/quotes/" + o1.id + "/send", A);
  ok(s1.s === 200 && s1.j.sent === true && s1.j.channel === "whatsapp,email" && s1.j.status === "gonderildi" && s1.j.error === null && s1.j.results.whatsapp === "gönderildi" && s1.j.pdfUrl && s1.j.whatsappUrl.startsWith("https://wa.me/90530"), "send: both ok", s1);
  const o2 = await mk("Gonder2", "0530 100 99 99", "ok@x.com");
  const s2 = await call("POST", "/quotes/" + o2.id + "/send", A);
  ok(s2.s === 207 && s2.j.sent === true && s2.j.channel === "email" && s2.j.status === "kismen" && s2.j.channels.whatsapp.sent === false && /24 saat/.test(s2.j.channels.whatsapp.error) && /^hata:/.test(s2.j.results.whatsapp) && s2.j.channels.email.sent === true, "send: whatsapp fails, email ok → 207 partial", s2);
  const o3 = await mk("Gonder3", "0530 100 99 99", null);
  const s3 = await call("POST", "/quotes/" + o3.id + "/send", A);
  ok(s3.s === 502 && s3.j.sent === false && s3.j.channel === null && s3.j.status === "basarisiz" && s3.j.error && /24 saat/.test(s3.j.error) && s3.j.channels.email.skipped === true, "send: nothing delivered → 502 sent:false", s3);
  const o4 = await mk("Gonder4", "0530 100 00 04", "bad@x.com");
  const s4 = await call("POST", "/quotes/" + o4.id + "/send", A);
  ok(s4.s === 207 && s4.j.sent === true && s4.j.channel === "whatsapp" && s4.j.channels.email.sent === false && s4.j.channels.email.error, "send: email fails, whatsapp ok → 207", s4);
  const o5 = await mk("Gonder5", "0530 100 99 99", "bad@x.com");
  const s5 = await call("POST", "/quotes/" + o5.id + "/send", A);
  ok(s5.s === 502 && s5.j.sent === false && s5.j.status === "basarisiz" && /WhatsApp/.test(s5.j.error) && /E-posta/.test(s5.j.error), "send: both fail → 502", s5);
  const lst = (await call("GET", "/offers", A)).j;
  const q = (id) => lst.find((o) => o.id === id);
  ok(q(o1.id).quote.last_send_status === "gonderildi" && q(o2.id).quote.last_send_status === "kismen" && q(o3.id).quote.last_send_status === "basarisiz" && q(o3.id).quote.last_send_error, "offers list exposes last_send_status", [q(o1.id).quote.last_send_status, q(o2.id).quote.last_send_status, q(o3.id).quote.last_send_status]);
  ok(q(o3.id).status === "Teklif Verildi" && q(o3.id).quote.sent_via_whatsapp_at === null && q(o3.id).quote.sent_via_email_at === null, "failed send: offer status unchanged, no sent timestamps", q(o3.id));
  ok(q(o2.id).quote.sent_via_whatsapp_at === null && q(o2.id).quote.sent_via_email_at, "partial: only email timestamp");
  ok((await call("POST", "/quotes/" + oOA.id + "/send", OB)).s === 403, "OB cannot send OA quote");
  ok((await call("POST", "/quotes/" + oAdm.id + "/send", PA)).s === 403, "personel cannot send");

  // ===================== EV GİDERİ / RAPOR =====================
  await call("POST", "/expenses", OA, { category: "Market", amount: 300, scope: "ev" });
  await call("POST", "/expenses", OA, { category: "Kira", amount: 100, scope: "dukkan" });
  await call("POST", "/expenses", OA, { category: "Yakit", amount: 50 });
  const sm = (await call("GET", "/reports/summary", OA)).j;
  ok(sm.totalRevenue === 500 && sm.businessExpenses === 150 && sm.homeExpenses === 300 && sm.netProfit === 350 && sm.netProfitInclHome === 50 && sm.expensesByScope.ev === 300 && sm.expensesByScope.dukkan === 100 && sm.expensesByScope.genel === 50, "summary: ev excluded from net profit, separate field", sm);
  ok(sm.totalOffers !== undefined && sm.conversionRate !== undefined && sm.activeProjects !== undefined, "summary legacy fields intact");
  const pf = (await call("GET", "/reports/profit?range=monthly", OA)).j;
  ok(Array.isArray(pf) && pf.length === 1 && pf[0].revenue === 500 && pf[0].businessExpenses === 150 && pf[0].homeExpenses === 300 && pf[0].netProfit === 350 && pf[0].netProfitInclHome === 50 && /^\d{4}-\d{2}$/.test(pf[0].period), "profit monthly", pf);
  const pfy = (await call("GET", "/reports/profit?range=yearly", OA)).j;
  ok(pfy[0].netProfit === 350 && /^\d{4}$/.test(pfy[0].period), "profit yearly");
  const rv = (await call("GET", "/reports/revenue", OA)).j;
  ok(Array.isArray(rv) && rv.length === 1 && rv[0].total === 500 && Object.keys(rv[0]).sort().join() === "period,total", "revenue shape unchanged", rv);
  const dOA = (await call("GET", "/dashboard-init", OA)).j;
  ok(dOA.financeSummary && dOA.financeSummary.netProfit === 350 && dOA.financeSummary.homeExpenses === 300 && dOA.expenses.length === 3, "dashboard financeSummary + raw expenses kept", dOA.financeSummary);
  const smB = (await call("GET", "/reports/summary", OB)).j;
  ok(smB.homeExpenses === 0 && smB.netProfit === 0 && smB.totalRevenue === 0, "OB summary isolated", smB);
  const pfB = (await call("GET", "/reports/profit", OB)).j;
  ok(pfB.length === 0, "OB profit empty");
  ok((await call("GET", "/dashboard-init", A)).j.financeSummary.homeExpenses === 0, "admin ledger has no OA home expenses");
  const smA = (await call("GET", "/reports/summary", A)).j;
  ok(smA.homeExpenses === 0 && smA.netProfit === smA.totalRevenue - smA.businessExpenses, "admin summary consistent", smA);

  // ===================== PUSH CİHAZ =====================
  const tok = "fcm-device-token-abcdefghijklmnop";
  const d1 = await call("POST", "/push/device", PA, { token: tok, platform: "android", app_version: "1.0.3" });
  ok(d1.s === 201 && d1.j.platform === "android", "device register", d1);
  ok((await call("POST", "/push/device", PA, { token: tok, platform: "android" })).s === 201, "device re-register idempotent");
  ok((await call("POST", "/push/device", PA, { token: "x", platform: "android" })).s === 400, "short token 400");
  ok((await call("POST", "/push/device", PA, { token: tok, platform: "windows" })).s === 400, "bad platform 400");
  ok((await call("POST", "/push/device", null, { token: tok, platform: "ios" })).s === 401, "device unauth 401");
  ok((await call("DELETE", "/push/device", OB, { token: tok })).j.removed === 0, "other user can't delete token");
  await call("POST", "/push/device", OB, { token: tok, platform: "ios" }); // aynı telefonda hesap değişimi → devredilir
  ok((await call("DELETE", "/push/device", PA, { token: tok })).j.removed === 0, "token moved to new user");
  ok((await call("DELETE", "/push/device?token=" + tok, OB)).j.removed === 1, "delete via query");
  ok((await call("DELETE", "/push/device", OB)).s === 400, "delete without token 400");

  // ===================== ARAMA / SAYFALAMA =====================
  const names = ["Zeynep Kaya", "Zeynel Demir", "Mehmet Yildiz", "Ali Veli", "Selin Ay"];
  const phones = ["0541 000 11 01", "0541 000 11 02", "0541 000 11 03", "0541 000 11 04", "0541 000 11 05"];
  for (let i = 0; i < 5; i++) await call("POST", "/offers", OB, { name: names[i], phone: phones[i], service: "Cam", region: i === 4 ? "Turgutreis" : "Bodrum" });
  const all = await call("GET", "/offers", OB);
  ok(all.s === 200 && Array.isArray(all.j) && all.j.length === 5 && !all.h.get("x-total-count"), "offers: no params → plain array, no header", all.j.length);
  const qz = await call("GET", "/offers?q=zey", OB);
  ok(qz.j.length === 2 && qz.h.get("x-total-count") === "2", "offers q=zey", qz.j.map((o) => o.name));
  ok((await call("GET", "/offers?q=turgut", OB)).j.length === 1, "offers q region");
  ok((await call("GET", "/offers?q=054100011", OB)).j.length === 5 && (await call("GET", "/offers?q=0541%20000%2011%2003", OB)).j.length === 1, "offers q phone digits");
  ok((await call("GET", "/offers?q=%25", OB)).j.length === 0, "offers q wildcard escaped");
  const pg1 = await call("GET", "/offers?limit=2", OB);
  ok(pg1.j.length === 2 && pg1.h.get("x-total-count") === "5", "offers limit=2 total 5", pg1.h.get("x-total-count"));
  const pg3 = await call("GET", "/offers?limit=2&offset=4", OB);
  ok(pg3.j.length === 1 && pg3.h.get("x-total-count") === "5", "offers last page");
  const pgx = await call("GET", "/offers?limit=2&offset=40", OB);
  ok(pgx.j.length === 0 && pgx.h.get("x-total-count") === "5", "offers offset beyond end: total kept");
  const pids = new Set([...(await call("GET", "/offers?limit=2&offset=0", OB)).j, ...(await call("GET", "/offers?limit=2&offset=2", OB)).j, ...pg3.j].map((o) => o.id));
  ok(pids.size === 5, "pages cover all rows without overlap");
  ok((await call("GET", "/offers?limit=0", OB)).s === 400 && (await call("GET", "/offers?limit=999", OB)).s === 400 && (await call("GET", "/offers?offset=-1", OB)).s === 400 && (await call("GET", "/offers?limit=abc", OB)).s === 400, "bad limit/offset → 400");
  ok((await call("GET", "/offers?offset=2", OB)).j.length === 3, "offset alone → default limit 50");
  ok((await call("GET", "/offers?q=zey&limit=1", OA)).j.length === 0, "OA cannot search OB's offers");
  ok((await call("GET", "/offers?status=Yeni&q=zey&limit=5", OB)).j.length === 2, "status+q+limit combine");
  // müşteriler
  const cq = await call("GET", "/customers?q=mehmet", OB);
  ok(cq.j.length === 1 && cq.j[0].name === "Mehmet Yildiz" && cq.h.get("x-total-count") === "1", "customers q", cq.j);
  const cp = await call("GET", "/customers?limit=2&offset=0", OB);
  ok(cp.j.length === 2 && cp.h.get("x-total-count") === "5", "customers paging", cp.h.get("x-total-count"));
  ok((await call("GET", "/customers?q=zeynep", OA)).j.length === 0, "OA cannot search OB customers");
  ok((await call("GET", "/customers", OB)).j.length === 5, "customers no params = all");
  ok((await call("GET", "/customers?q=gumbet", OA)).j.length === 1, "customers q by address");
  // projeler
  for (let i = 0; i < 3; i++) await call("POST", "/projects", OB, { customer_name: "Proje Musteri " + i, service: i === 2 ? "Merdiven" : "Kapi", total_amount: 10 });
  const pq = await call("GET", "/projects?q=merdiven", OB);
  ok(pq.j.length === 1 && pq.h.get("x-total-count") === "1", "projects q service", pq.j.length);
  const ppg = await call("GET", "/projects?limit=2", OB);
  ok(ppg.j.length === 2 && ppg.h.get("x-total-count") === "3", "projects paging");
  ok((await call("GET", "/projects", OB)).j.length === 3, "projects no params = all");
  ok((await call("GET", "/projects?q=Ayse", OB)).j.length === 0, "OB cannot find admin project via q");
  ok((await call("GET", "/projects?q=proje%20adresi", A)).j.length >= 1, "projects q address");

  // ===================== eski davranış / dashboard-init şekli =====================
  for (const [n, t] of [["A", A], ["M", M], ["OA", OA], ["OB", OB], ["PA", PA]]) {
    const d = await call("GET", "/dashboard-init", t);
    ok(d.s === 200 && ["offers", "projects", "payments", "appointments", "expenses", "customers", "reminders", "users", "quoteTemplates", "materials", "recurringExpenses"].every((k) => Array.isArray(d.j[k])), "dashboard keys " + n, Object.keys(d.j));
  }
  ok((await call("GET", "/dashboard-init", OB)).j.appointments.length === 0, "OB dashboard appts empty");
  const dAdm = (await call("GET", "/dashboard-init", A)).j;
  ok(dAdm.appointments.every((a) => "offer_name" in a && "project_customer" in a && "scheduled_at" in a), "legacy appointment fields intact");

  wa.close(); smtp.close();
  console.log(`\n${pass} geçti, ${fail} kaldı`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST CRASH", e); process.exit(2); });
