/**
 * Sektör sözlüğü: metinlerde SABİT sektör ifadesi yok; terimler org_settings.sector_dictionary.terms'ten gelir.
 * Anahtar yoksa nötr varsayılana ('genel' şablonu) düşer. İstemci ile aynı anahtarlar: customer(s), job(s), offer(s), appointment(s),
 * expense(s), payment(s), staff, location, visit.
 *
 *   const T = await loadTerms(orgId);  ya da  makeTerms(termsObject)
 *   T.get("offer")  → "Teklif"        T.lc("offers") → "teklifler"
 *   T.n(3, "appointment") → "3 randevu"   (sayıdan sonra tekil)
 *   T.ek("job","dat") → "projeye"          (sözlük teriminin ek almış hâli)
 */
const db = require("../../db");
const tr = require("./tr");

const DEFAULTS = {
  customer: "Müşteri", customers: "Müşteriler", job: "İş", jobs: "İşler", offer: "Teklif", offers: "Teklifler",
  appointment: "Randevu", appointments: "Randevular", expense: "Gider", expenses: "Giderler", payment: "Tahsilat", payments: "Tahsilatlar",
  staff: "Ekip", location: "Adres", visit: "Ziyaret",
};

function makeTerms(terms) {
  const dict = { ...DEFAULTS, ...(terms && typeof terms === "object" ? terms : {}) };
  const get = (k) => {
    const v = dict[k];
    return typeof v === "string" && v.trim() ? v.trim() : (DEFAULTS[k] || k);
  };
  return {
    dict,
    get,
    lc: (k) => tr.lower(get(k)),
    cap: (k) => tr.cap(get(k)),
    /** "3 randevu" — tekil terim kullanılır (Türkçe sayı kuralı); k ya tekil anahtar ya da çoğul anahtardır */
    n: (n, k) => `${n} ${tr.lower(get(singularKey(k)))}`,
    ek: (k, kind) => tr.ek(tr.lower(get(k)), kind),
  };
}
const singularKey = (k) => ({ customers: "customer", jobs: "job", offers: "offer", appointments: "appointment", expenses: "expense", payments: "payment" }[k] || k);

const cache = new Map(); // orgId -> {t, exp}
async function loadTerms(orgId, opts = {}) {
  const hit = cache.get(orgId);
  if (hit && hit.exp > Date.now() && !opts.fresh) return hit.t;
  let terms = null;
  try {
    const { rows } = await db.query("SELECT sector_dictionary FROM org_settings WHERE org_id = $1", [orgId]);
    terms = rows[0] && rows[0].sector_dictionary && rows[0].sector_dictionary.terms;
  } catch { /* tablo/ayar yoksa varsayılan */ }
  const t = makeTerms(terms);
  cache.set(orgId, { t, exp: Date.now() + 30000 });
  return t;
}
const _resetCache = () => cache.clear();

module.exports = { loadTerms, makeTerms, DEFAULTS, _resetCache };
