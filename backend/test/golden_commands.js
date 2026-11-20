// Altın veri seti değerlendirici (birim; veritabanı gerekmez). Kullanım: node test/golden_commands.js [-v]
const path = require("path");
const fx = require("./fixtures/commands.tr.json");
const { parseCommand } = require("../src/assistant/command");

function check(res, exp) {
  const errs = [];
  if (res.intent !== exp.intent) { errs.push(`intent ${res.intent} != ${exp.intent}`); return errs; }
  const p = res.params || {};
  for (const [k, v] of Object.entries(exp.params || {})) {
    if (k === "customer") { const got = p.customer?.match?.key; if (got !== v) errs.push(`customer ${got} != ${v}`); }
    else if (k === "customer_ambiguous") { const got = (p.customer?.candidates || []).map((c) => c.key).sort(); const w = [...v].sort(); if (!p.customer?.match && JSON.stringify(got) === JSON.stringify(w)) { /* ok */ } else errs.push(`customer_ambiguous ${JSON.stringify(got)} != ${JSON.stringify(w)}`); }
    else if (k === "matches") { const got = (p.matches || []).map((c) => c.key).sort(); if (JSON.stringify(got) !== JSON.stringify([...v].sort())) errs.push(`matches ${JSON.stringify(got)} != ${JSON.stringify(v)}`); }
    else if (p[k] !== v) errs.push(`${k} ${JSON.stringify(p[k])} != ${JSON.stringify(v)}`);
  }
  for (const a of exp.amb || []) if (!res.ambiguities.some((x) => x.field === a.field && x.kind === a.kind)) errs.push(`amb ${a.field}/${a.kind} yok`);
  return errs;
}

function run(set) {
  const now = new Date(fx.now);
  const cases = fx.cases.filter((c) => !set || c.set === set);
  let ok = 0, fieldsTotal = 0, fieldsOk = 0; const fails = [];
  for (const c of cases) {
    const res = parseCommand(c.text, { now, candidates: fx.customers });
    const errs = check(res, c);
    fieldsTotal += 1 + Object.keys(c.params || {}).length + (c.amb || []).length;
    fieldsOk += fieldsTotal ? (1 + Object.keys(c.params || {}).length + (c.amb || []).length - errs.filter((e) => !e.startsWith("intent")).length - (errs.some((e) => e.startsWith("intent")) ? 1 + Object.keys(c.params || {}).length + (c.amb || []).length : 0)) : 0;
    if (!errs.length) ok++; else fails.push({ text: c.text, errs, got: res });
  }
  return { n: cases.length, ok, acc: ok / cases.length, fails, fieldAcc: null };
}
module.exports = { run, check, fx };
if (require.main === module) {
  const v = process.argv.includes("-v");
  for (const set of [null, "dev", "holdout", "blind2"]) {
    const r = run(set);
    console.log(`${set || "TÜMÜ"}: ${r.ok}/${r.n} = ${(r.acc * 100).toFixed(1)}%`);
    if (v && set === null) for (const f of r.fails) console.log("  ✗", JSON.stringify(f.text), "→", f.errs.join(" | "));
  }
}
