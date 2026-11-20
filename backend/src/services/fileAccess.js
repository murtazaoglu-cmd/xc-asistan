const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const express = require("express");
const db = require("../db");
const { authenticate } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");

/**
 * /uploads erişim denetimi (v16).
 *  - İmzalı bağlantı:  /uploads/<yol>?exp=<unix>&sig=<HMAC>  — varsayılan 10 dk; <img>/<a> ile kullanılır, başlık gerekmez.
 *  - Authorization başlığı: kaydın sahibi/paylaşılan kişi/admin-muhasebe dosyayı doğrudan (Bearer ile) çekebilir.
 *  - Yayınlanmış galeri görselleri herkese açıktır (web sitesi için); diğer her şey kimlik ister.
 * İmza anahtarı: UPLOAD_SIGN_SECRET (yoksa JWT_SECRET'ten türetilir). İmza yola ve süreye bağlıdır.
 */
const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, "../../uploads"));
const TTL_SEC = Math.min(Math.max(Number(process.env.UPLOAD_URL_TTL_SEC) || 600, 30), 86400);
const INLINE_EXT = new Set([".pdf", ".png", ".jpg", ".jpeg", ".webp", ".gif"]);

function key() {
  return process.env.UPLOAD_SIGN_SECRET || crypto.createHmac("sha256", String(process.env.JWT_SECRET)).update("xc-upload-url-v1").digest();
}
function sign(rel, exp) {
  return crypto.createHmac("sha256", key()).update(`${rel}\n${exp}`).digest("base64url");
}
function verify(rel, exp, sig) {
  const e = Number(exp);
  if (!Number.isInteger(e) || e < Math.floor(Date.now() / 1000) || typeof sig !== "string" || sig.length > 100) return false;
  const a = Buffer.from(sign(rel, e)), b = Buffer.from(sig);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** "…/uploads/documents/x.pdf" (saklanan mutlak URL) → "documents/x.pdf" */
function relFromStored(url) {
  const m = /\/uploads\/([^?#]+)/.exec(String(url || ""));
  if (!m) return null;
  try { return decodeURIComponent(m[1]); } catch { return null; }
}
const base = () => String(process.env.APP_URL || "").replace(/\/+$/, "");

/** Göreli yol için kısa ömürlü imzalı mutlak bağlantı */
function signedUrl(rel, ttl = TTL_SEC) {
  const exp = Math.floor(Date.now() / 1000) + ttl;
  return `${base()}/uploads/${rel.split("/").map(encodeURIComponent).join("/")}?exp=${exp}&sig=${sign(rel, exp)}`;
}
/** Veritabanında saklanan (imzasız) URL'yi imzalı URL'ye çevirir; tanınmazsa olduğu gibi döner */
function signStored(url, ttl) {
  const rel = relFromStored(url);
  return rel ? signedUrl(rel, ttl) : url;
}
function signRow(row, field) {
  return row ? { ...row, [field]: signStored(row[field]) } : row;
}

/** İlk bayt imzalarıyla (magic bytes) dosya içeriğinin uzantıyla uyumunu denetler */
const ZIP = (b) => b[0] === 0x50 && b[1] === 0x4b && (b[2] === 3 || b[2] === 5);
const OLE = (b) => b.length >= 8 && b[0] === 0xd0 && b[1] === 0xcf && b[2] === 0x11 && b[3] === 0xe0;
const FTYP = (b) => b.length >= 12 && b.slice(4, 8).toString("latin1") === "ftyp";
const MAGIC = {
  ".pdf": (b) => b.slice(0, 1024).toString("latin1").includes("%PDF-"),
  ".png": (b) => b.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  ".jpg": (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  ".jpeg": (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  ".gif": (b) => /^GIF8[79]a/.test(b.slice(0, 6).toString("latin1")),
  ".webp": (b) => b.slice(0, 4).toString("latin1") === "RIFF" && b.slice(8, 12).toString("latin1") === "WEBP",
  ".heic": FTYP, ".heif": FTYP, ".mp4": FTYP, ".mov": FTYP,
  ".docx": ZIP, ".xlsx": ZIP, ".pptx": ZIP, ".odt": ZIP, ".ods": ZIP, ".zip": ZIP,
  ".doc": OLE, ".xls": OLE, ".ppt": OLE,
  ".rtf": (b) => b.slice(0, 5).toString("latin1") === "{\\rtf",
  ".dwg": (b) => /^AC10\d\d/.test(b.slice(0, 6).toString("latin1")),
  ".txt": (b) => isPlainText(b), ".csv": (b) => isPlainText(b), ".dxf": (b) => isPlainText(b),
};
function isPlainText(b) {
  if (b.includes(0)) return false;
  const head = b.slice(0, 2048).toString("utf8").trimStart().toLowerCase();
  return !/^(<!doctype|<html|<\?xml|<svg|<script|<body|<head|<iframe|<\?php|%pdf)/.test(head);
}
/** Yüklenen dosya uzantısına uygun içerik mi? (Bilinmeyen uzantı → false) */
function contentMatchesExt(filePath, ext) {
  const check = MAGIC[ext];
  if (!check) return false;
  let fd;
  try {
    fd = fs.openSync(filePath, "r");
    const buf = Buffer.alloc(4096);
    const n = fs.readSync(fd, buf, 0, buf.length, 0);
    if (n === 0) return false;
    return !!check(buf.slice(0, n));
  } catch { return false; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch {} }
}
const DOC_EXTENSIONS = Object.keys(MAGIC);
const IMAGE_EXTENSIONS = [".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic", ".heif"];

/** Kaynağa (offer/project) erişim — documents/shares ile aynı kural */
async function userCanAccess(user, type, id) {
  const table = type === "offer" ? "offers" : "projects";
  const { rows } = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [id]);
  if (!rows[0]) return false;
  return canAccessResource(user, type, id, rows[0].owner_id);
}

/** Authorization başlığı ile istenen dosya için yetki kararı: "ok" | "forbidden" | "notfound" */
async function authorizeBearer(user, rel) {
  const staff = user.role === "admin" || user.role === "muhasebe";
  const file = rel.split("/").pop();
  if (rel.startsWith("documents/")) {
    const { rows } = await db.query("SELECT resource_type, resource_id FROM documents WHERE substring(file_url from '[^/?]+$') = $1 LIMIT 1", [file]);
    if (!rows[0]) return staff ? "ok" : "notfound";
    return (await userCanAccess(user, rows[0].resource_type, rows[0].resource_id)) ? "ok" : "forbidden";
  }
  if (rel.startsWith("invoices/")) { // v18: fatura ekleri — yalnız ilgili defterin sahibi (muhasebe → işletme defteri) ya da admin
    const { rows } = await db.query("SELECT i.owner_id FROM invoice_files f JOIN invoices i ON i.id = f.invoice_id WHERE substring(f.file_url from '[^/?]+$') = $1 LIMIT 1", [file]);
    if (!rows[0]) return staff ? "ok" : "notfound";
    if (user.role === "admin") return "ok";
    const { financeOwnerId } = require("../middleware/access");
    return String(rows[0].owner_id) === String(await financeOwnerId(user)) ? "ok" : "forbidden";
  }
  if (rel.startsWith("gallery/")) return staff ? "ok" : "forbidden";
  const m = /^teklif-(.+)-\d+\.pdf$/.exec(file); // teklif PDF'leri: teklif-OFR-12-<zaman>.pdf
  if (m) {
    const { rows } = await db.query("SELECT id, owner_id FROM offers WHERE code = $1", [m[1]]);
    if (!rows[0]) return staff ? "ok" : "notfound";
    return (await canAccessResource(user, "offer", rows[0].id, rows[0].owner_id)) ? "ok" : "forbidden";
  }
  return staff ? "ok" : "forbidden";
}

async function isPublishedGalleryFile(rel) {
  if (!rel.startsWith("gallery/")) return false;
  const { rows } = await db.query("SELECT 1 FROM gallery WHERE published = true AND substring(image_url from '[^/?]+$') = $1 LIMIT 1", [rel.split("/").pop()]);
  return rows.length > 0;
}

/** /uploads için Express katmanı: yetki denetimi + güvenli statik servis */
function uploadsMiddleware() {
  const statik = express.static(UPLOAD_DIR, {
    index: false, redirect: false, dotfiles: "ignore", fallthrough: true,
    setHeaders(res, filePath) {
      const ext = path.extname(filePath).toLowerCase();
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Cache-Control", res.getHeader("X-Public-File") ? "public, max-age=3600" : "private, max-age=60");
      res.removeHeader("X-Public-File");
      if (!INLINE_EXT.has(ext)) res.setHeader("Content-Disposition", `attachment; filename="${path.basename(filePath).replace(/[^\w.\-]/g, "_")}"`);
    },
  });
  return async (req, res, next) => {
    if (req.method !== "GET" && req.method !== "HEAD") return res.status(405).json({ error: "İzin verilmeyen yöntem." });
    let rel;
    try { rel = decodeURIComponent(req.path.replace(/^\/+/, "")); } catch { return res.status(400).json({ error: "Geçersiz adres." }); }
    const parts = rel.split("/");
    if (!rel || rel.includes("\0") || rel.includes("\\") || parts.length > 2 || parts.some((p) => !p || p === "." || p === ".." || p.startsWith("."))) {
      return res.status(404).json({ error: "Dosya bulunamadı." });
    }
    const abs = path.resolve(UPLOAD_DIR, rel);
    if (!abs.startsWith(UPLOAD_DIR + path.sep)) return res.status(404).json({ error: "Dosya bulunamadı." });

    let allowed = false;
    if (req.query.sig !== undefined && verify(rel, req.query.exp, req.query.sig)) allowed = true;
    else if (await isPublishedGalleryFile(rel)) { allowed = true; res.setHeader("X-Public-File", "1"); }
    else if (req.headers.authorization) {
      const r = await authenticate(req.headers.authorization);
      if (!r.user) return res.status(401).json({ error: "Geçersiz veya süresi dolmuş oturum." });
      const verdict = await authorizeBearer(r.user, rel);
      if (verdict === "forbidden") return res.status(403).json({ error: "Bu dosyaya erişiminiz yok." });
      if (verdict === "notfound") return res.status(404).json({ error: "Dosya bulunamadı." });
      allowed = true;
    }
    if (!allowed) return res.status(401).json({ error: "Dosyaya erişim için oturum açın veya geçerli (süresi dolmamış) imzalı bağlantı kullanın." });
    req.url = "/" + parts.map(encodeURIComponent).join("/");
    statik(req, res, () => { res.removeHeader("X-Public-File"); res.status(404).json({ error: "Dosya bulunamadı." }); });
  };
}

module.exports = { UPLOAD_DIR, TTL_SEC, signedUrl, signStored, signRow, relFromStored, contentMatchesExt, DOC_EXTENSIONS, IMAGE_EXTENSIONS, uploadsMiddleware, userCanAccess, verify, sign };
