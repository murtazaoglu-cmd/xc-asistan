/**
 * Müdür motoru: kural kataloğunu bir KAPSAM için (business | user:<ortak>) çalıştırır, insight'ları dedupe ederek yazar.
 * Müdür HİÇBİR ŞEY YAPMAZ: öneri + dayanak + aksiyon metadatası üretir; uygulamayı kullanıcı (uygulama uçları) yapar.
 *
 * Yaşam döngüsü (status): acik → ertelendi (süre bitince açılır) · kapatildi (kullanıcı: 14 gün susturma; koşul kalkınca otomatik)
 *                          · uygulandi (7 gün susturma). Koşul geri dönerse ya da susturma bitince yeniden açılır.
 * Dedupe: UNIQUE (org_id, scope_key, fingerprint); fingerprint = kural + varlık. Aynı insight tekrar tekrar yaratılmaz.
 * Kalibrasyon modu (insight_rule_config '*' → calibration=1): kritikler 'warn'a indirilir (ilk 30 gün önerisi).
 */
const db = require("../../db");
const clock = require("../clock");
const facts = require("../facts");
const { loadTerms } = require("../text/terms");
const catalog = require("./catalog");
const templates = require("./templates");
const { SEV_RANK } = require("./rules/_util");

const DISMISS_DAYS = 14, APPLIED_DAYS = 7, WRONG_DAYS = 30, FRESH_MS = 30 * 60 * 1000;
const dayMs = 86400000;

function scopeKeyForUser(user) {
  if (user.role === "admin" || user.role === "muhasebe") return "business";
  if (user.role === "ortak") return `user:${user.id}`;
  return null;
}

async function loadConfig(orgId) {
  const { rows } = await db.query("SELECT rule_key, enabled, params FROM insight_rule_config WHERE org_id = $1", [orgId]);
  return new Map(rows.map((r) => [r.rule_key, r]));
}
const effParams = (rule, cfg) => ({ ...rule.defaultParams, ...((cfg && cfg.params) || {}) });

async function allScopes(orgId) {
  const { rows } = await db.query("SELECT id FROM users WHERE role = 'ortak' AND org_id = $1", [orgId]);
  return ["business", ...rows.map((r) => `user:${r.id}`)];
}

/**
 * Bir kapsam için tüm kuralları çalıştırır ve insight tablosunu günceller.
 * → {scope, date, rules:{M1:{status:'ok'|'devre_disi'|'bagimli'|'hata'|'kapsam_disi', count, ...}}, created, updated, reopened, closed}
 */
async function refresh(orgId, scopeKey, opts = {}) {
  const now = opts.now || clock.now();
  const date = opts.date || clock.istanbulDateStr(now);
  const ctx = await facts.context.scopeCtx(orgId, scopeKey, { date });
  const T = await loadTerms(orgId);
  const cfg = await loadConfig(orgId);
  const calibration = !!(cfg.get("*") && cfg.get("*").params && cfg.get("*").params.calibration);
  const env = { date, tz: ctx.tz };
  const summary = { scope: scopeKey, date, rules: {}, created: 0, updated: 0, reopened: 0, closed: 0 };
  const evaluated = []; // başarıyla değerlendirilen kurallar (aday kümesi güvenilir)
  const disabled = [];
  const cands = [];

  for (const rule of catalog.RULES) {
    const row = cfg.get(rule.key);
    if (row && row.enabled === false) { summary.rules[rule.key] = { status: "devre_disi" }; disabled.push(rule.key); continue; }
    if (rule.scopes && !rule.scopes.includes(scopeKey === "business" ? "business" : "user")) { summary.rules[rule.key] = { status: "kapsam_disi" }; continue; }
    const dep = await catalog.dependencyState(rule);
    if (!dep.available) { summary.rules[rule.key] = { status: "bagimli", missing: dep.missing }; continue; }
    try {
      const params = effParams(rule, row);
      const input = await rule.collect(ctx, params, facts);
      const out = rule.evaluate(input, params, ctx) || [];
      evaluated.push(rule.key);
      summary.rules[rule.key] = { status: "ok", count: out.length };
      for (const c of out) {
        if (calibration && c.severity === "critical") c.severity = "warn";
        cands.push(c);
      }
    } catch (err) {
      summary.rules[rule.key] = { status: "hata", error: String(err.message || err).slice(0, 200) };
      console.error(`[manager] ${rule.key} (${scopeKey}) hatası:`, err.message);
    }
  }

  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`insights:${orgId}:${scopeKey}`]);
    const keysTouched = [...evaluated, ...disabled];
    const { rows: existing } = keysTouched.length
      ? await client.query("SELECT * FROM insights WHERE org_id = $1 AND scope_key = $2 AND rule_key = ANY($3)", [orgId, scopeKey, keysTouched])
      : { rows: [] };
    const byFp = new Map(existing.map((e) => [e.fingerprint, e]));
    const seen = new Set();

    for (const c of cands) {
      seen.add(c.fingerprint);
      const r = templates.render(c, T, env);
      const e = byFp.get(c.fingerprint);
      const vals = [c.severity, r.title, r.body, JSON.stringify(r.evidence), JSON.stringify(r.actions), c.entity ? c.entity.type : null, c.entity ? c.entity.id : null, c.score];
      if (!e) {
        await client.query(
          `INSERT INTO insights (org_id, scope_key, rule_key, fingerprint, severity, title, body, evidence, actions, entity_type, entity_id, score, first_seen_at, last_seen_at, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13,$13)`, [orgId, scopeKey, c.rule, c.fingerprint, ...vals, now]);
        summary.created++;
        continue;
      }
      let reopen = false;
      if (e.status === "kapatildi" || e.status === "uygulandi") {
        const userClosed = e.closed_reason === "kullanici" || e.closed_reason === "uygulandi";
        reopen = !userClosed || !e.snoozed_until || new Date(e.snoozed_until) <= now;
        if (!reopen) { // susturulmuş: içeriği sessizce tazele (durum değişmez)
          await client.query("UPDATE insights SET last_seen_at = $2, updated_at = $2 WHERE id = $1", [e.id, now]);
          continue;
        }
      } else if (e.status === "ertelendi") {
        reopen = !e.snoozed_until || new Date(e.snoozed_until) <= now || SEV_RANK[c.severity] > SEV_RANK[e.severity];
      }
      if (reopen) {
        await client.query(
          `UPDATE insights SET status='acik', snoozed_until=NULL, closed_reason=NULL, closed_at=NULL, occurrences = occurrences + 1,
                  severity=$3, title=$4, body=$5, evidence=$6, actions=$7, entity_type=$8, entity_id=$9, score=$10, last_seen_at=$2, updated_at=$2 WHERE id = $1`, [e.id, now, ...vals]);
        summary.reopened++;
      } else {
        await client.query(
          `UPDATE insights SET severity=$3, title=$4, body=$5, evidence=$6, actions=$7, entity_type=$8, entity_id=$9, score=$10, last_seen_at=$2, updated_at=$2 WHERE id = $1`, [e.id, now, ...vals]);
        summary.updated++;
      }
    }
    // koşulu kalkanlar / kapatılmış kurallar
    for (const e of existing) {
      if (seen.has(e.fingerprint) || !["acik", "ertelendi"].includes(e.status)) continue;
      const reason = disabled.includes(e.rule_key) ? "kural_kapali" : "kosul_ortadan_kalkti";
      await client.query("UPDATE insights SET status='kapatildi', closed_reason=$2, closed_at=$3, snoozed_until=NULL, updated_at=$3 WHERE id=$1", [e.id, reason, now]);
      summary.closed++;
    }
    await client.query(
      `INSERT INTO insight_runs (org_id, scope_key, ran_at, summary) VALUES ($1,$2,$3,$4)
       ON CONFLICT (org_id, scope_key) DO UPDATE SET ran_at = EXCLUDED.ran_at, summary = EXCLUDED.summary`, [orgId, scopeKey, now, JSON.stringify(summary)]);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  return summary;
}

async function refreshAll(orgId, opts = {}) {
  const out = [];
  for (const s of await allScopes(orgId)) out.push(await refresh(orgId, s, opts));
  return out;
}

/** Son hesaplama 30 dk'dan eskiyse (ya da gün değiştiyse) tazele */
async function ensureFresh(orgId, scopeKey, opts = {}) {
  const now = opts.now || clock.now();
  const { rows } = await db.query("SELECT ran_at, summary FROM insight_runs WHERE org_id = $1 AND scope_key = $2", [orgId, scopeKey]);
  const r = rows[0];
  const date = clock.istanbulDateStr(now);
  if (!opts.force && r && now - new Date(r.ran_at) < FRESH_MS && r.summary && r.summary.date === date) return false;
  await refresh(orgId, scopeKey, { ...opts, now, date });
  return true;
}

function present(r) {
  const rule = catalog.BY_KEY.get(r.rule_key);
  return {
    id: r.id, rule_key: r.rule_key, rule_title: rule ? rule.title : r.rule_key, severity: r.severity, title: r.title, body: r.body, status: r.status,
    snoozed_until: r.snoozed_until ? new Date(r.snoozed_until).toISOString() : null, evidence: r.evidence, actions: r.actions,
    entity: r.entity_type ? { type: r.entity_type, id: r.entity_id } : null,
    first_seen_at: new Date(r.first_seen_at).toISOString(), last_seen_at: new Date(r.last_seen_at).toISOString(), occurrences: r.occurrences,
    feedback: r.feedback, closed_reason: r.closed_reason,
  };
}

/** Görünürlük: admin/muhasebe → 'business'; ortak → yalnız kendi kapsamı; diğer roller → null (insight yok) */
async function list(user, orgId, { status = "acik", severity, limit = 50, fresh = true, now = clock.now() } = {}) {
  const sk = scopeKeyForUser(user);
  if (!sk) return null;
  if (fresh) await ensureFresh(orgId, sk, { now });
  await db.query("UPDATE insights SET status='acik', snoozed_until=NULL, updated_at=$3 WHERE org_id=$1 AND scope_key=$2 AND status='ertelendi' AND snoozed_until <= $3", [orgId, sk, now]);
  const p = [orgId, sk];
  let where = "org_id = $1 AND scope_key = $2";
  if (status !== "all") { p.push(status); where += ` AND status = $${p.length}`; }
  if (severity) { p.push(severity); where += ` AND severity = $${p.length}`; }
  const { rows } = await db.query(
    `SELECT * FROM insights WHERE ${where} ORDER BY CASE severity WHEN 'critical' THEN 3 WHEN 'warn' THEN 2 ELSE 1 END DESC, score DESC, last_seen_at DESC LIMIT ${Math.min(Math.max(Number(limit) || 50, 1), 200)}`, p);
  return rows.map(present);
}

/** Dikkat gerektiren (brifing/haftalık/aylık için): açık, önem sırasıyla ilk n */
async function top(user, orgId, n = 3, { now = clock.now(), minSeverity = "info" } = {}) {
  const rows = await list(user, orgId, { status: "acik", limit: 100, fresh: false, now });
  if (!rows) return [];
  return rows.filter((r) => SEV_RANK[r.severity] >= SEV_RANK[minSeverity]).slice(0, n);
}

async function loadVisible(user, orgId, id) {
  const sk = scopeKeyForUser(user);
  if (!sk) return null;
  const { rows } = await db.query("SELECT * FROM insights WHERE id = $1 AND org_id = $2 AND scope_key = $3", [id, orgId, sk]);
  return rows[0] || null;
}

async function setState(row, sets, now) {
  const cols = Object.keys(sets);
  const p = [row.id, ...cols.map((c) => sets[c]), now];
  const { rows } = await db.query(`UPDATE insights SET ${cols.map((c, i) => `${c} = $${i + 2}`).join(", ")}, updated_at = $${cols.length + 2} WHERE id = $1 RETURNING *`, p);
  return present(rows[0]);
}

/** Ertele: days (1–90) ya da until (ISO). Durum 'ertelendi' */
async function snooze(row, { days, until }, now = clock.now()) {
  let u = until ? new Date(until) : new Date(now.getTime() + Number(days) * dayMs);
  return setState(row, { status: "ertelendi", snoozed_until: u, closed_reason: null }, now);
}
/** Kapat: 14 gün susturma (koşul sürse de o süre açılmaz) */
async function dismiss(row, now = clock.now()) {
  return setState(row, { status: "kapatildi", closed_reason: "kullanici", closed_at: now, snoozed_until: new Date(now.getTime() + DISMISS_DAYS * dayMs) }, now);
}
/** Uygulandı: önerilen aksiyon yapıldı; 7 gün susturma */
async function markApplied(row, now = clock.now()) {
  return setState(row, { status: "uygulandi", closed_reason: "uygulandi", closed_at: now, snoozed_until: new Date(now.getTime() + APPLIED_DAYS * dayMs) }, now);
}
/** Geri bildirim: yanlis | alakasiz | yararli. 'yanlis'/'alakasiz' insight'ı 30 gün susturur (kural kalibrasyonu için kayıt kalır) */
async function feedback(row, verdict, note, now = clock.now()) {
  const sets = { feedback: verdict, feedback_note: note ? String(note).slice(0, 500) : null, feedback_at: now };
  if (verdict !== "yararli") Object.assign(sets, { status: "kapatildi", closed_reason: "kullanici", closed_at: now, snoozed_until: new Date(now.getTime() + WRONG_DAYS * dayMs) });
  return setState(row, sets, now);
}

// ---- kural yapılandırması (admin) --------------------------------------------------------------------------
async function rulesView(orgId) {
  const cfg = await loadConfig(orgId);
  const fb = await db.query("SELECT rule_key, feedback, COUNT(*)::int AS n FROM insights WHERE org_id = $1 AND feedback IS NOT NULL GROUP BY 1, 2", [orgId]);
  const fbMap = {};
  for (const r of fb.rows) (fbMap[r.rule_key] = fbMap[r.rule_key] || {})[r.feedback] = r.n;
  const rules = [];
  for (const r of catalog.RULES) {
    const row = cfg.get(r.key);
    const dep = await catalog.dependencyState(r);
    const enabled = !(row && row.enabled === false);
    rules.push({
      rule_key: r.key, title: r.title, description: r.description, group: r.group, enabled,
      status: !dep.available ? "bagimli" : enabled ? "aktif" : "kapali",
      dependency: (r.requires || []).length ? { requires: r.requires.map((x) => x.table), available: dep.available, missing: dep.missing } : null,
      scope: r.scopes ? r.scopes.join(",") : "business,user", params: effParams(r, row), defaults: r.defaultParams, feedback: fbMap[r.key] || {},
    });
  }
  const star = cfg.get("*");
  return { calibration_mode: !!(star && star.params && star.params.calibration), rules };
}

async function saveRules(orgId, userId, body) {
  const b = body && typeof body === "object" && !Array.isArray(body) ? body : null;
  if (!b) return { error: "Geçersiz gövde." };
  const known = ["rules", "calibration_mode"];
  for (const k of Object.keys(b)) if (!known.includes(k)) return { error: `Bilinmeyen alan: ${k}` };
  if (b.rules === undefined && b.calibration_mode === undefined) return { error: "rules ya da calibration_mode gerekli." };
  const ops = [];
  if (b.calibration_mode !== undefined) {
    if (typeof b.calibration_mode !== "boolean") return { error: "calibration_mode true/false olmalı." };
    ops.push({ key: "*", enabled: true, params: { calibration: b.calibration_mode ? 1 : 0 } });
  }
  if (b.rules !== undefined) {
    if (!Array.isArray(b.rules) || b.rules.length === 0 || b.rules.length > 40) return { error: "rules 1–40 öğeli dizi olmalı." };
    for (const x of b.rules) {
      const rule = x && catalog.BY_KEY.get(x.rule_key);
      if (!rule) return { error: `Bilinmeyen kural: ${x && x.rule_key}` };
      for (const k of Object.keys(x)) if (!["rule_key", "enabled", "params"].includes(k)) return { error: `${rule.key}: bilinmeyen alan '${k}'.` };
      if (x.enabled !== undefined && typeof x.enabled !== "boolean") return { error: `${rule.key}.enabled true/false olmalı.` };
      let params;
      if (x.params !== undefined) { const v = catalog.validateParams(rule, x.params); if (v.error) return { error: v.error }; params = v.value; }
      if (x.enabled === undefined && params === undefined) return { error: `${rule.key}: enabled ya da params gerekli.` };
      ops.push({ key: rule.key, enabled: x.enabled, params });
    }
  }
  for (const o of ops) {
    await db.query(
      `INSERT INTO insight_rule_config (org_id, rule_key, enabled, params, updated_by) VALUES ($1,$2,COALESCE($3,true),COALESCE($4::jsonb,'{}'::jsonb),$5)
       ON CONFLICT (org_id, rule_key) DO UPDATE SET enabled = COALESCE($3, insight_rule_config.enabled),
         params = CASE WHEN $4::jsonb IS NULL THEN insight_rule_config.params ELSE insight_rule_config.params || $4::jsonb END, updated_at = now(), updated_by = $5`,
      [orgId, o.key, o.enabled === undefined ? null : o.enabled, o.params === undefined ? null : JSON.stringify(o.params), userId]);
  }
  return { ok: true };
}

module.exports = { refresh, refreshAll, ensureFresh, list, top, loadVisible, snooze, dismiss, markApplied, feedback, rulesView, saveRules, scopeKeyForUser, allScopes, present, DISMISS_DAYS, APPLIED_DAYS, WRONG_DAYS };
