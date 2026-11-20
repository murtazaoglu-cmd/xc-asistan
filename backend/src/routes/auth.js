const express = require("express");
const bcrypt = require("bcryptjs");
const db = require("../db");
const { requireAuth, invalidateUser } = require("../middleware/auth");
const { issueToken } = require("../services/tokens");

// Kullanıcı bulunamadığında da bcrypt çalıştırılır (zamanlama farkıyla hesap varlığı anlaşılmasın)
const { BCRYPT_ROUNDS } = require("../services/passwords");
const DUMMY_HASH = bcrypt.hashSync("dummy-password", BCRYPT_ROUNDS);

const router = express.Router();

const publicUser = (u) => ({ id: u.id, name: u.name, email: u.email, role: u.role });

// POST /api/auth/login   body: { email, password, client?: "mobile" }
router.post("/login", async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password || typeof email !== "string" || typeof password !== "string" || email.length > 254 || password.length > 1000) {
    return res.status(400).json({ error: "E-posta ve şifre zorunludur." });
  }

  const { rows } = await db.query("SELECT * FROM users WHERE lower(email) = lower($1)", [String(email).trim()]);
  const user = rows[0];
  // Kullanıcı yokluğu ile hatalı şifre aynı mesajı verir (hesap varlığı sızdırılmaz)
  const valid = await bcrypt.compare(String(password), user ? user.password_hash : DUMMY_HASH);
  if (!user || !valid) return res.status(401).json({ error: "E-posta veya şifre hatalı." });

  const client = req.body.client === "mobile" || req.headers["x-client"] === "mobile" ? "mobile" : "web";
  res.json({ ...issueToken(user, client), user: publicUser(user) });
});

// Rol bazlı yetenekler — mobil arayüzün menüleri göstermesi için (sunucu yine de her uçta yetkiyi denetler)
function capabilitiesFor(role) {
  const finance = ["admin", "muhasebe", "ortak", "personel"].includes(role);
  return {
    offers: ["admin", "muhasebe", "ortak", "personel"].includes(role),
    quotes: ["admin", "muhasebe", "ortak"].includes(role),
    projects: ["admin", "muhasebe", "ortak", "personel"].includes(role),
    customers: ["admin", "muhasebe", "ortak"].includes(role),
    finance,
    homeFinance: ["admin", "muhasebe", "ortak"].includes(role),
    materials: ["admin", "muhasebe", "ortak"].includes(role),
    manageUsers: ["admin", "ortak"].includes(role),
    appointmentsCreate: ["admin", "muhasebe", "ortak", "personel"].includes(role),
  };
}

// GET /api/auth/me — oturum doğrulama + kullanıcı, rol, ekip
router.get("/me", requireAuth, async (req, res) => {
  const { rows } = await db.query("SELECT id, name, email, role, created_by, created_at FROM users WHERE id = $1", [req.user.id]);
  const me = rows[0];
  // Ekip: admin → tüm kullanıcılar; muhasebe → diğerleri; ortak → kendi oluşturdukları;
  // personel/saha → kendini oluşturan (lider) + aynı lider altındaki kişiler. (dashboard-init "users" ile aynı kural)
  let team;
  if (me.role === "admin") team = (await db.query("SELECT id, name, role FROM users WHERE id != $1 ORDER BY name ASC", [me.id])).rows;
  else if (me.role === "muhasebe") team = (await db.query("SELECT id, name, role FROM users WHERE id != $1 ORDER BY name ASC", [me.id])).rows;
  else if (me.role === "ortak") team = (await db.query("SELECT id, name, role FROM users WHERE created_by = $1 ORDER BY name ASC", [me.id])).rows;
  else {
    team = me.created_by
      ? (await db.query(
          `SELECT id, name, role FROM users WHERE id != $1 AND (created_by = $2 OR id = $2) ORDER BY name ASC`,
          [me.id, me.created_by])).rows
      : [];
  }
  const leader = me.created_by ? (await db.query("SELECT id, name, role FROM users WHERE id = $1", [me.created_by])).rows[0] || null : null;
  res.json({
    user: publicUser(me),
    leader,
    team,
    capabilities: capabilitiesFor(me.role),
    session: { client: req.user.cl, expiresAt: new Date(req.user.exp * 1000).toISOString() },
  });
});

// POST /api/auth/refresh — geçerli jetonla yeni (süresi uzatılmış) jeton; eski jeton da süresi dolana dek geçerli kalır
router.post("/refresh", requireAuth, async (req, res) => {
  const { rows } = await db.query("SELECT id, name, email, role, token_version FROM users WHERE id = $1", [req.user.id]);
  res.json({ ...issueToken(rows[0], req.user.cl), user: publicUser(rows[0]) });
});

// POST /api/auth/logout-all — bu kullanıcının TÜM cihazlardaki oturumlarını iptal eder (jeton çalındı/telefon kayboldu)
router.post("/logout-all", requireAuth, async (req, res) => {
  await db.query("UPDATE users SET token_version = token_version + 1 WHERE id = $1", [req.user.id]);
  await db.query("DELETE FROM device_tokens WHERE user_id = $1", [req.user.id]);
  invalidateUser(req.user.id);
  res.json({ message: "Tüm oturumlar sonlandırıldı. Yeniden giriş yapın." });
});

module.exports = router;
