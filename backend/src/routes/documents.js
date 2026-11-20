const express = require("express");
const multer = require("multer");
const rateLimit = require("express-rate-limit");
const crypto = require("crypto");
const path = require("path");
const fs = require("fs");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");
const { logActivity } = require("../middleware/activity");
const { UPLOAD_DIR, signRow, relFromStored, contentMatchesExt, DOC_EXTENSIONS } = require("../services/fileAccess");

const router = express.Router();

const DOCS_DIR = path.join(UPLOAD_DIR, "documents");
if (!fs.existsSync(DOCS_DIR)) fs.mkdirSync(DOCS_DIR, { recursive: true });

// Yalnızca izin verilen (allowlist) türler yüklenebilir; içerik de ilk baytlardan doğrulanır (uzantı sahteciliği engellenir).
const ALLOWED_EXT = new Set(DOC_EXTENSIONS);
const extOf = (name) => path.extname(String(name || "")).toLowerCase();

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, DOCS_DIR),
  filename: (req, file, cb) => {
    // Sunucu adı: zaman + rastgele + güvenli ad parçası + doğrulanmış küçük harfli uzantı (yol geçişi/çift uzantı hilesi yok)
    const ext = extOf(file.originalname);
    const stem = path.basename(file.originalname, path.extname(file.originalname)).replace(/[^\w\-]+/g, "_").slice(0, 50) || "dosya";
    cb(null, `${Date.now()}-${crypto.randomBytes(6).toString("hex")}-${stem}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 15 * 1024 * 1024, files: 1, fields: 5, parts: 8 }, // 15MB
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_EXT.has(extOf(file.originalname))) return cb(Object.assign(new Error("Bu dosya türü yüklenemez."), { status: 400 }));
    cb(null, true);
  },
});

/** Kayıt yetkisi; true/false döner, hata yanıtını kendisi yazar */
async function checkAccess(req, res, resourceType, resourceId) {
  if (!["offer", "project"].includes(resourceType)) {
    res.status(400).json({ error: "Geçersiz kaynak türü." });
    return false;
  }
  const table = resourceType === "offer" ? "offers" : "projects";
  const ownerRes = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [resourceId]);
  if (!ownerRes.rows[0]) { res.status(404).json({ error: "Kayıt bulunamadı." }); return false; }
  const allowed = await canAccessResource(req.user, resourceType, resourceId, ownerRes.rows[0].owner_id);
  if (!allowed) { res.status(403).json({ error: "Erişiminiz yok." }); return false; }
  return true;
}

// Yükleme hız sınırı: kullanıcı başına 15 dk'da 120 dosya
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 120,
  keyGenerator: (req) => (req.user ? "u:" + req.user.id : "ip"),
  message: { error: "Çok fazla dosya yükleme isteği. Lütfen biraz sonra tekrar deneyin." },
});

router.get("/:resourceType/:resourceId", (req, res, next) => (req.params.resourceType === "file" ? next("route") : next()), requireAuth, async (req, res) => {
  const { resourceType, resourceId } = req.params;
  if (!(await checkAccess(req, res, resourceType, resourceId))) return;
  const { rows } = await db.query(`
    SELECT d.*, u.name AS uploaded_by_name FROM documents d
    LEFT JOIN users u ON u.id = d.uploaded_by
    WHERE d.resource_type = $1 AND d.resource_id = $2 ORDER BY d.created_at DESC
  `, [resourceType, resourceId]);
  // file_url kısa ömürlü (10 dk) imzalı bağlantı olarak döner; süresi dolunca listeyi yeniden çekin
  res.json(rows.map((r) => signRow(r, "file_url")));
});

/** Dosyayı Authorization başlığıyla doğrudan akıt (mobil/panel). İmzalı bağlantı yerine bu uç da kullanılabilir. */
router.get("/file/:id", requireAuth, async (req, res) => {
  const { rows } = await db.query("SELECT resource_type, resource_id, file_url, file_name FROM documents WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "Dosya bulunamadı." });
  if (!(await checkAccess(req, res, rows[0].resource_type, rows[0].resource_id))) return;
  const rel = relFromStored(rows[0].file_url);
  const abs = rel && path.resolve(UPLOAD_DIR, rel);
  if (!abs || !abs.startsWith(path.resolve(UPLOAD_DIR) + path.sep) || !fs.existsSync(abs)) return res.status(404).json({ error: "Dosya bulunamadı." });
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cache-Control", "private, no-store");
  const inline = [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".gif"].includes(extOf(abs));
  res.setHeader("Content-Disposition", `${inline ? "inline" : "attachment"}; filename="${path.basename(abs).replace(/[^\w.\-]/g, "_")}"`);
  res.sendFile(abs, { dotfiles: "deny" });
});

// Yetki + kaynak kontrolü dosya diske yazılmadan ÖNCE yapılır (yetkisiz/boş isteklerle disk doldurulamaz)
async function precheck(req, res, next) {
  if (!(await checkAccess(req, res, req.params.resourceType, req.params.resourceId))) return;
  next();
}
// Reddedilen/yarım kalan yüklemeyi yanıttan ÖNCE diskten sil (eşzamanlı: yanıt dönünce dosya gerçekten yok)
const removeFile = (f) => { if (f && f.path) { try { fs.unlinkSync(f.path); } catch {} } };

router.post("/:resourceType/:resourceId", requireAuth, uploadLimiter, precheck, upload.single("file"), async (req, res) => {
  const { resourceType, resourceId } = req.params;
  if (!req.file) return res.status(400).json({ error: "Dosya bulunamadı." });
  // İçerik doğrulaması: uzantı pdf ama gövde HTML gibi sahtecilikler reddedilir
  if (!contentMatchesExt(req.file.path, extOf(req.file.filename))) {
    removeFile(req.file);
    return res.status(400).json({ error: "Dosya içeriği uzantısıyla uyuşmuyor; yüklenemez." });
  }
  const origName = String(req.file.originalname || "dosya").replace(/[\u0000-\u001f\u007f<>]/g, "").slice(0, 200);
  const fileUrl = `${String(process.env.APP_URL || "").replace(/\/+$/, "")}/uploads/documents/${req.file.filename}`;
  let rows;
  try {
    ({ rows } = await db.query(
      "INSERT INTO documents (resource_type, resource_id, file_url, file_name, uploaded_by) VALUES ($1,$2,$3,$4,$5) RETURNING *",
      [resourceType, resourceId, fileUrl, origName, req.user.id]
    ));
  } catch (err) { removeFile(req.file); throw err; }
  logActivity(resourceType, resourceId, req.user.id, "dosya_eklendi", origName);
  res.status(201).json(signRow(rows[0], "file_url"));
});

router.delete("/:id", requireAuth, async (req, res) => {
  const doc = await db.query("SELECT resource_type, resource_id, file_url FROM documents WHERE id = $1", [req.params.id]);
  if (!doc.rows[0]) return res.status(404).json({ error: "Dosya bulunamadı." });
  if (!(await checkAccess(req, res, doc.rows[0].resource_type, doc.rows[0].resource_id))) return;
  await db.query("DELETE FROM documents WHERE id = $1", [req.params.id]);
  // Dosya diskten de silinir (yalnız documents klasörü içindeki, çözümlenmiş yol doğrulanarak)
  const rel = relFromStored(doc.rows[0].file_url);
  if (rel && rel.startsWith("documents/")) {
    const abs = path.resolve(UPLOAD_DIR, rel);
    if (abs.startsWith(path.resolve(DOCS_DIR) + path.sep)) { try { fs.unlinkSync(abs); } catch {} }
  }
  res.json({ message: "Silindi." });
});

module.exports = router;
