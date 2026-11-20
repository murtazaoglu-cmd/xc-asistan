/**
 * Müdür kural kataloğu (M1–M13 + alt kurallar). Her kural: {key, group, title, description, defaultParams, requires?, scopes?, collect(ctx, params, facts), evaluate(input, params)}.
 * Bağımlılığı olan kurallar (M7 → invoices, M8 → vat_periods) tablo/sütun yoksa DEVRE DIŞI sayılır (varsayım yok: çalışma anında yoklanır).
 */
const deps = require("../facts/deps");

const RULES = [].concat(require("./rules/money"), require("./rules/receivables"), require("./rules/margin"), require("./rules/pipeline"));
const ORDER = ["M1", "M2", "M2b", "M3", "M3b", "M4", "M5", "M6", "M6b", "M6c", "M7", "M8", "M9", "M10", "M11", "M12", "M13"];
RULES.sort((a, b) => ORDER.indexOf(a.key) - ORDER.indexOf(b.key));
const BY_KEY = new Map(RULES.map((r) => [r.key, r]));

/** Kuralın bağımlılıkları karşılanıyor mu? → {available, missing:[tablo]} */
async function dependencyState(rule) {
  const missing = [];
  for (const r of rule.requires || []) if (!(await deps.has(r.table, r.cols || []))) missing.push(r.table);
  return { available: missing.length === 0, missing };
}

/** Sınırlar: params doğrulaması için kural başına alan → [min, max] (hepsi tamsayı) */
const BOUNDS = { default: [0, 1000000000] };

function validateParams(rule, input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return { error: "params nesne olmalı." };
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    if (!(k in rule.defaultParams)) return { error: `${rule.key}: bilinmeyen parametre '${k}'. İzin verilenler: ${Object.keys(rule.defaultParams).join(", ")}.` };
    if (!Number.isInteger(v) || v < 0 || v > 1000000000) return { error: `${rule.key}.${k} 0 ile 1.000.000.000 arasında tam sayı olmalı (para kuruş, oran baz puandır).` };
    out[k] = v;
  }
  return { value: out };
}

module.exports = { RULES, BY_KEY, dependencyState, validateParams, BOUNDS };
