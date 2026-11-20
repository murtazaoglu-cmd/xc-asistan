const crypto = require("crypto");
const db = require("../db");
const { authenticate } = require("./auth");

/**
 * Idempotency-Key ara katmanı (YALNIZ POST, OPSİYONEL; başlık yoksa hiçbir şey değişmez).
 *  - Anahtar kullanıcı başına geçerlidir (oturum gerekir; oturumsuz isteklerde başlık yok sayılır).
 *  - Aynı anahtar + aynı istek → ilk 2xx JSON yanıtı yeniden gönderilir (başlık `Idempotent-Replay: true`), işlem TEKRARLANMAZ.
 *  - Aynı anahtar, farklı istek (yol/gövde) → 422. Aynı anahtarla işlem sürüyorsa → 409.
 *  - Yalnız 2xx JSON yanıtlar saklanır; hata (4xx/5xx) ya da JSON olmayan yanıt (PDF…) olursa anahtar serbest bırakılır, istemci yeniden deneyebilir.
 * Kayıtlar 48 saat sonra housekeeping işiyle silinir. Yanıt, kayıt yazıldıktan SONRA istemciye gider (yarış yok).
 */
const KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;
const STALE_MS = 2 * 60 * 1000;

function normPath(u) { return String(u).replace(/^\/api\/v1(?=\/|\?|$)/, "/api"); }

module.exports = async function idempotency(req, res, next) {
  if (req.method !== "POST") return next();
  const key = req.headers["idempotency-key"];
  if (key === undefined) return next();
  if (typeof key !== "string" || !KEY_RE.test(key)) return res.status(400).json({ error: "Idempotency-Key geçersiz (8-128 karakter: harf, rakam, _ - : .)." });
  const a = await authenticate(req.headers.authorization);
  if (!a.user) return next();
  const userId = a.user.id;
  const hash = crypto.createHash("sha256").update(`${normPath(req.originalUrl)}\n${JSON.stringify(req.body || {})}\n${req.headers["content-length"] || ""}`).digest("hex");

  let ins = await db.query("INSERT INTO idempotency_keys (user_id, key, request_hash) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING RETURNING key", [userId, key, hash]);
  if (!ins.rows[0]) {
    const { rows } = await db.query("SELECT request_hash, status_code, response_body, created_at FROM idempotency_keys WHERE user_id = $1 AND key = $2", [userId, key]);
    const ex = rows[0];
    if (ex) {
      if (ex.request_hash !== hash) return res.status(422).json({ error: "Bu Idempotency-Key farklı bir istekle kullanılmış." });
      if (ex.status_code !== null) { res.set("Idempotent-Replay", "true"); return res.status(ex.status_code).json(ex.response_body); }
      if (Date.now() - new Date(ex.created_at).getTime() < STALE_MS) return res.status(409).json({ error: "Bu istek hâlâ işleniyor; kısa süre sonra tekrar deneyin." });
      // yarım kalmış (çökmüş) eski deneme: sahiplen
      const take = await db.query("UPDATE idempotency_keys SET created_at = now() WHERE user_id = $1 AND key = $2 AND status_code IS NULL AND created_at = $3 RETURNING key", [userId, key, ex.created_at]);
      if (!take.rows[0]) return res.status(409).json({ error: "Bu istek hâlâ işleniyor; kısa süre sonra tekrar deneyin." });
    } else {
      ins = await db.query("INSERT INTO idempotency_keys (user_id, key, request_hash) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING RETURNING key", [userId, key, hash]);
      if (!ins.rows[0]) return res.status(409).json({ error: "Bu istek hâlâ işleniyor; kısa süre sonra tekrar deneyin." });
    }
  }

  let stored = false;
  const origJson = res.json.bind(res);
  res.json = (body) => {
    if (stored) return origJson(body);
    stored = true;
    if (res.statusCode < 200 || res.statusCode >= 300) { // hata: anahtarı yanıttan ÖNCE serbest bırak (hemen ardından düzeltilmiş istek gelebilir)
      db.query("DELETE FROM idempotency_keys WHERE user_id = $1 AND key = $2 AND status_code IS NULL", [userId, key]).catch(() => {}).finally(() => origJson(body));
      return res;
    }
    const code = res.statusCode;
    db.query("UPDATE idempotency_keys SET status_code = $3, response_body = $4 WHERE user_id = $1 AND key = $2", [userId, key, code, JSON.stringify(body === undefined ? null : body)])
      .catch((e) => console.error("idempotency kaydı yazılamadı:", e.message))
      .finally(() => origJson(body));
    return res;
  };
  res.on("finish", () => {
    if (!stored) db.query("DELETE FROM idempotency_keys WHERE user_id = $1 AND key = $2 AND status_code IS NULL", [userId, key]).catch(() => {});
  });
  next();
};
