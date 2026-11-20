// v21 BİRLEŞİK SÜRÜM testleri: v17–v20'de ayrı ajanlarca eklenen YENİ uçların çapraz yetki/izolasyon taraması.
//   1) oturumsuz → 401 (tüm yeni uçlar, /api ve /api/v1)       2) personel/saha → finans uçlarında 403, asistan okumalarında finans verisi yok
//   3) ortak A ↔ ortak B: kimlikle erişim (IDOR) — GET/PATCH/DELETE/aksiyon uçları 403/404, listede görünmez
//   4) mass-assignment: gövdeden owner_id/org_id/created_by/user_id yükseltme yok sayılır
//   5) ai_actions onay/ret/geri alma/düzenleme başkasının kaydına uygulanamaz     6) fatura dosyası IDOR / dosya adı / içerik sahteciliği
//   7) Idempotency-Key kullanıcılar arası sızıntı yok                                8) içe aktarma hız sınırı (varsayılan değerle, ayrı sunucu süreci)
// Önkoşul: TEMİZ veritabanı + migrate + seed (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234); sunucu TEST_PORT'ta (varsayılan 4105),
// ASSISTANT_FAKE_NOW="2026-11-20T10:00:00+03:00" ile; cwd = backend klasörü. IMPORT_RATE_MAX TANIMSIZ olmalı (blok 8 varsayılanı sınar).
const path = require("path"), fs = require("fs"), crypto = require("crypto");
const { spawn } = require("child_process");
const db = require("../src/db"); // dotenv'i de yükler
const { makeZip } = require("./helpers/zip");
const PORT = Number(process.env.TEST_PORT || 4105);
const B = `http://localhost:${PORT}/api`;
const ROOT = path.resolve(__dirname, "..");
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 700) : ""); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function call(method, p, token, body, headers = {}, base = B) {
  const r = await fetch(base + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...headers }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
async function upload(p, token, buf, filename, fields = {}, fieldName = "file", base = B) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, String(v));
  fd.append(fieldName, new Blob([buf]), filename);
  const r = await fetch(base + p, { method: "POST", headers: token ? { Authorization: "Bearer " + token } : {}, body: fd, signal: AbortSignal.timeout(60000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
const login = async (e) => (await call("POST", "/auth/login", null, { email: e, password: "pass1234" })).j?.token;
const q1 = async (sql, p) => (await db.query(sql, p)).rows[0];
const qa = async (sql, p) => (await db.query(sql, p)).rows;
const UUID0 = "00000000-0000-4000-8000-000000000000";
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n");

(async () => {
  const [A, M, OA, OB, PA] = await Promise.all(["admin@x.com", "muh@x.com", "oa@x.com", "ob@x.com", "pa@x.com"].map(login));
  ok(A && M && OA && OB && PA, "girişler");
  const U = {}; for (const r of await qa("SELECT id, email FROM users")) U[r.email.split("@")[0]] = r.id;
  // saha kullanıcısı (ortak A oluşturur)
  let r = await call("POST", "/users", OA, { name: "Saha OA", email: "saha21@x.com", password: "pass1234", role: "saha" });
  ok(r.s === 201, "saha kullanıcısı oluşturuldu", r);
  const S = await login("saha21@x.com"); ok(!!S, "saha girişi");
  const orgA = (await q1("SELECT org_id FROM users WHERE id=$1", [U.oa])).org_id;

  // ====================================================================== 1) oturumsuz
  const ROUTES = [
    ["GET", "/invoices"], ["POST", "/invoices", {}], ["GET", "/invoices/summary"], ["GET", "/invoices/export"], ["GET", `/invoices/${UUID0}`], ["PATCH", `/invoices/${UUID0}`, {}], ["DELETE", `/invoices/${UUID0}`],
    ["POST", `/invoices/${UUID0}/mark-paid`, {}], ["POST", `/invoices/${UUID0}/files`, {}], ["GET", `/invoices/${UUID0}/files/${UUID0}`], ["DELETE", `/invoices/${UUID0}/files/${UUID0}`],
    ["GET", "/vat/rates"], ["POST", "/vat/rates", {}], ["PATCH", `/vat/rates/${UUID0}`, {}], ["DELETE", `/vat/rates/${UUID0}`], ["POST", "/vat/withholding-types", {}], ["PATCH", `/vat/withholding-types/${UUID0}`, {}], ["DELETE", `/vat/withholding-types/${UUID0}`],
    ["GET", "/vat/periods"], ["GET", "/vat/periods/2026-11"], ["POST", "/vat/periods/2026-11/calculate", {}], ["PATCH", "/vat/periods/2026-11", {}], ["POST", "/vat/periods/2026-11/lock", {}], ["POST", "/vat/periods/2026-11/unlock", {}], ["GET", "/vat/periods/2026-11/export"], ["GET", "/vat/insights"],
    ["GET", "/tax-calendar"], ["GET", "/tax-calendar/settings"], ["PUT", "/tax-calendar/settings", {}], ["GET", "/tax-calendar/items"], ["POST", "/tax-calendar/items", {}], ["PATCH", `/tax-calendar/items/${UUID0}`, {}], ["DELETE", `/tax-calendar/items/${UUID0}`],
    ["GET", "/tax-calendar/holidays"], ["POST", "/tax-calendar/holidays", {}], ["PATCH", "/tax-calendar/holidays/2026-12-12", {}], ["DELETE", "/tax-calendar/holidays/2026-12-12"],
    ["GET", "/payment-schedule"], ["POST", "/payment-schedule", {}], ["POST", "/payment-schedule/generate", {}], ["GET", `/payment-schedule/${UUID0}`], ["PATCH", `/payment-schedule/${UUID0}`, {}], ["DELETE", `/payment-schedule/${UUID0}`], ["POST", `/payment-schedule/${UUID0}/mark-paid`, {}],
    ["GET", "/receivables/aging"], ["GET", "/receivables/overdue"],
    ["GET", "/message-templates/variables"], ["GET", "/message-templates"], ["GET", `/message-templates/${UUID0}`], ["POST", "/message-templates", {}], ["POST", `/message-templates/${UUID0}/clone`, {}], ["PATCH", `/message-templates/${UUID0}`, {}], ["DELETE", `/message-templates/${UUID0}`], ["POST", `/message-templates/${UUID0}/render`, {}],
    ["GET", "/assistant/prefs"], ["PUT", "/assistant/prefs", {}], ["GET", "/assistant/sector-templates"], ["POST", "/assistant/sector-templates/apply", {}], ["GET", "/assistant/inbox"], ["POST", "/assistant/inbox/read-all", {}], ["POST", `/assistant/inbox/${UUID0}/read`, {}], ["POST", `/assistant/inbox/${UUID0}/unread`, {}], ["POST", `/assistant/inbox/${UUID0}/ack`, {}], ["POST", "/assistant/test-notification", {}],
    ["POST", "/assistant/commands", { text: "bugün ne var" }], ["GET", "/assistant/commands/chips"], ["GET", "/assistant/actions"], ["GET", `/assistant/actions/${UUID0}`], ["PATCH", `/assistant/actions/${UUID0}`, {}], ["POST", `/assistant/actions/${UUID0}/confirm`, {}], ["POST", `/assistant/actions/${UUID0}/reject`, {}], ["POST", `/assistant/actions/${UUID0}/undo`, {}],
    ["GET", "/assistant/imports/consent-notice"], ["POST", "/assistant/imports", {}], ["GET", "/assistant/imports"], ["GET", `/assistant/imports/${UUID0}`], ["POST", `/assistant/imports/${UUID0}/confirm`, {}], ["DELETE", `/assistant/imports/${UUID0}`],
    ["GET", "/assistant/conversations"], ["GET", `/assistant/conversations/${UUID0}`], ["GET", `/assistant/conversations/${UUID0}/messages`], ["PATCH", `/assistant/conversations/${UUID0}`, {}], ["DELETE", `/assistant/conversations/${UUID0}`],
    ["GET", "/assistant/suggestions"], ["PATCH", `/assistant/suggestions/${UUID0}`, {}], ["GET", "/assistant/notes"], ["POST", "/assistant/notes", {}], ["PATCH", `/assistant/notes/${UUID0}`, {}], ["DELETE", `/assistant/notes/${UUID0}`],
    ["GET", "/assistant/customers/5321112233/summary"], ["GET", "/assistant/customers/5321112233/conversations"], ["GET", "/assistant/customers/5321112233/notes"], ["DELETE", "/assistant/customers/5321112233/data"],
    ["GET", "/assistant/consents"], ["POST", "/assistant/consents", {}], ["POST", `/assistant/consents/${UUID0}/withdraw`, {}],
    ["GET", "/assistant/briefing/today"], ["GET", "/assistant/briefings"], ["POST", `/assistant/briefings/${UUID0}/read`, {}], ["GET", "/assistant/closure/today"], ["POST", "/assistant/closure/answers", {}],
    ["GET", "/assistant/insights"], ["POST", "/assistant/insights/refresh", {}], ["GET", `/assistant/insights/${UUID0}`], ["POST", `/assistant/insights/${UUID0}/snooze`, {}], ["POST", `/assistant/insights/${UUID0}/dismiss`, {}], ["POST", `/assistant/insights/${UUID0}/applied`, {}], ["POST", `/assistant/insights/${UUID0}/feedback`, {}],
    ["GET", "/assistant/insight-rules"], ["PUT", "/assistant/insight-rules", {}], ["POST", `/assistant/reminders/${UUID0}/snooze`, {}], ["POST", `/assistant/reminders/${UUID0}/complete`, {}],
    ["GET", "/assistant/followups"], ["POST", "/assistant/followups", {}], ["POST", `/assistant/followups/${UUID0}/done`, {}], ["POST", `/assistant/followups/${UUID0}/snooze`, {}],
    ["GET", "/config"], ["PATCH", "/config", {}], ["GET", "/mobile/home"], ["GET", "/health/worker"],
  ];
  const PUBLIC_OK = new Set(["GET /health/worker"]); // sağlık ucu oturumsuz açık olabilir (içerik kontrol edilir)
  let anon401 = 0;
  for (const [m, p, b] of ROUTES) {
    const k = `${m} ${p}`;
    const rr = await call(m, p, null, b);
    const rv = await call(m, "/v1" + p, null, b, {}, `http://localhost:${PORT}/api`);
    if (PUBLIC_OK.has(`${m} ${p.replace(/\/[0-9a-f-]{36}/g, "")}`)) continue;
    if (rr.s === 401 && rv.s === 401) anon401++; else ok(false, `oturumsuz 401: ${k}`, { s: rr.s, v1: rv.s });
  }
  ok(anon401 >= ROUTES.length - 2, `oturumsuz: ${anon401}/${ROUTES.length} uç 401 (/api ve /api/v1)`);
  const wh = await call("GET", "/health/worker", null);
  ok(!JSON.stringify(wh.j || {}).match(/hostname|\/home|\/var|postgres|DATABASE|secret/i), "health/worker: iç bilgi sızdırmıyor", wh);

  // ====================================================================== 2) personel / saha finans uçları
  const FIN_GET = ["/invoices", "/invoices/summary", "/invoices/export", "/vat/rates", "/vat/periods", "/vat/periods/2026-11", "/vat/insights", "/payment-schedule", "/receivables/aging", "/receivables/overdue", "/message-templates"];
  for (const [nm, tok] of [["saha", S], ["personel", PA]]) {
    for (const p of FIN_GET) { const x = await call("GET", p, tok); ok(x.s === 403, `${nm}: GET ${p} → 403`, x.s); }
    for (const [m, p, b] of [["POST", "/invoices", { direction: "giden", issue_date: "2026-11-01", matrah_kurus: 100, kdv_oran: 20 }], ["POST", "/payment-schedule", {}], ["POST", "/vat/rates", {}], ["PUT", "/tax-calendar/settings", {}], ["POST", "/vat/periods/2026-11/lock", {}], ["POST", "/message-templates", { key: "zz_x", title: "t", body: "b" }]]) {
      const x = await call(m, p, tok, b); ok(x.s === 403, `${nm}: ${m} ${p} → 403`, x.s);
    }
  }
  // komut çubuğu: saha/personel finans komutu
  for (const [nm, tok] of [["saha", S]]) {
    for (const t of ["bu ay ne kadar tahsilat var", "kimden alacağım var", "bu ay ne kadar gider var"]) { const x = await call("POST", "/assistant/commands", tok, { text: t }); ok(x.j && x.j.refused === true, `${nm}: komut reddi "${t}"`, x.j); }
    const x = await call("POST", "/assistant/commands", tok, { text: "Ali Bey'den 5000 TL tahsilat aldım" }); ok(!(x.j && x.j.kind === "action_card"), "saha: ödeme kartı üretilemez", x.j);
  }
  // saha: brifing / insight / kapanış / gelen kutusu finans veri içermez
  for (const p of ["/assistant/briefing/today", "/assistant/briefings", "/assistant/closure/today", "/assistant/insights", "/assistant/followups", "/mobile/home", "/config"]) {
    const x = await call("GET", p, S);
    const raw = JSON.stringify(x.j || {});
    ok(x.s < 500, `saha ${p} sunucu hatası yok`, x.s);
    ok(!/_kurus|"tutar|"amount|"total_amount|"balance|alacak_toplam|tahsilat_toplam/i.test(raw) || /config/.test(p), `saha ${p}: finans alanı yok`, raw.slice(0, 200));
  }
  // saha insight yapılandırması / sektör şablonu / yönetici uçları
  ok((await call("PUT", "/assistant/insight-rules", S, { rules: [] })).s === 403, "saha: insight-rules PUT 403");
  ok((await call("PUT", "/assistant/insight-rules", OA, { rules: [] })).s === 403, "ortak: insight-rules PUT 403 (yalnız admin)");
  ok((await call("PATCH", "/config", OA, { brand: { name: "x" } })).s === 403, "ortak: PATCH /config 403");
  ok((await call("PATCH", "/config", PA, { brand: { name: "x" } })).s === 403, "personel: PATCH /config 403");
  ok((await call("POST", "/assistant/sector-templates/apply", OA, { sector: "insaat" })).s === 403, "ortak: sektör şablonu uygulayamaz");

  // ====================================================================== 3) ortak A ↔ ortak B (IDOR)
  // --- A tarafında kayıtlar
  const offA = (await call("POST", "/offers", OA, { name: "Ali Veli", phone: "0532 111 22 33", service: "Pergola" })).j;
  const prA = (await call("POST", "/projects", OA, { customer_name: "Ali Veli", service: "Pergola", offer_id: offA.id })).j || {};
  let pid = prA.id;
  if (!pid) { const lst = await call("GET", "/projects", OA); pid = (lst.j.items || lst.j)[0]?.id; }
  const inv = await call("POST", "/invoices", OA, { direction: "giden", issue_date: "2026-11-02", matrah_kurus: 100000, kdv_oran: 20, invoice_no: "IDOR-1", counterparty: "Ali Veli" });
  ok(inv.s === 201, "OA fatura", inv); const invId = inv.j && inv.j.id;
  const invFile = await upload(`/invoices/${invId}/files`, OA, PDF, "fatura.pdf");
  ok(invFile.s === 201, "OA fatura dosyası", invFile); const fileId = invFile.j && invFile.j.id;
  const sch = await call("POST", "/payment-schedule", OA, { project_id: pid, amount_kurus: 50000, due_date: "2026-12-01" });
  ok(sch.s === 201, "OA ödeme planı satırı", sch); const schId = sch.j && sch.j.id;
  const tpl = await call("POST", "/message-templates", OA, { key: "oa_gizli", title: "OA gizli", body: "Merhaba {ad}" });
  ok(tpl.s === 201, "OA şablon", tpl); const tplId = tpl.j && tpl.j.id;
  const note = await call("POST", "/assistant/notes", OA, { body: "OA gizli not", phone_key: "5321112233" });
  ok(note.s === 201, "OA not", note); const noteId = note.j && note.j.id;
  const fu = await call("POST", "/assistant/followups", OA, { title: "OA takip", due_date: "2026-11-25", kind: "ara" });
  ok(fu.s === 201 || fu.s === 200, "OA takip", fu); const fuId = fu.j && (fu.j.id || (fu.j.item && fu.j.item.id));
  const card = await call("POST", "/assistant/commands", OA, { text: "yarın saat 14:00 Ali Veli ile görüşme randevusu ekle" });
  ok(card.j && card.j.kind === "action_card", "OA onay kartı", card.j); const actId = card.j && card.j.action && card.j.action.id;
  const chat = Buffer.from("[20.11.2026 10:15:00] Ali Veli: Merhaba, pergola için fiyat alabilir miyim?\n[20.11.2026 10:16:00] Ben: Tabii, yarın uğrayalım\n", "utf8");
  const imp = await upload("/assistant/imports", OA, chat, "WhatsApp Sohbeti - Ali Veli.txt", { consent: "true", consent_version: "2026-11-v1" });
  ok(imp.s === 201, "OA içe aktarma önizleme", imp); const impId = imp.j && (imp.j.id || (imp.j.import && imp.j.import.id));
  let convId = null;
  if (impId) { const cf = await call("POST", `/assistant/imports/${impId}/confirm`, OA, { consent: true, customer_consent: true }); convId = cf.j && (cf.j.conversation_id || (cf.j.conversation && cf.j.conversation.id)); ok(cf.s < 300, "OA içe aktarma onayı", cf); }
  const cons = await call("POST", "/assistant/consents", OA, { customer_key: "5321112233", kind: "aydinlatma", text_version: "2026-11-v1" });
  const consId = cons.j && cons.j.id;
  const sug = await qa("SELECT id FROM import_suggestions WHERE user_id=$1 LIMIT 1", [U.oa]).catch(() => []);
  const inboxRow = await q1("SELECT id FROM notification_outbox WHERE user_id=$1 LIMIT 1", [U.oa]).catch(() => null);

  // koşullu bloklar sessizce atlanmasın: hazırlık kayıtlarının hepsi oluşmuş olmalı
  for (const [k, v] of Object.entries({ invId, fileId, schId, tplId, noteId, fuId, actId, impId, convId, consId })) ok(!!v, `hazırlık kaydı: ${k}`);
  // --- B ihlalleri
  const denied = (s) => s === 403 || s === 404;
  const chk = async (label, m, p, b, tok = OB) => { const x = await call(m, p, tok, b); ok(denied(x.s), `IDOR ${label}: ${m} ${p} → 403/404`, { s: x.s, j: x.j }); return x; };
  if (invId) {
    await chk("fatura", "GET", `/invoices/${invId}`); await chk("fatura", "PATCH", `/invoices/${invId}`, { note: "ele geçirildi" }); await chk("fatura", "DELETE", `/invoices/${invId}`);
    await chk("fatura", "POST", `/invoices/${invId}/mark-paid`, {});
    await chk("fatura dosyası", "GET", `/invoices/${invId}/files/${fileId}`); await chk("fatura dosyası", "DELETE", `/invoices/${invId}/files/${fileId}`);
    const up = await upload(`/invoices/${invId}/files`, OB, PDF, "x.pdf"); ok(denied(up.s), "IDOR: başkasının faturasına dosya yükleme", up.s);
    { const lb = await call("GET", "/invoices", OB); ok(lb.s === 200 && Array.isArray(lb.j) && lb.j.every((x) => x.id !== invId), "B listesinde A faturası yok", lb.s); }
    const row = await q1("SELECT note, status FROM invoices WHERE id=$1", [invId]); ok(row && row.note !== "ele geçirildi", "A faturası değişmedi");
    ok(!!(await q1("SELECT 1 x FROM invoices WHERE id=$1", [invId])), "A faturası silinmedi");
    const sm = await call("GET", "/invoices/summary?period=2026-11", OB); ok(JSON.stringify(sm.j).indexOf("100000") < 0, "B özetinde A tutarı yok");
    const ex = await call("GET", "/invoices/export?period=2026-11", OB); ok(!JSON.stringify(ex.j || "").includes("IDOR-1"), "B dışa aktarımında A faturası yok");
    // B kendi faturasına A'nın dosya kimliğiyle erişmeye çalışır
    const invB = await call("POST", "/invoices", OB, { direction: "giden", issue_date: "2026-11-02", matrah_kurus: 5000, kdv_oran: 20 });
    if (invB.s === 201) { await chk("çapraz dosya", "GET", `/invoices/${invB.j.id}/files/${fileId}`); await chk("çapraz dosya", "DELETE", `/invoices/${invB.j.id}/files/${fileId}`);
      ok(!!(await q1("SELECT 1 x FROM invoice_files WHERE id=$1", [fileId])), "A dosyası çapraz silinmedi"); }
    // personel (PA, OA'nın personeli) faturaya erişemez
    await chk("personel→fatura", "GET", `/invoices/${invId}`, undefined, PA);
  }
  if (schId) { await chk("plan", "GET", `/payment-schedule/${schId}`); await chk("plan", "PATCH", `/payment-schedule/${schId}`, { amount_kurus: 1 }); await chk("plan", "DELETE", `/payment-schedule/${schId}`); await chk("plan", "POST", `/payment-schedule/${schId}/mark-paid`, {}); }
  if (tplId) { await chk("şablon", "GET", `/message-templates/${tplId}`); await chk("şablon", "PATCH", `/message-templates/${tplId}`, { title: "ele" }); await chk("şablon", "DELETE", `/message-templates/${tplId}`); await chk("şablon", "POST", `/message-templates/${tplId}/render`, {}); }
  if (noteId) { await chk("not", "PATCH", `/assistant/notes/${noteId}`, { body: "ele" }); await chk("not", "DELETE", `/assistant/notes/${noteId}`); ok((await call("GET", "/assistant/notes", OB)).j.items.every((x) => x.id !== noteId), "B notlarında A notu yok"); }
  if (fuId) { await chk("takip", "POST", `/assistant/followups/${fuId}/done`, {}); await chk("takip", "POST", `/assistant/followups/${fuId}/snooze`, { days: 1 }); }
  if (actId) {
    await chk("ai_action", "GET", `/assistant/actions/${actId}`); await chk("ai_action", "PATCH", `/assistant/actions/${actId}`, { fields: { time: "09:00" } });
    await chk("ai_action", "POST", `/assistant/actions/${actId}/confirm`, {}); await chk("ai_action", "POST", `/assistant/actions/${actId}/reject`, {}); await chk("ai_action", "POST", `/assistant/actions/${actId}/undo`, {});
    ok((await call("GET", "/assistant/actions", OB)).j.items.every((x) => x.id !== actId), "B aksiyon listesinde A kartı yok");
    const st = await q1("SELECT status FROM ai_actions WHERE id=$1", [actId]); ok(st.status === "onerildi", "A kartı B tarafından değiştirilmedi", st);
    await chk("ai_action(personel)", "POST", `/assistant/actions/${actId}/confirm`, {}, PA);
    await chk("ai_action(admin)", "POST", `/assistant/actions/${actId}/confirm`, {}, A); // admin bile başkasının kartını onaylayamaz
  }
  if (impId) { await chk("içe aktarma", "GET", `/assistant/imports/${impId}`); await chk("içe aktarma", "POST", `/assistant/imports/${impId}/confirm`, { consent: true }); await chk("içe aktarma", "DELETE", `/assistant/imports/${impId}`); }
  if (convId) { await chk("konuşma", "GET", `/assistant/conversations/${convId}`); await chk("konuşma", "GET", `/assistant/conversations/${convId}/messages`); await chk("konuşma", "PATCH", `/assistant/conversations/${convId}`, { title: "ele" }); await chk("konuşma", "DELETE", `/assistant/conversations/${convId}`);
    ok((await call("GET", "/assistant/conversations", OB)).j.items.every((x) => x.id !== convId), "B konuşma listesinde A konuşması yok"); }
  if (consId) await chk("rıza", "POST", `/assistant/consents/${consId}/withdraw`, {});
  if (sug[0]) await chk("öneri", "PATCH", `/assistant/suggestions/${sug[0].id}`, { status: "rejected" });
  if (inboxRow) { await chk("bildirim", "POST", `/assistant/inbox/${inboxRow.id}/read`, {}); await chk("bildirim", "POST", `/assistant/inbox/${inboxRow.id}/ack`, {}); }
  // müşteri kartı anahtarı: B, A'nın müşterisinin kartını/yazışmasını/notunu göremez, verisini silemez
  for (const sub of ["summary", "conversations", "notes"]) { const x = await call("GET", `/assistant/customers/5321112233/${sub}`, OB); ok(denied(x.s) || (x.j && x.j.items && x.j.items.length === 0), `B müşteri kartı ${sub}`, { s: x.s }); }
  { const x = await call("DELETE", "/assistant/customers/5321112233/data", OB); ok(denied(x.s), "B başkasının müşteri verisini silemez", x.s); ok(!!(await q1("SELECT 1 x FROM ai_notes WHERE id=$1", [noteId])), "A notu B silme denemesinden sonra duruyor"); }
  // B komut çubuğu A'nın müşterisini bilmez
  { const x = await call("POST", "/assistant/commands", OB, { text: "Ali Veli'ye yarın 15:00 randevu ekle" }); ok(!(x.j && x.j.kind === "action_card"), "B: A'nın müşterisiyle kart üretilemez", x.j && { k: x.j.kind, m: x.j.message }); }
  { const x = await call("POST", "/assistant/commands", OB, { text: "Ali Veli'nin telefonu ne" }); ok(!JSON.stringify(x.j).includes("532"), "B: A'nın müşteri telefonu sızmaz"); }

  // ====================================================================== 4) mass-assignment
  const evil = { owner_id: U.ob, org_id: UUID0, created_by: U.ob, user_id: U.ob, owner_user_id: U.ob, id: UUID0 };
  {
    const x = await call("POST", "/invoices", OA, { direction: "gelen", issue_date: "2026-11-03", matrah_kurus: 2000, kdv_oran: 20, ...evil });
    ok(x.s === 201, "mass-assign: fatura oluşur", x);
    if (x.s === 201) { const row = await q1("SELECT owner_id, org_id, created_by, id FROM invoices WHERE id=$1", [x.j.id]); ok(row.owner_id === U.oa && row.org_id === orgA && row.created_by === U.oa && row.id !== UUID0, "mass-assign: fatura sahibi/org/oluşturan istekten alınmadı", row);
      const p = await call("PATCH", `/invoices/${x.j.id}`, OA, { note: "n", ...evil }); const row2 = await q1("SELECT owner_id, org_id FROM invoices WHERE id=$1", [x.j.id]); ok(row2.owner_id === U.oa && row2.org_id === orgA, "mass-assign: PATCH fatura sahibi değişmedi", { p: p.s, row2 }); }
    const y = await call("POST", "/payment-schedule", OA, { project_id: pid, amount_kurus: 7000, due_date: "2026-12-02", ...evil });
    if (y.s === 201) { const row = await q1("SELECT * FROM payment_schedule WHERE id=$1", [y.j.id]).catch(() => null); if (row) ok((row.owner_id === undefined || row.owner_id === U.oa) && (row.org_id === undefined || row.org_id === orgA), "mass-assign: plan satırı", row); }
    const z = await call("POST", "/message-templates", OA, { key: "ma_test", title: "t", body: "b {ad}", ...evil, is_system: true, system: true, org_wide: true });
    if (z.s === 201) { const row = await q1("SELECT * FROM message_templates WHERE id=$1", [z.j.id]); ok((row.owner_id === undefined || row.owner_id === null || row.owner_id === U.oa) && row.org_id === orgA && !row.is_system, "mass-assign: şablon sahibi/sistem bayrağı", { o: row.owner_id, org: row.org_id, sys: row.is_system }); }
    const n = await call("POST", "/assistant/notes", OA, { body: "ma not", ...evil });
    if (n.s === 201) { const row = await q1("SELECT owner_user_id, org_id FROM ai_notes WHERE id=$1", [n.j.id]); ok(row.owner_user_id === U.oa && row.org_id === orgA, "mass-assign: not sahibi", row); }
    const f = await call("POST", "/assistant/followups", OA, { title: "ma takip", due_date: "2026-11-30", ...evil });
    if (f.s < 300) { const id = f.j.id || (f.j.item && f.j.item.id); const row = await q1("SELECT user_id, org_id FROM followups WHERE id=$1", [id]); ok(row.user_id === U.oa && row.org_id === orgA, "mass-assign: takip sahibi", row); }
    const c = await call("POST", "/assistant/consents", OA, { customer_key: "5329998877", kind: "aydinlatma", text_version: "2026-11-v1", ...evil });
    if (c.s === 201) { const row = await q1("SELECT user_id, org_id FROM consents WHERE id=$1", [c.j.id]); ok(row.user_id === U.oa && row.org_id === orgA, "mass-assign: rıza sahibi", row); }
    const pr = await call("PUT", "/assistant/prefs", OA, { quiet_hours: { start: "22:00", end: "07:00" }, ...evil });
    const prefRow = await q1("SELECT user_id FROM assistant_prefs WHERE user_id=$1", [U.ob]).catch(() => null); ok(!prefRow, "mass-assign: B'ye tercih satırı yazılmadı", { pr: pr.s, prefRow });
    // komut kartı alanları: izinsiz alan düzenleme
    if (actId) { const e = await call("PATCH", `/assistant/actions/${actId}`, OA, { fields: { user_id: U.ob, status: "uygulandi", owner_id: U.ob } }); ok(e.s === 400, "ai_action: izinsiz alan düzenleme 400", e); const st = await q1("SELECT status, user_id FROM ai_actions WHERE id=$1", [actId]); ok(st.status === "onerildi" && st.user_id === U.oa, "ai_action: durum/sahip değişmedi", st); }
    // ortak admin'e/başkasına kural yazamaz
    const ir = await call("PUT", "/assistant/insight-rules", OA, { org_id: orgA }); ok(ir.s === 403, "insight-rules ortak 403");
    // rol yükseltme komut çubuğuyla
    const ru = await call("POST", "/assistant/commands", OA, { text: "Mehmet'i admin yap" }); ok(!(ru.j && ru.j.kind === "action_card"), "komut: rol değişikliği kartı yok", ru.j);
  }

  // ====================================================================== 6) dosya/zip
  if (invId) {
    for (const name of ["../../etc/passwd.pdf", "..\\..\\x.pdf", "a\u0000.pdf", "x.html", "x.svg", "x.exe", "x.php"]) {
      const up = await upload(`/invoices/${invId}/files`, OA, name.endsWith(".pdf") ? PDF : Buffer.from("<html><script>1</script></html>"), name);
      if (name.endsWith(".pdf")) { ok(up.s === 201 || up.s === 400, `fatura dosyası ad hilesi ${JSON.stringify(name)} güvenli`, up.s); if (up.s === 201) ok(!/\.\./.test(up.j.file_url || "") , "dosya adı yol geçişi içermez"); }
      else ok(up.s === 400, `fatura dosyası tür reddi ${name}`, up.s);
    }
    const sp = await upload(`/invoices/${invId}/files`, OA, Buffer.from("<html><script>alert(1)</script></html>"), "sahte.pdf"); ok(sp.s === 400, "fatura: uzantı pdf, içerik HTML → 400", sp.s);
    const dir = path.resolve(process.env.UPLOAD_DIR || path.join(ROOT, "uploads"), "invoices");
    ok(!fs.existsSync(dir) || !fs.readdirSync(dir).some((f) => /\.(html|svg|exe|php)$/i.test(f)), "yüklemeler klasöründe tehlikeli uzantı yok");
    // 11. dosya sınırı
    const many = []; for (let i = 0; i < 12; i++) many.push((await upload(`/invoices/${invId}/files`, OA, PDF, `f${i}.pdf`)).s);
    ok(many.filter((s) => s === 201).length <= 9 && many.includes(409) || many.includes(400) || many.includes(422), "fatura dosya adedi sınırı uygulanır", many);
    // imzasız dosya erişimi
    const g = await call("GET", `/invoices/${invId}/files/${fileId}`, null); ok(g.s === 401, "dosya uç noktası oturumsuz 401");
    const rawUrl = (invFile.j.file_url || "").replace(/\?.*$/, ""); if (rawUrl) { const rr2 = await fetch(rawUrl); ok(rr2.status === 401 || rr2.status === 403, "imzasız /uploads/invoices bağlantısı kapalı", rr2.status); }
  }
  // zip: yol geçişi, bomba, iç içe, sahte txt
  {
    const bad = [["yol geçişi", makeZip([{ name: "../../evil.txt", data: Buffer.from("x") }, { name: "_chat.txt", data: chat }])],
      ["bomba", makeZip([{ name: "_chat.txt", data: Buffer.alloc(30 * 1024 * 1024, 0x41) }])],
      ["boş", Buffer.alloc(10)], ["txt yok", makeZip([{ name: "a.jpg", data: Buffer.from("x") }])]];
    for (const [nm, buf] of bad) { const x = await upload("/assistant/imports", OA, buf, "chat.zip", { consent: "true", consent_version: "2026-11-v1" }); ok(x.s >= 400 && x.s < 500, `zip ${nm} → 4xx`, x.s); }
    const good = await upload("/assistant/imports", OA, makeZip([{ name: "WhatsApp Chat.txt", data: chat }, { name: "IMG-1.jpg", data: Buffer.from("jpg") }]), "chat.zip", { consent: "true", consent_version: "2026-11-v1" }); ok(good.s === 201, "geçerli zip kabul", good);
    const noFile = await call("POST", "/assistant/imports", OA, {}); ok(noFile.s === 400, "içe aktarma: dosya/metin yok → 400", noFile.s);
    const wrongField = await upload("/assistant/imports", OA, chat, "x.txt", {}, "attachment"); ok(wrongField.s === 400, "beklenmeyen dosya alanı → 400", wrongField.s);
    const inj = await call("POST", "/assistant/imports", OA, { text: "[20.11.2026 10:15:00] Ali: <script>alert(1)</script> '); DROP TABLE users;--\n", source: "share" }); ok(inj.s < 500, "enjeksiyon metni 5xx vermez", inj.s);
    ok(!!(await q1("SELECT to_regclass('public.users') t")).t, "users tablosu duruyor");
  }

  // ====================================================================== 7) Idempotency-Key kullanıcılar arası
  {
    const key = "idem-" + crypto.randomBytes(6).toString("hex");
    const a1 = await call("POST", "/assistant/notes", OA, { body: "idem A" }, { "Idempotency-Key": key });
    const b1 = await call("POST", "/assistant/notes", OB, { body: "idem A" }, { "Idempotency-Key": key });
    ok(a1.s === 201 && b1.s === 201 && a1.j.id !== b1.j.id, "Idempotency-Key kullanıcıya özel (B, A'nın yanıtını almaz)", { a: a1.j && a1.j.id, b: b1.j && b1.j.id });
    ok(!(await q1("SELECT 1 x FROM ai_notes WHERE id=$1 AND owner_user_id<>$2", [b1.j.id, U.ob])), "B notu B'ye ait");
    const a2 = await call("POST", "/assistant/notes", OA, { body: "idem A" }, { "Idempotency-Key": key });
    ok(a2.j && a2.j.id === a1.j.id, "aynı kullanıcıda tekrar: aynı yanıt");
  }

  // ====================================================================== 5b) onay sırasında yetki: REST yetkisi aşılamaz
  {
    // saha randevu oluşturamaz (ROLE_MATRIX); kart bile üretilmez. personel gider kartı → REST yine denetler
    const x = await call("POST", "/assistant/commands", S, { text: "yarın saat 14:00 randevu ekle" }); ok(!(x.j && x.j.kind === "action_card"), "saha: randevu kartı yok", x.j);
    // kartı DB'den başkası adına enjekte et → confirm sahibinin yetkisiyle REST'e gider (kullanıcı eşleşmesi)
    const fake = await q1(`INSERT INTO ai_actions (org_id,user_id,origin,intent,risk,raw_text,params,args,preview,params_hash,status,raw_expires_at,expires_at)
      VALUES ($1,$2,'command_bar','expense.add','R2','x','{"amount_kurus":100,"category":"x"}','{"request":{"method":"POST","path":"/expenses","body":{"category":"x","amount":1}},"meta":{}}','{"summary":"x","fields":[],"ambiguities":[],"warnings":[]}','h'||gen_random_uuid()::text,'onerildi',now()+interval '1 day',now()+interval '1 day') RETURNING id`, [orgA, U.ob]);
    const cf = await call("POST", `/assistant/actions/${fake.id}/confirm`, S, {}); ok(denied(cf.s), "saha, B'nin kartını onaylayamaz", cf.s);
    const cf2 = await call("POST", `/assistant/actions/${fake.id}/confirm`, OB, {}); ok(cf2.s < 500, "enjekte kart: onay sunucu hatası vermez", cf2);
    const exp = await qa("SELECT 1 FROM expenses WHERE amount=1 AND category='x'");
    ok(exp.length === 0 || cf2.s < 300, "kart 'args.request' yok sayıldı mı: gider kaydı ancak geçerli yetkiyle", { n: exp.length, s: cf2.s });
  }

  // ====================================================================== 8) içe aktarma hız sınırı (varsayılan 20 / 15 dk / kullanıcı) — ayrı süreç
  {
    const P2 = 4125;
    const env = { ...process.env, PORT: String(P2), APP_URL: `http://localhost:${P2}`, ASSISTANT_FAKE_NOW: process.env.ASSISTANT_FAKE_NOW || "2026-11-20T10:00:00+03:00" };
    delete env.IMPORT_RATE_MAX;
    const srv = spawn("node", [path.join(ROOT, "src", "server.js")], { cwd: ROOT, env, stdio: "ignore" });
    for (let i = 0; i < 40; i++) { await sleep(250); try { if ((await fetch(`http://localhost:${P2}/api/health`)).ok) break; } catch {} }
    const base2 = `http://localhost:${P2}/api`;
    const t1 = (await call("POST", "/auth/login", null, { email: "oa@x.com", password: "pass1234" }, {}, base2)).j.token;
    const t2 = (await call("POST", "/auth/login", null, { email: "ob@x.com", password: "pass1234" }, {}, base2)).j.token;
    const codes = [];
    for (let i = 0; i < 22; i++) codes.push((await call("POST", "/assistant/imports", t1, { text: `[20.11.2026 10:${10 + (i % 40)}:00] Ali: merhaba ${i}\n`, source: "share" }, {}, base2)).s);
    ok(codes.slice(0, 20).every((s) => s < 429) && codes[20] === 429 && codes[21] === 429, "içe aktarma: 20 istekten sonra 429", codes);
    const other = await call("POST", "/assistant/imports", t2, { text: "[20.11.2026 10:10:00] Veli: selam\n", source: "share" }, {}, base2);
    ok(other.s < 429, "içe aktarma sınırı kullanıcıya özel (B etkilenmez)", other.s);
    srv.kill("SIGTERM"); await sleep(300);
  }


  // ====================================================================== 9) paketler arası şema dikişi: müdür kuralları M7/M8 GERÇEK fatura/KDV tablolarıyla
  {
    const clock = require("../src/assistant/clock"), engine = require("../src/assistant/manager/engine");
    clock.setFake(process.env.ASSISTANT_FAKE_NOW || "2026-11-20T10:00:00+03:00");
    const today = clock.istanbulDateStr(clock.now());
    const pj = (await call("POST", "/projects", A, { customer_name: "Dikiş Müşteri", service: "Pergola", total_amount: 500000 })).j;
    const pay = await call("POST", `/projects/${pj.id}/payments`, A, { amount: 100000, method: "Havale" });
    ok(pay.s === 201, "M7: ödeme kaydı", pay.s);
    await db.query("UPDATE payments SET paid_at = now() - interval '20 days' WHERE project_id = $1", [pj.id]);
    const ledger = (await q1("SELECT id FROM users WHERE role='admin' ORDER BY created_at LIMIT 1")).id;
    const m7 = async () => { await engine.refresh(orgA, "business", { now: clock.now(), date: today }); return (await qa("SELECT status, evidence FROM insights WHERE org_id=$1 AND rule_key='M7' AND entity_id=$2", [orgA, pj.id])); };
    let rows = await m7();
    ok(rows.length >= 1, "M7: faturasız tahsilat tespit edildi (gerçek invoices tablosu okundu)", rows);
    const iv = await call("POST", "/invoices", A, { direction: "giden", issue_date: today, matrah_kurus: 8333333, kdv_oran: 20, project_id: pj.id, invoice_no: "DKS-1", status: "kesildi" });
    ok(iv.s === 201, "M7: proje faturası", iv);
    rows = await m7(); ok(rows.every((r) => r.status !== "acik"), "M7: fatura kesilince faturasız tahsilat uyarısı kapanır", rows.map((r) => r.status));
    // M8: açık KDV dönemi, son gün yakın, ödenecek > 0
    await call("POST", "/vat/periods/2026-10/calculate", A, {});
    await db.query("UPDATE vat_periods SET odenecek_kurus = 500000, due_date = ($2::date + 3) WHERE owner_id = $1 AND period_key = '2026-10'", [ledger, today]);
    await engine.refresh(orgA, "business", { now: clock.now(), date: today });
    const m8 = await qa("SELECT status FROM insights WHERE org_id=$1 AND rule_key='M8'", [orgA]);
    ok(m8.length >= 1, "M8: KDV son günü uyarısı gerçek vat_periods ile üretildi", m8);
  }


  // ====================================================================== 10) VAPID anahtarsız başlangıç (üretimde isteğe bağlı olmalı) + bozuk multipart
  {
    const P3 = 4126;
    const env = { ...process.env, PORT: String(P3), APP_URL: `http://localhost:${P3}` };
    // dotenv, ortamda tanımlı (boş da olsa) değişkeni .env ile ezmez → anahtarlar boş string ile geçersiz kılınır
    env.VAPID_PUBLIC_KEY = ""; env.VAPID_PRIVATE_KEY = "";
    const srv = spawn("node", [path.join(ROOT, "src", "server.js")], { cwd: ROOT, env, stdio: "ignore" });
    let up = false, code = null; srv.on("exit", (c) => { code = c; });
    for (let i = 0; i < 40 && code === null; i++) { await sleep(250); try { if ((await fetch(`http://localhost:${P3}/api/health`)).ok) { up = true; break; } } catch {} }
    ok(up && code === null, "VAPID anahtarı boşken sunucu başlar (web-push isteğe bağlı)", { up, code });
    if (up) {
      const b3 = `http://localhost:${P3}/api`;
      const t = (await call("POST", "/auth/login", null, { email: "oa@x.com", password: "pass1234" }, {}, b3)).j.token;
      const k = await call("GET", "/push/vapid-public-key", t, undefined, {}, b3); ok(k.s === 200 && k.j.publicKey === null, "vapid-public-key anahtarsız null döner", k);
      // bozuk multipart gövdesi 5xx değil 400
      const raw = await fetch(b3 + "/assistant/imports", { method: "POST", headers: { Authorization: "Bearer " + t, "Content-Type": "multipart/form-data; boundary=XX" }, body: "--XX\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n\r\nabc" });
      ok(raw.status === 400, "bozuk/yarım multipart → 400", raw.status);
    }
    srv.kill("SIGTERM"); await sleep(300);
  }

  console.log(`\napi_test_v21: ${pass} geçti, ${fail} başarısız`);
  await db.pool.end();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST ÇÖKTÜ:", e); process.exit(2); });
