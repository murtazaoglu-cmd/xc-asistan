const B = "http://localhost:4100/api";
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra) : ""); } };
async function call(method, path, token, body) {
  const r = await fetch(B + path, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(8000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
const login = async (e) => (await call("POST", "/auth/login", null, { email: e, password: "pass1234" })).j.token;
(async () => {
  const [A, M, OA, OB, PA] = await Promise.all(["admin@x.com", "muh@x.com", "oa@x.com", "ob@x.com", "pa@x.com"].map(login));
  ok(A && M && OA && OB && PA, "logins");
  ok((await call("POST", "/auth/login", null, { email: "ADMIN@x.com", password: "pass1234" })).s === 200, "case-insens login");
  ok((await call("POST", "/auth/login", null, { email: "nope@x.com", password: "x" })).s === 401, "bad login 401");

  // offers
  const oAdmin = (await call("POST", "/offers", A, { name: "Adm Musteri", phone: "0500 000 00 01", service: "Demir" })).j;
  const oOA = (await call("POST", "/offers", OA, { name: "OA Musteri", phone: "0500 000 00 02", service: "Pergola" })).j;
  ok(oAdmin.id && oOA.id && oOA.code !== oAdmin.code, "offers create", [oAdmin, oOA]);
  ok((await call("GET", "/offers/" + oOA.id, OB)).s === 403, "OB cannot read OA offer");
  ok((await call("GET", "/offers/" + oOA.id, OA)).s === 200, "OA reads own");
  ok((await call("GET", "/offers/not-a-uuid", A)).s === 400, "invalid uuid -> 400 not hang");

  // quotes
  let q = await call("POST", "/quotes/" + oOA.id, OA, { items: [{ desc: "x", qty: 1, price: 3, vatIncluded: true }] });
  ok(q.s === 201 && Number(q.j.total) === 3 && Number(q.j.subtotal) + Number(q.j.tax) === 3, "quote KDV dahil 3 TL", q);
  q = await call("POST", "/quotes/" + oAdmin.id, OA, { items: [{ desc: "x", qty: 1, price: 3 }] });
  ok(q.s === 403, "OA cannot quote admin offer", q.s);
  q = await call("POST", "/quotes/" + oOA.id, OA, { items: [{ desc: "x", qty: "abc", price: 3 }] });
  ok(q.s === 400, "NaN rejected", q.s);

  // accept -> project (once)
  let st = await call("PATCH", "/offers/" + oOA.id + "/status", OA, { status: "Kabul Edildi" });
  ok(st.s === 200, "accept ok", st);
  st = await call("PATCH", "/offers/" + oOA.id + "/status", OA, { status: "Kabul Edildi" });
  const projs = (await call("GET", "/projects", OA)).j;
  ok(projs.length === 1 && projs[0].owner_id, "exactly one project, owned", projs.length);
  const pid = projs[0].id;
  ok((await call("GET", "/projects", OB)).j.length === 0, "OB sees no projects");
  const full = (await call("GET", "/projects/" + pid + "/full", OA)).j;
  ok(full.tasks.length === 1 && full.tasks[0].assigned_user_id, "task copied+assigned", full.tasks);
  ok((await call("GET", "/projects/" + pid + "/full", OB)).s === 403, "OB project full 403");

  // bulk accept
  const o3 = (await call("POST", "/offers", A, { name: "Bulk", phone: "0500 000 00 03", service: "Kapi" })).j;
  const bs = await call("PATCH", "/offers/bulk-status", A, { ids: [o3.id], status: "Kabul Edildi" });
  ok(bs.s === 200 && (await call("GET", "/projects", A)).j.some((p) => p.offer_id === o3.id), "bulk accept creates project", bs);
  // bulk delete accepted offer (FK)
  const bd = await call("DELETE", "/offers/bulk", A, { ids: [o3.id] });
  ok(bd.s === 200 && bd.j.deleted === 1, "bulk delete accepted offer", bd);
  const bd2 = await call("DELETE", "/offers/bulk", OB, { ids: [oOA.id] });
  ok(bd2.j.deleted === 0, "OB cannot bulk-delete OA offer", bd2);

  // payments / expenses ledgers
  let pay = await call("POST", "/projects/" + pid + "/payments", OA, { amount: 1000, method: "Nakit" });
  ok(pay.s === 201, "OA add payment", pay);
  ok((await call("POST", "/projects/" + pid + "/payments", OA, { amount: -5, method: "Nakit" })).s === 400, "negative payment 400");
  ok((await call("POST", "/projects/" + pid + "/payments", OA, { amount: 5, method: "Bitcoin" })).s === 400, "bad method 400");
  ok((await call("PATCH", "/projects/payments/" + pay.j.id, OB, { amount: 1 })).s === 403, "OB cannot edit OA payment");
  ok((await call("DELETE", "/projects/payments/" + pay.j.id, OB)).s === 403, "OB cannot delete OA payment");
  const aProj = (await call("POST", "/projects", A, { customer_name: "Adm Proje", service: "X", total_amount: 5000 })).j;
  ok(aProj.code && /^PRJ-/.test(aProj.code), "admin project", aProj);
  ok((await call("POST", "/projects/" + aProj.id + "/payments", OA, { amount: 99, method: "Nakit" })).s === 403, "OA cannot pay into admin project");
  const mp = await call("POST", "/projects/" + aProj.id + "/payments", M, { amount: 200, method: "Havale" });
  ok(mp.s === 201, "muhasebe payment", mp);
  const adminPays = (await call("GET", "/projects/payments/all", A)).j;
  ok(adminPays.some((p) => p.id === mp.j.id), "muhasebe payment lands in admin ledger");
  ok(!adminPays.some((p) => p.id === pay.j.id), "admin ledger excludes OA payment");
  const dashA = (await call("GET", "/dashboard-init", A)).j;
  ok(dashA.payments.some((p) => p.id === mp.j.id) && !dashA.payments.some((p) => p.id === pay.j.id), "dashboard payments scoped");

  const ex = await call("POST", "/expenses", OA, { category: "Kira", amount: 500, scope: "dukkan" });
  ok(ex.s === 201, "OA general expense", ex);
  ok((await call("PATCH", "/expenses/" + ex.j.id, OB, { amount: 1 })).s === 403, "OB cannot edit OA expense");
  ok((await call("DELETE", "/expenses/" + ex.j.id, A)).s === 200, "admin can delete (override)");
  const ex2 = await call("POST", "/expenses", OA, { category: "Kira", amount: 500 });
  const dOA = (await call("GET", "/dashboard-init", OA)).j;
  ok(dOA.expenses.some((e) => e.id === ex2.j.id), "OA general expense in dashboard");
  ok((await call("GET", "/expenses", OB)).j.length === 0, "OB sees no OA expense");
  ok((await call("POST", "/expenses", PA, { category: "X", amount: 5 })).s === 403, "personel no general expense");
  const mex = await call("POST", "/expenses", M, { category: "Elektrik", amount: 50 });
  ok((await call("GET", "/expenses", A)).j.some((e) => e.id === mex.j.id), "muhasebe expense in admin ledger");

  // customers isolation
  const cu = await call("POST", "/customers", OA, { name: "Cust OA", phone: "0555 111 22 33" });
  ok(cu.s === 201, "OA create customer", cu);
  ok((await call("DELETE", "/customers/05551112233", OB)).s === 200, "delete by OB returns 200");
  ok((await call("GET", "/customers", OA)).j.some((c) => c.phone_key === "05551112233"), "OA customer survives OB delete");
  ok((await call("PATCH", "/customers/05551112233", OB, { name: "hack" })).s === 404, "OB cannot patch OA customer");
  const hist = await call("GET", "/customers/05000000002", OB);
  ok(hist.s === 200 && hist.j.offers.length === 0, "OB cannot read OA customer history", hist.j);

  // users
  ok((await call("POST", "/users", OA, { name: "M", email: "m2@x.com", password: "abcdef", role: "muhasebe" })).s === 400, "ortak cannot create muhasebe");
  const nu = await call("POST", "/users", OA, { name: "P2", email: "P2@x.com", password: "abcdef", role: "personel" });
  ok(nu.s === 201, "ortak create personel", nu);
  ok((await call("POST", "/users", OA, { name: "P3", email: "p2@X.com", password: "abcdef", role: "personel" })).s === 409, "email case dup 409");
  ok((await call("GET", "/users", OB)).j.length === 0, "OB sees no team");
  const dl = await call("DELETE", "/users/" + nu.j.id, OA);
  ok(dl.s === 200, "delete user ok", dl);
  const nu2 = await call("POST", "/users", OA, { name: "P4", email: "p4@x.com", password: "abcdef", role: "personel" });
  const tok4 = await login("p4@x.com");
  await call("POST", "/projects/" + pid + "/expenses", OA, { category: "Boya", amount: 10, owner_id: nu2.j.id });
  ok((await call("DELETE", "/users/" + nu2.j.id, OA)).s === 200, "delete user owning ledger rows (transfer)");

  // reports
  const rv = await call("GET", "/reports/revenue", OB);
  ok(rv.s === 200 && rv.j.length === 0, "OB revenue empty", rv.j);
  const rv2 = await call("GET", "/reports/revenue?range=yearly", OA);
  ok(rv2.s === 200 && rv2.j.length === 1 && /^\d{4}$/.test(rv2.j[0].period) && rv2.j[0].total === 1000, "OA yearly revenue", rv2.j);
  const sm = await call("GET", "/reports/summary", OB);
  ok(sm.j.totalOffers === 0 && sm.j.totalRevenue === 0, "OB summary empty", sm.j);

  // reminders / appointments
  const rm = await call("POST", "/reminders", OA, { title: "Ara", remind_at: new Date(Date.now() + 86400000).toISOString() });
  ok(rm.s === 201, "reminder create", rm);
  ok((await call("GET", "/reminders", OB)).j.length === 0, "OB cannot see OA reminders");
  ok((await call("PATCH", "/reminders/" + rm.j.id, OB, { status: "tamamlandi" })).s === 403, "OB cannot patch reminder");
  ok((await call("GET", "/reminders", A)).j.length === 1, "admin sees reminders");
  const ap = await call("POST", "/appointments", OA, { type: "kesif", scheduled_at: new Date().toISOString(), notes: "t" });
  ok(ap.s === 201, "appointment create", ap);
  ok((await call("PATCH", "/appointments/" + ap.j.id, OB, { status: "iptal" })).s === 403, "OB cannot patch appt");
  ok((await call("GET", "/appointments", OB)).j.length === 0, "OB sees no appts");
  ok((await call("GET", "/appointments", OA)).j.some((a) => a.id === ap.j.id), "OA sees own appt");
  ok((await call("POST", "/appointments", OB, { type: "kesif", scheduled_at: new Date().toISOString(), offer_id: oAdmin.id })).s === 403, "OB cannot attach appt to admin offer");

  // dashboards for every role
  for (const [n, t] of [["A", A], ["M", M], ["OA", OA], ["OB", OB], ["PA", PA]]) {
    const d = await call("GET", "/dashboard-init", t);
    ok(d.s === 200 && Array.isArray(d.j.offers), "dashboard " + n, d);
    if (n === "OB") ok(d.j.offers.length === 0 && d.j.reminders.length === 0 && d.j.customers.length === 0, "OB dashboard empty", { o: d.j.offers.length, r: d.j.reminders.length, c: d.j.customers.length });
    if (n === "OA") ok(d.j.quoteTemplates.length === 0 && d.j.users.every((u) => u.id), "OA templates/users scoped");
    if (n === "PA") ok(d.j.offers.length === 0 && d.j.quoteTemplates.length === 0, "PA dashboard scoped", { o: d.j.offers.length });
  }

  // recurring
  const rc = await call("POST", "/recurring-expenses", OA, { category: "Kira", amount: 100, scope: "dukkan" });
  const a1 = await call("POST", "/recurring-expenses/" + rc.j.id + "/apply", OA);
  const a2 = await call("POST", "/recurring-expenses/" + rc.j.id + "/apply", OA);
  ok(a1.s === 201 && a2.s === 409, "recurring apply once", [a1.s, a2.s, a2.j]);
  const [r1, r2] = await Promise.all([call("POST", "/recurring-expenses/" + rc.j.id + "/apply", A), call("POST", "/recurring-expenses/" + rc.j.id + "/apply", A)]);
  ok(r1.s === 409 && r2.s === 409, "recurring already applied -> 409", [r1.s, r2.s]);
  const rc2 = await call("POST", "/recurring-expenses", OB, { category: "Su", amount: 10 });
  const rr = await Promise.all([call("POST", "/recurring-expenses/" + rc2.j.id + "/apply", OB), call("POST", "/recurring-expenses/" + rc2.j.id + "/apply", OB)]);
  ok(rr.map((x) => x.s).sort().join() === "201,409", "concurrent apply: exactly one", rr.map((x) => x.s));

  // tracking acceptance by customer
  const o5 = (await call("POST", "/offers", OA, { name: "Trk", phone: "0500 000 00 05", service: "Kapi" })).j;
  await call("POST", "/quotes/" + o5.id, OA, { items: [{ desc: "a", qty: 2, price: 100 }] });
  const dec = await fetch(B + "/track/" + o5.trackingCode + "/decision", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ decision: "Kabul Edildi" }) });
  ok(dec.status === 200, "track decision");
  const pr = (await call("GET", "/projects", OA)).j.find((p) => p.offer_id === o5.id);
  ok(pr && pr.owner_id && Number(pr.total_amount) === 240, "tracked project owned + total 240", pr);

  // shares
  const sh = await call("POST", "/shares", OB, { resource_type: "project", resource_id: pid, user_id: PA && (await call("GET", "/users", OA)).j[0]?.id });
  ok(sh.s === 403, "OB cannot share OA project", sh.s);

  // concurrent offer creation -> unique codes
  const many = await Promise.all(Array.from({ length: 12 }, (_, i) => call("POST", "/offers", A, { name: "C" + i, phone: "050000010" + i, service: "S" })));
  ok(many.every((r) => r.s === 201) && new Set(many.map((r) => r.j.code)).size === 12, "12 concurrent unique codes", many.map((r) => r.s));

  // unauth
  ok((await call("GET", "/offers", null)).s === 401, "401 unauth");
  console.log(`\n${pass} geçti, ${fail} kaldı`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST CRASH", e); process.exit(2); });
