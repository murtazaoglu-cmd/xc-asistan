/**
 * Facts bağlamı + kapsam (rol) SQL parçaları.
 *
 * "Görüntüleyen" (viewer) = {id, role, name}. İki tür bağlam:
 *   userCtx(user)            → bir kullanıcının kendi görünümü (brifing/kapanış)
 *   scopeCtx(orgId, scopeKey)→ insight motoru: 'business' (admin+muhasebe işletme defteri) | 'user:<id>' (ortak: yalnız kendi verisi)
 *
 * Kapsam kuralları (mevcut API ile aynı):
 *   - admin/muhasebe: operasyonel listeler (randevu, yeni teklif…) HEPSİ; PARA/hunisi ise "işletme" verisi
 *     (sahibi boş ya da admin/muhasebe olan kayıtlar; ortakların ayrı firma verisi KARIŞMAZ). Defter = financeOwnerId (muhasebe → ilk admin).
 *   - ortak: yalnız kendi (owner_id = ortak) kayıtları ve kendi defteri
 *   - personel: kendi/paylaşılan kayıtlar; FİNANS YOK (mobil ana ekranla aynı)
 *   - saha: yalnız kendine atanan/paylaşılan işler; FİNANS YOK
 * Gün sınırları İstanbul takvim gününe göre; asla `now()` SQL'de kullanılmaz (sahte saat uyumu için hep parametre).
 */
const db = require("../../db");
const clock = require("../clock");
const { orgIdForUser } = require("../org");
const { financeOwnerId, firstAdminId } = require("../../middleware/access");

const GLOBAL = ["admin", "muhasebe"];

function dayBounds(dateStr, tz = clock.IST) {
  const start = clock.zonedToUtc(dateStr, "00:00", tz);
  const end = clock.zonedToUtc(clock.addDays(dateStr, 1), "00:00", tz);
  return { start, end };
}

/** viewer: {id, role, name?}; opts: {date: 'YYYY-MM-DD' (varsayılan bugün, İstanbul), orgId} */
async function userCtx(viewer, opts = {}) {
  const orgId = opts.orgId || (await orgIdForUser(viewer.id));
  const date = opts.date || clock.istanbulDateStr();
  const { start, end } = dayBounds(date);
  const role = viewer.role;
  const isGlobal = GLOBAL.includes(role);
  const canFinance = isGlobal || role === "ortak";
  return {
    orgId, date, dayStart: start, dayEnd: end, tz: clock.IST, now: clock.now(),
    viewer: { id: viewer.id, role, name: viewer.name || null },
    userId: viewer.id, role, isGlobal, canFinance, isField: role === "saha", isPersonel: role === "personel", isOrtak: role === "ortak",
    ledgerOwnerId: canFinance ? await financeOwnerId({ id: viewer.id, role }) : null,
    scopeKey: role === "ortak" ? `user:${viewer.id}` : isGlobal ? "business" : `user:${viewer.id}`,
  };
}

/** İnsight motoru için kapsam bağlamı */
async function scopeCtx(orgId, scopeKey, opts = {}) {
  if (scopeKey === "business") {
    const admin = await firstAdminId();
    return userCtx({ id: admin, role: "admin", name: null }, { ...opts, orgId });
  }
  const m = /^user:([0-9a-f-]{36})$/.exec(scopeKey);
  if (!m) throw new Error("Geçersiz kapsam anahtarı: " + scopeKey);
  return userCtx({ id: m[1], role: "ortak", name: null }, { ...opts, orgId });
}

/** Parametre listesi yardımcısı: p.add(v) → "$n" */
function params(initial = []) {
  const arr = [...initial];
  return { arr, add(v) { arr.push(v); return `$${arr.length}`; } };
}

const BIZ = (a) => `(${a}.owner_id IS NULL OR ${a}.owner_id IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')))`;

/**
 * Bir tablo takma adı için sahiplik koşulu ("AND" ile eklenir; boş olabilir).
 *   mode 'ops': mevcut API kapsamı (admin/muhasebe hepsi; diğerleri kendi + paylaşılan)
 *   mode 'biz': para/huni: admin/muhasebe → işletme sahipli; ortak/personel → YALNIZ kendi
 * resourceType: 'offer' | 'project' (paylaşım tablosu için)
 */
function ownerClause(ctx, alias, resourceType, p, mode = "ops") {
  if (ctx.isGlobal) return mode === "biz" ? ` AND ${BIZ(alias)}` : "";
  const u = p.add(ctx.userId);
  if (mode === "biz") return ` AND ${alias}.owner_id = ${u}`;
  return ` AND (${alias}.owner_id = ${u} OR ${alias}.id IN (SELECT resource_id FROM resource_shares WHERE resource_type = '${resourceType}' AND shared_with_user_id = ${u}))`;
}
const orgClause = (alias, p, orgId) => ` AND ${alias}.org_id = ${p.add(orgId)}`;

/**
 * Randevu kapsamı: admin/muhasebe hepsi · ortak: kendi oluşturduğu/atanan/kendi teklif-projesine bağlı ·
 * personel/saha: YALNIZ kendine atanan ya da kendi oluşturduğu ("kendi işleri").
 * (appointmentQueries.APPT_SELECT takma adları: a, o, p)
 */
function apptClause(ctx, p, mode = "ops") {
  if (ctx.isGlobal) return mode === "biz" ? ` AND (a.owner_id IS NULL OR a.owner_id IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')) OR a.assigned_user_id IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')))` : "";
  const u = p.add(ctx.userId);
  if (ctx.isField || ctx.isPersonel) return ` AND (a.assigned_user_id = ${u} OR a.owner_id = ${u})`;
  return ` AND (a.owner_id = ${u} OR a.assigned_user_id = ${u}
      OR o.owner_id = ${u} OR o.id IN (SELECT resource_id FROM resource_shares WHERE resource_type='offer' AND shared_with_user_id = ${u})
      OR p.owner_id = ${u} OR p.id IN (SELECT resource_id FROM resource_shares WHERE resource_type='project' AND shared_with_user_id = ${u}))`;
}

/** Randevu durumu sınıflaması (panel serbest metin kullanır: beklemede/onaylandı/tamamlandı/iptal, eski planlandi/tamamlandi) */
function apptState(status) {
  const s = String(status || "").toLocaleLowerCase("tr-TR");
  if (s.startsWith("iptal")) return "iptal";
  if (s.startsWith("tamamlan") || s === "yapıldı" || s === "yapildi") return "tamamlandi";
  if (s.startsWith("ertelen")) return "ertelendi";
  return "acik";
}

module.exports = { userCtx, scopeCtx, dayBounds, params, ownerClause, orgClause, apptClause, apptState, BIZ, GLOBAL };
