const express = require("express");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const db = require("../db");
const crypto = require("crypto");
const { requireAuth, requireRole } = require("../middleware/auth");
const { UPLOAD_DIR: SAFE_UPLOAD_DIR, signRow, contentMatchesExt, IMAGE_EXTENSIONS } = require("../services/fileAccess");

const router = express.Router();

const UPLOAD_DIR = SAFE_UPLOAD_DIR;
const GALLERY_DIR = path.join(UPLOAD_DIR, "gallery");
if (!fs.existsSync(GALLERY_DIR)) fs.mkdirSync(GALLERY_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, GALLERY_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `${Date.now()}-${crypto.randomBytes(6).toString("hex")}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 8 * 1024 * 1024 }, // 8MB
  fileFilter: (req, file, cb) => {
    // allowlist: svg/html gibi betik taşıyabilen "image/*" türleri kabul edilmez; içerik ayrıca ilk baytlardan doğrulanır
    if (!IMAGE_EXTENSIONS.includes(path.extname(file.originalname).toLowerCase())) return cb(Object.assign(new Error("Sadece görsel dosyaları yüklenebilir (jpg, png, webp, gif, heic)."), { status: 400 }));
    cb(null, true);
  },
});

/** Bir projeye ait tüm fotoğraflar */
router.get("/project/:projectId", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  const { rows } = await db.query(
    "SELECT * FROM gallery WHERE project_id = $1 ORDER BY created_at DESC",
    [req.params.projectId]
  );
  res.json(rows.map((r) => signRow(r, "image_url"))); // yayınlanmamış görseller için kısa ömürlü imzalı bağlantı
});

/** Fotoğraf yükle (proje bazlı, öncesi/sonrası etiketiyle) */
router.post("/project/:projectId", requireAuth, requireRole("admin", "muhasebe"), async (req, res, next) => {
  // proje yoksa dosya diske hiç yazılmaz
  const pr = await db.query("SELECT 1 FROM projects WHERE id = $1", [req.params.projectId]);
  if (!pr.rows[0]) return res.status(404).json({ error: "Proje bulunamadı." });
  next();
}, upload.single("photo"), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: "Dosya bulunamadı." });
  if (!contentMatchesExt(req.file.path, path.extname(req.file.filename).toLowerCase())) {
    try { fs.unlinkSync(req.file.path); } catch {}
    return res.status(400).json({ error: "Dosya içeriği geçerli bir görsel değil." });
  }
  const { category, before_after, published } = req.body;
  if (before_after && !["before", "after"].includes(before_after)) { try { fs.unlinkSync(req.file.path); } catch {} return res.status(400).json({ error: "before_after before veya after olmalıdır." }); }
  const imageUrl = `${String(process.env.APP_URL || "").replace(/\/+$/, "")}/uploads/gallery/${req.file.filename}`;

  let rows;
  try {
    ({ rows } = await db.query(
      `INSERT INTO gallery (project_id, image_url, category, before_after, published)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [req.params.projectId, imageUrl, category ? String(category).slice(0, 60) : null, before_after || null, published === "true"]
    ));
  } catch (err) { try { fs.unlinkSync(req.file.path); } catch {} throw err; }
  res.status(201).json(signRow(rows[0], "image_url"));
});

/** Fotoğrafın yayın durumunu değiştir (sitede gösterilsin mi) */
router.patch("/:id", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  const { published } = req.body;
  const { rows } = await db.query(
    "UPDATE gallery SET published = $1 WHERE id = $2 RETURNING *",
    [!!published, req.params.id]
  );
  if (!rows[0]) return res.status(404).json({ error: "Fotoğraf bulunamadı." });
  res.json(signRow(rows[0], "image_url"));
});

router.delete("/:id", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  const { rows } = await db.query("SELECT * FROM gallery WHERE id = $1", [req.params.id]);
  if (rows[0]) {
    const filename = path.basename(rows[0].image_url.split("?")[0]);
    const filePath = path.join(GALLERY_DIR, filename);
    try { fs.unlinkSync(filePath); } catch {} // sessizce dene, dosya yoksa önemli değil
  }
  await db.query("DELETE FROM gallery WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

/** PUBLIC — Sitede gösterilecek yayınlanmış fotoğraflar */
router.get("/published", async (req, res) => {
  const { rows } = await db.query(`
    SELECT g.id, g.image_url, g.category, g.before_after, p.service
    FROM gallery g JOIN projects p ON p.id = g.project_id
    WHERE g.published = true ORDER BY g.created_at DESC LIMIT 24
  `);
  res.json(rows);
});

module.exports = router;
