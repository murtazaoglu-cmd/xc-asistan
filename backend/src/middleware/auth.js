const jwt = require("jsonwebtoken");
const db = require("../db");

/**
 * Oturum doğrulama. JWT imzası + süresi kontrol edilir, ardından kullanıcı hâlâ var mı ve
 * jetonun token_version'ı güncel mi bakılır (kısa süreli bellek önbelleğiyle; istek başına DB yükü yok denecek kadar az).
 * Sonuç: silinen kullanıcı, "tüm cihazlardan çıkış" yapılmış oturum veya rolü değişmiş kullanıcı en geç
 * CACHE_TTL_MS içinde (aynı süreçte anında) yeni duruma geçer. req.user.role her zaman veritabanındaki güncel roldür.
 */
// Önbellek ömrü AUTH_CACHE_TTL_MS (varsayılan 10 sn, en çok 30 sn): çok süreçli (PM2 cluster) kurulumda iptal en geç bu sürede yansır
const CACHE_TTL_MS = Math.min(Math.max(Number(process.env.AUTH_CACHE_TTL_MS) || 10 * 1000, 0), 30 * 1000);
const cache = new Map();

async function loadUserState(id) {
  const hit = cache.get(id);
  if (hit && hit.exp > Date.now()) return hit.v;
  const { rows } = await db.query("SELECT id, name, role, token_version FROM users WHERE id = $1", [id]);
  const v = rows[0] || null;
  if (cache.size > 5000) cache.clear();
  cache.set(id, { v, exp: Date.now() + CACHE_TTL_MS });
  return v;
}

/** Kullanıcı durumu değişince (çıkış, silme, rol) önbelleği hemen temizle */
function invalidateUser(id) {
  cache.delete(id);
}

/** Bearer jetonundan kullanıcıyı çözer; geçersizse null */
async function authenticate(header) {
  if (!header || !header.startsWith("Bearer ")) return { error: "missing" };
  let payload;
  try {
    payload = jwt.verify(header.split(" ")[1], process.env.JWT_SECRET, { algorithms: ["HS256"] });
  } catch {
    return { error: "invalid" };
  }
  const state = payload && payload.id ? await loadUserState(payload.id) : null;
  if (!state || (payload.tv ?? 0) !== state.token_version) return { error: "revoked" };
  return {
    user: { id: state.id, name: state.name, role: state.role, tv: state.token_version, cl: payload.cl || "web", exp: payload.exp },
  };
}

async function requireAuth(req, res, next) {
  const r = await authenticate(req.headers.authorization);
  if (r.error === "missing") return res.status(401).json({ error: "Yetkilendirme gerekli." });
  if (r.error) return res.status(401).json({ error: "Geçersiz veya süresi dolmuş oturum." });
  req.user = r.user;
  next();
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ error: "Bu işlem için yetkiniz yok." });
    }
    next();
  };
}

async function optionalAuth(req, res, next) {
  // geçersiz/iptal edilmiş token — sessizce devam et, req.user tanımsız kalır
  const r = await authenticate(req.headers.authorization);
  if (r.user) req.user = r.user;
  next();
}

module.exports = { requireAuth, requireRole, optionalAuth, invalidateUser, authenticate };
