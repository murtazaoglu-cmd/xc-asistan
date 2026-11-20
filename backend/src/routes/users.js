const express = require("express");
const bcrypt = require("bcryptjs");
const db = require("../db");
const rateLimit = require("express-rate-limit");
const { requireAuth, requireRole, invalidateUser } = require("../middleware/auth");
const { issueToken } = require("../services/tokens");
const { BCRYPT_ROUNDS } = require("../services/passwords");
const { parseEmail, text, validatePassword } = require("../services/validate");

const router = express.Router();

/** ADMIN + "Ortak" — Kullanıcıları listele. "Ortak" sadece kendi oluşturduğu kullanıcıları görür. */
router.get("/", requireAuth, requireRole("admin", "ortak"), async (req, res) => {
  if (req.user.role === "ortak") {
    const { rows } = await db.query(
      "SELECT id, name, email, role, created_at FROM users WHERE created_by = $1 ORDER BY created_at DESC",
      [req.user.id]
    );
    return res.json(rows);
  }
  const { rows } = await db.query("SELECT id, name, email, role, created_at FROM users ORDER BY created_at DESC");
  res.json(rows);
});

/** ADMIN + "Ortak" — Yeni kullanıcı oluştur. "Ortak" oluşturduğu kullanıcının sahibi olarak işaretlenir,
 *  böylece sadece kendi ekibini görür/yönetir — admin'in kullanıcılarını göremez. */
router.post("/", requireAuth, requireRole("admin", "ortak"), async (req, res) => {
  let { name, email, password, role } = req.body;
  const validRoles = req.user.role === "ortak"
    ? ["saha", "personel"] // ortak; admin/muhasebe/ortak oluşturamaz (muhasebe tüm işletme verisini görür)
    : ["admin", "saha", "muhasebe", "personel", "ortak"];
  if (!name || !email || !password || !role) {
    return res.status(400).json({ error: "Ad, e-posta, şifre ve rol zorunludur." });
  }
  const nm = text(name, 100);
  if (nm.error || !nm.value) return res.status(400).json({ error: "Ad en çok 100 karakterlik bir metin olmalıdır." });
  name = nm.value;
  if (typeof role !== "string" || !validRoles.includes(role)) {
    return res.status(400).json({ error: "Geçersiz rol." });
  }
  const pwErr = validatePassword(password);
  if (pwErr) return res.status(400).json({ error: pwErr });
  const em = parseEmail(email);
  if (em.error || !em.value) return res.status(400).json({ error: "Geçerli bir e-posta adresi girin." });
  email = em.value.toLowerCase();
  const existing = await db.query("SELECT id FROM users WHERE lower(email) = $1", [email]);
  if (existing.rows.length > 0) {
    return res.status(409).json({ error: "Bu e-posta ile kayıtlı bir kullanıcı zaten var." });
  }

  const hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const { rows } = await db.query(
    "INSERT INTO users (name, email, password_hash, role, created_by) VALUES ($1,$2,$3,$4,$5) RETURNING id, name, email, role, created_at",
    [name, email, hash, role, req.user.id]
  );
  res.status(201).json(rows[0]);
});

// Parola değiştirme/sıfırlama kaba kuvvet denemesine karşı sınırlıdır (kullanıcı başına 15 dk'da 10 deneme)
const passwordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 10,
  keyGenerator: (req) => (req.user ? "u:" + req.user.id : "ip"),
  message: { error: "Çok fazla deneme. Lütfen biraz sonra tekrar deneyin." },
});

/** Oturum açmış kullanıcı kendi şifresini değiştirir. Tüm eski oturumlar iptal olur; yanıtla YENİ jeton döner.
 *  body: { current_password, new_password } */
router.patch("/me/password", requireAuth, passwordLimiter, async (req, res) => {
  const { current_password, new_password } = req.body;
  if (typeof current_password !== "string" || !current_password) return res.status(400).json({ error: "Mevcut şifre zorunludur." });
  const pwErr = validatePassword(new_password);
  if (pwErr) return res.status(400).json({ error: pwErr });
  const { rows } = await db.query("SELECT id, name, email, role, password_hash FROM users WHERE id = $1", [req.user.id]);
  const u = rows[0];
  if (!u || !(await bcrypt.compare(current_password, u.password_hash))) return res.status(400).json({ error: "Mevcut şifre hatalı." });
  const hash = await bcrypt.hash(new_password, BCRYPT_ROUNDS);
  const upd = await db.query(
    "UPDATE users SET password_hash = $1, token_version = token_version + 1, password_changed_at = now() WHERE id = $2 RETURNING token_version",
    [hash, u.id]
  );
  await db.query("DELETE FROM device_tokens WHERE user_id = $1", [u.id]);
  invalidateUser(u.id);
  res.json({ message: "Şifre değiştirildi. Diğer tüm oturumlar sonlandırıldı.", ...issueToken({ ...u, token_version: upd.rows[0].token_version }, req.user.cl), user: { id: u.id, name: u.name, email: u.email, role: u.role } });
});

/** ADMIN + "Ortak" — Başka bir kullanıcının şifresini sıfırla (ortak yalnız kendi oluşturduğunu). Hedefin oturumları iptal olur.
 *  body: { new_password } */
router.patch("/:id/password", requireAuth, requireRole("admin", "ortak"), passwordLimiter, async (req, res) => {
  const pwErr = validatePassword(req.body.new_password);
  if (pwErr) return res.status(400).json({ error: pwErr });
  const target = await db.query("SELECT id, created_by FROM users WHERE id = $1", [req.params.id]);
  if (!target.rows[0]) return res.status(404).json({ error: "Kullanıcı bulunamadı." });
  if (req.user.role === "ortak" && String(target.rows[0].created_by) !== String(req.user.id)) {
    return res.status(403).json({ error: "Bu kullanıcı size ait değil." });
  }
  const hash = await bcrypt.hash(req.body.new_password, BCRYPT_ROUNDS);
  await db.query("UPDATE users SET password_hash = $1, token_version = token_version + 1, password_changed_at = now() WHERE id = $2", [hash, req.params.id]);
  await db.query("DELETE FROM device_tokens WHERE user_id = $1", [req.params.id]);
  invalidateUser(req.params.id);
  res.json({ message: "Şifre sıfırlandı; kullanıcının tüm oturumları sonlandırıldı." });
});

/** ADMIN + "Ortak" — Kullanıcı sil (kendini silemez; "ortak" sadece kendi oluşturduğunu silebilir) */
router.delete("/:id", requireAuth, requireRole("admin", "ortak"), async (req, res) => {
  if (req.params.id === req.user.id) {
    return res.status(400).json({ error: "Kendi hesabınızı silemezsiniz." });
  }
  if (req.user.role === "ortak") {
    const existing = await db.query("SELECT created_by FROM users WHERE id = $1", [req.params.id]);
    if (!existing.rows[0]) return res.status(404).json({ error: "Kullanıcı bulunamadı." });
    if (String(existing.rows[0].created_by) !== String(req.user.id)) {
      return res.status(403).json({ error: "Bu kullanıcı size ait değil." });
    }
  }
  // Finans kayıtları (ödeme/gider) silinen kullanıcıya bağlıysa silme işlemini engellemeden, silen kişiye devret
  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("UPDATE expenses SET owner_id = $1 WHERE owner_id = $2", [req.user.id, req.params.id]);
    await client.query("UPDATE payments SET owner_id = $1 WHERE owner_id = $2", [req.user.id, req.params.id]);
    await client.query("UPDATE invoices SET owner_id = $1 WHERE owner_id = $2", [req.user.id, req.params.id]); // v18: faturalar ve tahsilat planı da devredilir
    await client.query("UPDATE payment_schedule SET owner_id = $1 WHERE owner_id = $2", [req.user.id, req.params.id]);
    await client.query("DELETE FROM users WHERE id = $1", [req.params.id]);
    await client.query("COMMIT");
    invalidateUser(req.params.id); // silinen kullanıcının jetonları hemen geçersiz olsun
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
  res.json({ message: "Kullanıcı silindi." });
});

module.exports = router;
