/**
 * Yazma niyetleri için "taslak (draft) → doğrulanmış kart" üreticileri. Aynı fonksiyonlar önerirken, düzenlerken ve onaylarken çalışır:
 * onay anında veri yeniden okunur/doğrulanır (bayat öneri güvenli olmaz).
 * build() sonucu:
 *   {clarify:{message, questions[]}}                    → eksik/belirsiz zorunlu alan (kart oluşmaz)
 *   {noop:"mesaj"}                                      → yapılacak bir şey yok
 *   {error:{status,message}}                            → yetki/iş kuralı engeli
 *   {draft, summary, fields[], ambiguities[], warnings[], request}  → kart
 * request: onayda çalışacak işlem: {kind:"rest", method, path, body} | {kind:"note", ...}  (jeton/gizli alan içermez)
 */
const db = require("../../db");
const { listAppointments } = require("../../services/appointmentQueries");
const { scopeClause } = require("../../middleware/ownership");
const { tail10, poolEntry, customerPool } = require("./scope");
const { fmtDate, fmtAt, istParts, kurus } = require("./render");
const { addDays, splitYmd, daysInMonth } = require("./datetime");
const { parseNumericString } = require("./numbers");
const { customerProjects } = require("./reads");
const { fold, tidy } = require("./text");

const OFFER_STATUSES = ["Yeni", "İncelendi", "Keşif Planlandı", "Teklif Verildi", "Kabul Edildi", "Reddedildi"];
const METHODS = ["Havale", "Nakit", "Kredi Kartı"];
const SCOPES = { ev: "Ev (kişisel)", dukkan: "Dükkan", genel: "Genel işletme" };
const MAX_KURUS = 99999999999; // < 1 milyar TL (NUMERIC(12,2) sınırının çok altı)
const TYPE_HINTS = { kesif: /ke[sş]if|ziyaret|ekspertiz|[öo]l[çc][üu]/i, montaj: /montaj|kurulum|y[üu]kleme/i, teslim: /teslim/i, servis: /bak[ıi]m|servis|onar[ıi]m/i, gorusme: /g[öo]r[üu][sş]me|toplant[ıi]|randevu|dan[ıi][sş]ma|diğer|diger/i };
const TYPE_DEFAULT = { kesif: "Keşif", montaj: "Montaj", teslim: "Teslim", servis: "Bakım", gorusme: "Görüşme" };

const isYmd = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && (() => { const { y, m, d } = splitYmd(s); return y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m); })();
const isHm = (s) => typeof s === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);
const cleanText = (s, max) => tidy(String(s == null ? "" : s)).slice(0, max);
const atIso = (date, time) => `${date}T${time}:00+03:00`;
const nowYmd = (ctx) => ctx.today;

/** TL değeri (sayı ya da "12.500,50" metni) → kuruş tamsayısı; geçersizse null */
function toKurusSafe(v) {
  let n = null;
  if (typeof v === "number") n = v;
  else if (typeof v === "string") n = parseNumericString(v.trim().replace(/\s|TL|₺/gi, ""));
  if (n === null || !Number.isFinite(n)) return null;
  const k = Math.round(n * 100);
  return k > 0 && k <= MAX_KURUS ? k : null;
}
const tlOf = (k) => k / 100;

function typeLabel(cfg, key) {
  const list = (cfg.lists && cfg.lists.appointment_types) || [];
  if (!key) return list[0] || "Randevu";
  if (TYPE_HINTS[key]) { const hit = list.find((t) => TYPE_HINTS[key].test(t)); if (hit) return hit; }
  return TYPE_DEFAULT[key] || key;
}
function categoryLabel(cfg, cat) {
  const list = (cfg.lists && cfg.lists.expense_categories) || [];
  const f = fold(cat);
  const hit = list.find((c) => fold(c) === f) || list.find((c) => fold(c).includes(f) || f.includes(fold(c)));
  return hit || cat;
}

const customerQuestion = (cands, message) => ({
  clarify: { message, questions: [{ field: "customer_key", type: "choice", label: "Hangi müşteri?", options: cands.map((c) => ({ value: c.key, label: `${c.name}${c.phone ? " · " + c.phone : ""}` })) }] },
});

/** draft.customer_key → havuz kaydı. {entry} | {clarify} (belirtilmiş ama bulunamadıysa) | {entry:null} (belirtilmemiş) */
async function loadCustomer(ctx, draft, { required, label = "müşteri" }) {
  if (draft.customer_key) {
    const e = await poolEntry(ctx.user, draft.customer_key);
    if (!e) return { clarify: { message: "Bu müşteri kaydına erişiminiz yok ya da bulunamadı.", questions: [{ field: "customer_key", type: "choice", label: "Hangi müşteri?", options: [] }] } };
    return { entry: e };
  }
  if (draft.customer_options && draft.customer_options.length) return customerQuestion(draft.customer_options, "Birden fazla müşteri eşleşti, hangisi?");
  if (draft.customer_query) return { clarify: { message: `“${cleanText(draft.customer_query, 60)}” adlı bir ${label} bulamadım.`, reason: "not_found", questions: [{ field: "customer_key", type: "choice", label: "Hangi müşteri?", options: [] }] } };
  if (required) return { clarify: { message: `Hangi ${label}?`, reason: "missing", questions: [{ field: "customer_key", type: "choice", label: "Hangi müşteri?", options: [] }] } };
  return { entry: null };
}

// ---------- randevu araçları ----------
const apptLabel = (a, today) => `${fmtAt(a.scheduled_at, today)} · ${a.customer_name || "—"} · ${a.type}`;
async function findAppointments(ctx, { customerKey, targetDate }) {
  const where = [`COALESCE(a.status,'') NOT ILIKE 'iptal%'`, `COALESCE(a.status,'') NOT ILIKE 'tamam%'`, `a.scheduled_at >= $1::date`];
  const params = [ctx.today];
  if (targetDate) { params.push(targetDate); where.push(`a.scheduled_at >= $2::date AND a.scheduled_at < ($2::date + 1)`); }
  let rows = await listAppointments(ctx.user, { extraWhere: where, extraParams: params, limit: 200 });
  if (customerKey) rows = rows.filter((a) => tail10(a.customer_phone) === customerKey || tail10(a.offer_phone) === customerKey);
  return rows;
}
async function pickAppointment(ctx, draft, customerKey) {
  if (draft.appointment_id) {
    const rows = await listAppointments(ctx.user, { extraWhere: ["a.id = $1::uuid"], extraParams: [String(draft.appointment_id)], limit: 1 }).catch(() => []);
    if (!rows[0]) return { error: { status: 404, message: "Randevu bulunamadı ya da erişiminiz yok." } };
    return { appt: rows[0] };
  }
  const rows = await findAppointments(ctx, { customerKey, targetDate: draft.target_date });
  if (rows.length === 1) return { appt: rows[0] };
  if (rows.length === 0) return { clarify: { message: customerKey ? "Bu müşteri için ileri tarihli açık randevu bulamadım." : "Eşleşen açık randevu bulamadım.", reason: "not_found", questions: [] } };
  return { clarify: { message: "Birden fazla randevu var, hangisi?", reason: "ambiguous", questions: [{ field: "appointment_id", type: "choice", label: "Hangi randevu?", options: rows.slice(0, 8).map((a) => ({ value: a.id, label: apptLabel(a, ctx.today) })) }] } };
}

// ---------- proje çözümleme (ödeme/gider) ----------
async function pickProject(ctx, draft, cust, { required }) {
  if (draft.project_id) {
    const sc = scopeClause(ctx.user, "p", "project", 2);
    const { rows } = await db.query(`SELECT p.id, p.code, p.service, p.customer_name, (p.total_amount*100)::bigint AS total_kurus FROM projects p WHERE p.id = $1::uuid ${sc.clause}`, [String(draft.project_id), ...sc.params]).catch(() => ({ rows: [] }));
    if (!rows[0]) return { error: { status: 404, message: "Proje bulunamadı ya da erişiminiz yok." } };
    return { project: rows[0] };
  }
  let list = [];
  if (cust) list = await customerProjects(ctx.user, cust);
  if (draft.project_ref) {
    const ref = String(draft.project_ref).toUpperCase();
    let byRef = list.filter((p) => String(p.code).toUpperCase() === ref);
    if (!byRef.length) {
      const sc = scopeClause(ctx.user, "p", "project", 2);
      const q = await db.query(`SELECT p.id, p.code, p.service, p.customer_name, (p.total_amount*100)::bigint AS total_kurus FROM projects p WHERE upper(p.code) = $1 ${sc.clause}`, [ref, ...sc.params]);
      byRef = q.rows;
    }
    if (byRef.length === 1) return { project: byRef[0] };
    if (!byRef.length) return { clarify: { message: `“${cleanText(draft.project_ref, 30)}” kodlu bir proje bulamadım.`, reason: "not_found", questions: [] } };
  }
  if (list.length === 1) return { project: list[0] };
  if (list.length > 1) {
    return { clarify: { message: "Birden fazla proje var, hangisi?", reason: "ambiguous", questions: [{ field: "project_id", type: "choice", label: "Hangi proje?", options: list.slice(0, 8).map((p) => ({ value: p.id, label: `${p.code} · ${p.service} · kalan ${kurus(Math.max(Number(p.total_kurus) - Number(p.paid_kurus || 0), 0))}` })) }] } };
  }
  if (required) return { clarify: { message: cust ? `${cust.name} için kayıtlı proje bulamadım; ödeme bir projeye bağlı olmalı.` : "Hangi projeye?", reason: cust ? "not_found" : "missing", questions: [] } };
  return { project: null };
}

const fld = (key, label, type, value, display, extra = {}) => ({ key, label, type, value, display: display == null ? "" : String(display), editable: extra.editable !== false, required: !!extra.required, ...(extra.options ? { options: extra.options } : {}) });

// =====================================================================================================
const BUILDERS = {
  // ---- randevu ekle
  async "appointment.create"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: true });
    if (c.clarify) return c;
    const qs = [];
    if (!isYmd(d.date)) qs.push({ field: "date", type: "date", label: "Hangi gün?" });
    if (!isHm(d.time)) qs.push({ field: "time", type: "time", label: "Saat kaçta?" });
    if (qs.length) return { clarify: { message: qs.length === 2 ? "Randevu tarihi ve saati gerekli." : (qs[0].field === "date" ? "Hangi gün?" : "Saat kaçta?"), reason: "missing", questions: qs } };
    const amb = [];
    const type = cleanText(d.type, 40) || typeLabel(ctx.cfg, null);
    if (!d.type) amb.push({ field: "type", kind: "assumed", value: type });
    const at = atIso(d.date, d.time);
    const warnings = [];
    if (new Date(at) < ctx.now) warnings.push("Seçilen zaman geçmişte.");
    const near = await listAppointments(ctx.user, { extraWhere: [`a.scheduled_at > $1::timestamptz - interval '30 minutes'`, `a.scheduled_at < $1::timestamptz + interval '30 minutes'`, `COALESCE(a.status,'') NOT ILIKE 'iptal%'`], extraParams: [at], limit: 3 });
    if (near.length) warnings.push(`Aynı saate yakın başka randevu var (${near[0].customer_name || "—"}).`);
    const draft = { customer_key: c.entry.key, date: d.date, time: d.time, type, ...(d.notes ? { notes: cleanText(d.notes, 500) } : {}) };
    const t = ctx.terms.appointment || "Randevu";
    return {
      draft, ambiguities: amb, warnings,
      summary: `${t}: ${c.entry.name} · ${fmtAt(at, ctx.today)} · ${type}`,
      fields: [
        fld("customer_key", "Müşteri", "customer", c.entry.key, c.entry.name),
        fld("date", "Gün", "date", d.date, fmtDate(d.date, ctx.today), { required: true }),
        fld("time", "Saat", "time", d.time, d.time, { required: true }),
        fld("type", "Tür", "choice", type, type, { options: ((ctx.cfg.lists && ctx.cfg.lists.appointment_types) || []).map((x) => ({ value: x, label: x })) }),
        fld("notes", "Not", "text", draft.notes || "", draft.notes || ""),
      ],
      request: { kind: "rest", method: "POST", path: "/appointments", body: { type, scheduled_at: at, notes: draft.notes || null, customer_name: c.entry.name, customer_phone: c.entry.phone || null, ...(c.entry.address ? { address: String(c.entry.address).slice(0, 500) } : {}) } },
    };
  },

  // ---- randevu ertele
  async "appointment.reschedule"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const pk = await pickAppointment(ctx, d, c.entry && c.entry.key);
    if (pk.error || pk.clarify) return pk;
    const a = pk.appt, cur = istParts(a.scheduled_at);
    let nd = null, nt = null;
    if (Number.isInteger(d.shift_days) && d.shift_days !== 0) { nd = addDays(cur.date, d.shift_days); nt = isHm(d.new_time) ? d.new_time : cur.time; }
    else {
      nd = isYmd(d.new_date) ? d.new_date : (isHm(d.new_time) ? cur.date : null);
      nt = isHm(d.new_time) ? d.new_time : cur.time;
    }
    if (!nd) return { clarify: { message: "Yeni tarih ya da saat nedir?", reason: "missing", questions: [{ field: "new_date", type: "date", label: "Yeni gün?" }, { field: "new_time", type: "time", label: "Yeni saat?" }] } };
    const newAt = atIso(nd, nt);
    if (new Date(newAt).getTime() === new Date(a.scheduled_at).getTime()) return { noop: "Randevu zaten bu zamanda." };
    const warnings = [];
    if (new Date(newAt) < ctx.now) warnings.push("Yeni zaman geçmişte.");
    const draft = { appointment_id: a.id, new_date: nd, new_time: nt };
    return {
      draft, ambiguities: [], warnings, meta: { old_at: new Date(a.scheduled_at).toISOString() },
      summary: `${ctx.terms.appointment || "Randevu"} ertelenecek: ${a.customer_name || "—"} · ${fmtAt(a.scheduled_at, ctx.today)} → ${fmtAt(newAt, ctx.today)}`,
      fields: [
        fld("appointment_id", "Randevu", "appointment", a.id, apptLabel(a, ctx.today), { editable: false }),
        fld("new_date", "Yeni gün", "date", nd, fmtDate(nd, ctx.today), { required: true }),
        fld("new_time", "Yeni saat", "time", nt, nt, { required: true }),
      ],
      request: { kind: "rest", method: "PATCH", path: `/appointments/${a.id}`, body: { scheduled_at: newAt } },
    };
  },

  // ---- randevu iptal
  async "appointment.cancel"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const pk = await pickAppointment(ctx, d, c.entry && c.entry.key);
    if (pk.error || pk.clarify) return pk;
    const a = pk.appt;
    return {
      draft: { appointment_id: a.id }, ambiguities: [], warnings: [], meta: { old_status: a.status || null },
      summary: `${ctx.terms.appointment || "Randevu"} iptal edilecek: ${a.customer_name || "—"} · ${fmtAt(a.scheduled_at, ctx.today)} · ${a.type}`,
      fields: [fld("appointment_id", "Randevu", "appointment", a.id, apptLabel(a, ctx.today), { editable: false })],
      request: { kind: "rest", method: "PATCH", path: `/appointments/${a.id}`, body: { status: "iptal" } },
    };
  },

  // ---- hatırlatma
  async "reminder.create"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const title = cleanText(d.title, 200);
    const qs = [];
    if (!title) qs.push({ field: "title", type: "text", label: "Ne hatırlatılsın?" });
    if (!isYmd(d.date)) qs.push({ field: "date", type: "date", label: "Hangi gün?" });
    if (qs.length) return { clarify: { message: !title ? "Ne hatırlatılsın?" : "Ne zaman hatırlatılsın?", reason: "missing", questions: qs } };
    const time = isHm(d.time) ? d.time : "09:00";
    const at = atIso(d.date, time);
    const warnings = [];
    if (new Date(at) < ctx.now) warnings.push("Seçilen zaman geçmişte; hatırlatma hemen görünür.");
    const note = c.entry ? `Müşteri: ${c.entry.name}${c.entry.phone ? " (" + c.entry.phone + ")" : ""}` : null;
    return {
      draft: { title, date: d.date, time, ...(c.entry ? { customer_key: c.entry.key } : {}) },
      ambiguities: isHm(d.time) ? [] : [{ field: "time", kind: "default", value: "09:00" }], warnings,
      summary: `Hatırlatma: ${title} · ${fmtAt(at, ctx.today)}`,
      fields: [
        fld("title", "Hatırlatma", "text", title, title, { required: true }),
        fld("date", "Gün", "date", d.date, fmtDate(d.date, ctx.today), { required: true }),
        fld("time", "Saat", "time", time, time, { required: true }),
        ...(c.entry ? [fld("customer_key", "Müşteri", "customer", c.entry.key, c.entry.name, { editable: false })] : []),
      ],
      request: { kind: "rest", method: "POST", path: "/reminders", body: { title, remind_at: at, note } },
    };
  },

  // ---- ödeme (tahsilat)
  async "payment.add"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const k = Number.isInteger(d.amount_kurus) ? d.amount_kurus : toKurusSafe(d.amount);
    if (!k || k <= 0 || k > MAX_KURUS) return { clarify: { message: "Tutar nedir?", reason: "missing", questions: [{ field: "amount", type: "money", label: "Tutar (TL)?" }] } };
    if (!c.entry && !d.project_id && !d.project_ref) return { clarify: { message: "Ödeme hangi müşteriden/projeden?", reason: "missing", questions: [{ field: "customer_key", type: "choice", label: "Hangi müşteri?", options: [] }] } };
    const method = METHODS.includes(d.method) ? d.method : "Nakit";
    const pr = await pickProject(ctx, d, c.entry, { required: true });
    if (pr.error || pr.clarify) return pr;
    const p = pr.project;
    const paid = await db.query("SELECT COALESCE(SUM((amount*100)::bigint),0)::bigint AS k FROM payments WHERE project_id = $1 AND owner_id = $2", [p.id, ctx.ledgerOwner]);
    const remaining = Number(p.total_kurus) - Number(paid.rows[0].k);
    const warnings = [];
    if (k > remaining) warnings.push(`Tutar projenin kalan bakiyesinden (${kurus(Math.max(remaining, 0))}) büyük.`);
    const date = isYmd(d.date) ? d.date : null;
    const draft = { amount_kurus: k, method, project_id: p.id, ...(c.entry ? { customer_key: c.entry.key } : {}), ...(date ? { date } : {}) };
    return {
      draft, warnings, ambiguities: METHODS.includes(d.method) ? [] : [{ field: "method", kind: "default", value: "Nakit", options: METHODS }], meta: { remaining_before_kurus: remaining },
      summary: `${ctx.terms.payment || "Tahsilat"}: ${kurus(k)} · ${c.entry ? c.entry.name : p.customer_name} · ${p.code} · ${method}`,
      fields: [
        fld("amount", "Tutar (TL)", "money", tlOf(k), kurus(k), { required: true }),
        fld("method", "Yöntem", "choice", method, method, { options: METHODS.map((x) => ({ value: x, label: x })) }),
        fld("project_id", "Proje", "project", p.id, `${p.code} · ${p.service}`),
        fld("date", "Tarih", "date", date, date ? fmtDate(date, ctx.today) : "Bugün"),
      ],
      request: { kind: "rest", method: "POST", path: `/projects/${p.id}/payments`, body: { amount: tlOf(k), method, note: "Komut çubuğu", ...(date ? { paid_at: atIso(date, "12:00") } : {}) } },
    };
  },

  // ---- gider
  async "expense.add"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const k = Number.isInteger(d.amount_kurus) ? d.amount_kurus : toKurusSafe(d.amount);
    if (!k || k <= 0 || k > MAX_KURUS) return { clarify: { message: "Tutar nedir?", reason: "missing", questions: [{ field: "amount", type: "money", label: "Tutar (TL)?" }] } };
    const category = categoryLabel(ctx.cfg, cleanText(d.category, 60));
    if (!category) return { clarify: { message: "Gider kategorisi nedir?", reason: "missing", questions: [{ field: "category", type: "text", label: "Kategori?" }] } };
    const scope = SCOPES[d.scope] ? d.scope : "genel";
    let project = null;
    if (c.entry || d.project_id || d.project_ref) {
      const pr = await pickProject(ctx, d, c.entry, { required: !!(d.project_id || d.project_ref) });
      if (pr.error || pr.clarify) return pr;
      project = pr.project;
    }
    if (!project && ctx.user.role === "personel") return { error: { status: 403, message: "Genel işletme gideri sadece yönetici/muhasebe tarafından girilebilir; bir projeye bağlayın." } };
    const date = isYmd(d.date) ? d.date : null;
    const draft = { amount_kurus: k, category, scope, ...(project ? { project_id: project.id } : {}), ...(c.entry ? { customer_key: c.entry.key } : {}), ...(date ? { date } : {}) };
    return {
      draft, warnings: [], ambiguities: [],
      summary: `${ctx.terms.expense || "Gider"}: ${kurus(k)} · ${category}${project ? " · " + project.code : ""} · ${SCOPES[scope]}`,
      fields: [
        fld("amount", "Tutar (TL)", "money", tlOf(k), kurus(k), { required: true }),
        fld("category", "Kategori", "choice", category, category, { options: ((ctx.cfg.lists && ctx.cfg.lists.expense_categories) || []).map((x) => ({ value: x, label: x })) }),
        fld("scope", "Kapsam", "choice", scope, SCOPES[scope], { options: Object.entries(SCOPES).map(([v, l]) => ({ value: v, label: l })) }),
        fld("project_id", "Proje", "project", project ? project.id : null, project ? `${project.code} · ${project.service}` : "—", { editable: !!project }),
        fld("date", "Tarih", "date", date, date ? fmtDate(date, ctx.today) : "Bugün"),
      ],
      request: { kind: "rest", method: "POST", path: "/expenses", body: { category, amount: tlOf(k), scope, project_id: project ? project.id : undefined, ...(date ? { expense_date: atIso(date, "12:00") } : {}), note: "Komut çubuğu" } },
    };
  },

  // ---- teklif durumu
  async "offer.status"(ctx, d) {
    const status = d.status;
    if (!OFFER_STATUSES.includes(status)) return { clarify: { message: "Teklif hangi duruma alınsın?", reason: "missing", questions: [{ field: "status", type: "choice", label: "Durum?", options: OFFER_STATUSES.map((s) => ({ value: s, label: s })) }] } };
    const sc = scopeClause(ctx.user, "o", "offer", 2);
    let offer = null;
    if (d.offer_id) {
      const { rows } = await db.query(`SELECT o.id, o.code, o.name, o.status, o.service FROM offers o WHERE o.id = $1::uuid ${sc.clause}`, [String(d.offer_id), ...sc.params]).catch(() => ({ rows: [] }));
      offer = rows[0];
      if (!offer) return { error: { status: 404, message: "Teklif bulunamadı ya da erişiminiz yok." } };
    } else {
      const c = await loadCustomer(ctx, d, { required: false });
      if (c.clarify) return c;
      if (d.offer_ref) {
        const { rows } = await db.query(`SELECT o.id, o.code, o.name, o.status, o.service FROM offers o WHERE upper(o.code) = $1 ${sc.clause}`, [String(d.offer_ref).toUpperCase(), ...sc.params]);
        offer = rows[0];
        if (!offer) return { clarify: { message: `“${cleanText(d.offer_ref, 30)}” kodlu bir teklif bulamadım.`, reason: "not_found", questions: [] } };
      } else if (c.entry) {
        const { rows } = await db.query(`SELECT o.id, o.code, o.name, o.status, o.service, o.created_at FROM offers o WHERE right(regexp_replace(o.phone,'[^0-9]','','g'),10) = $1 ${sc.clause} ORDER BY o.created_at DESC LIMIT 8`, [c.entry.key, ...sc.params]);
        if (!rows.length) return { clarify: { message: `${c.entry.name} için teklif bulamadım.`, reason: "not_found", questions: [] } };
        if (rows.length === 1) offer = rows[0];
        else return { clarify: { message: "Birden fazla teklif var, hangisi?", reason: "ambiguous", questions: [{ field: "offer_id", type: "choice", label: "Hangi teklif?", options: rows.map((o) => ({ value: o.id, label: `${o.code} · ${o.service || ""} · ${o.status}` })) }] } };
      } else return { clarify: { message: "Hangi teklif? (kod ya da müşteri adı)", reason: "missing", questions: [{ field: "offer_id", type: "choice", label: "Hangi teklif?", options: [] }] } };
    }
    if (offer.status === status) return { noop: `${offer.code} zaten “${status}” durumunda.` };
    if (offer.status === "Kabul Edildi" && status !== "Kabul Edildi" && ctx.user.role !== "admin") return { error: { status: 409, message: "Kabul edilmiş teklifin durumu değiştirilemez (yalnızca yönetici düzeltebilir)." } };
    const warnings = [];
    if (status === "Kabul Edildi") warnings.push("Kabul edilince proje otomatik oluşturulur; bu işlem komuttan geri alınamaz.");
    return {
      draft: { offer_id: offer.id, status }, warnings, ambiguities: [], meta: { old_status: offer.status, undoable: status !== "Kabul Edildi" },
      summary: `${ctx.terms.offer || "Teklif"}: ${offer.code} · ${offer.name || ""} · ${offer.status} → ${status}`,
      fields: [
        fld("offer_id", "Teklif", "offer", offer.id, `${offer.code} · ${offer.name || ""}`, { editable: false }),
        fld("status", "Yeni durum", "choice", status, status, { options: OFFER_STATUSES.map((s) => ({ value: s, label: s })) }),
      ],
      request: { kind: "rest", method: "PATCH", path: `/offers/${offer.id}/status`, body: { status } },
    };
  },

  // ---- not
  async "note.add"(ctx, d) {
    const c = await loadCustomer(ctx, d, { required: false });
    if (c.clarify) return c;
    const text = cleanText(d.text, 2000);
    if (!text) return { clarify: { message: "Not metni nedir?", reason: "missing", questions: [{ field: "text", type: "text", label: "Not?" }] } };
    return {
      draft: { text, ...(c.entry ? { customer_key: c.entry.key } : {}) }, warnings: [], ambiguities: [],
      summary: `Not${c.entry ? " · " + c.entry.name : ""}: ${text.length > 80 ? text.slice(0, 79) + "…" : text}`,
      fields: [fld("text", "Not", "text", text, text, { required: true }), ...(c.entry ? [fld("customer_key", "Müşteri", "customer", c.entry.key, c.entry.name, { editable: false })] : [])],
      request: { kind: "note", phone_key: c.entry ? c.entry.key : null, body: text },
    };
  },
};

/** Düzenlenebilir taslak alanları (PATCH /actions/:id ve clarify `choices`) — her niyet için beyaz liste */
const EDITABLE = {
  "appointment.create": ["customer_key", "date", "time", "type", "notes"],
  "appointment.reschedule": ["appointment_id", "customer_key", "new_date", "new_time", "target_date"],
  "appointment.cancel": ["appointment_id", "customer_key", "target_date"],
  "reminder.create": ["title", "date", "time", "customer_key"],
  "payment.add": ["customer_key", "project_id", "amount", "method", "date"],
  "expense.add": ["customer_key", "project_id", "amount", "category", "scope", "date"],
  "offer.status": ["offer_id", "customer_key", "status"],
  "note.add": ["text", "customer_key"],
};
const ALL_CHOICE_KEYS = [...new Set(Object.values(EDITABLE).flat())];

/** Alan değeri biçim doğrulaması (düzenleme/seçim); geçersizse hata metni döner */
function validateEdit(key, v) {
  if (v === null || v === undefined) return null;
  switch (key) {
    case "date": case "new_date": case "target_date": return v === "" || isYmd(v) ? null : "Geçersiz tarih (YYYY-AA-GG).";
    case "time": case "new_time": return v === "" || isHm(v) ? null : "Geçersiz saat (SS:DD).";
    case "amount": return toKurusSafe(v) ? null : "Geçersiz tutar.";
    case "method": return METHODS.includes(v) ? null : "Geçersiz ödeme yöntemi.";
    case "scope": return SCOPES[v] ? null : "Geçersiz kapsam.";
    case "status": return OFFER_STATUSES.includes(v) ? null : "Geçersiz teklif durumu.";
    case "appointment_id": case "project_id": case "offer_id": return typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v) ? null : "Geçersiz kimlik.";
    case "customer_key": return typeof v === "string" && /^\d{7,10}$/.test(v) ? null : "Geçersiz müşteri anahtarı.";
    case "title": case "text": case "notes": case "category": case "type": return typeof v === "string" && v.length <= 2000 ? null : "Geçersiz metin.";
    default: return "Bilinmeyen alan.";
  }
}

module.exports = { BUILDERS, EDITABLE, ALL_CHOICE_KEYS, validateEdit, typeLabel, categoryLabel, toKurusSafe, isYmd, isHm, OFFER_STATUSES, METHODS, MAX_KURUS };
