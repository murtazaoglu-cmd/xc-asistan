const express = require("express");
const multer = require("multer");
const rateLimit = require("express-rate-limit");
const { requireAuth, requireRole } = require("../middleware/auth");
const imp = require("../assistant/importer/service");
const store = require("../assistant/importer/store");
const consent = require("../assistant/importer/consent");

/**
 * Yazışma içe aktarma + öneriler + notlar + rıza kayıtları (v19) — /api/assistant altında.
 * Roller: admin, muhasebe, ortak, personel (saha: yok). Yükleme güvenliği: yalnız .txt/.zip (uzantı + imza), boyut sınırı,
 * zip bombası/yol geçişi savunması (zipReader), dosya DİSKE YAZILMAZ (bellekte işlenir), kullanıcı başına hız sınırı.
 */
const router = express.Router();
const ROLES = ["admin", "muhasebe", "ortak", "personel"];
const guard = [requireAuth, requireRole(...ROLES)];

const MAX_MB = Math.min(Math.max(Number(process.env.IMPORT_MAX_UPLOAD_MB) || 25, 1), 100);
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_MB * 1024 * 1024, files: 1, fields: 20, fieldSize: 20 * 1024, parts: 30 },
  fileFilter: (req, file, cb) => {
    if (file.fieldname !== "file") return cb(Object.assign(new multer.MulterError("LIMIT_UNEXPECTED_FILE", file.fieldname)));
    cb(null, true);
  },
}).single("file");

const importLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: Number(process.env.IMPORT_RATE_MAX) || 20,
  keyGenerator: (req) => (req.user && req.user.id) || "anon", validate: false,
  message: { error: "Çok fazla içe aktarma denemesi. Lütfen biraz sonra tekrar deneyin." },
});

function wrap(fn) {
  return async (req, res) => {
    try { await fn(req, res); }
    catch (err) {
      if (err && err.expose && err.status) return res.status(err.status).json({ error: err.message, ...(err.extra || {}) });
      throw err;
    }
  };
}
const bodyOf = (req) => (req.body && typeof req.body === "object" ? req.body : {});

// ---- aydınlatma metni
router.get("/imports/consent-notice", ...guard, (req, res) => res.json(consent.NOTICE));

// ---- yükleme → önizleme (multipart: file + alanlar) ya da JSON {text, source:'share'|…} (paylaş / pano)
router.post("/imports", ...guard, importLimiter, (req, res, next) => {
  if (req.is("multipart/form-data")) return upload(req, res, next);
  next();
}, wrap(async (req, res) => {
  const f = bodyOf(req);
  let out;
  if (req.file) out = await imp.createPreview(req, { buf: req.file.buffer, filename: req.file.originalname, source: f.source, fields: f });
  else if (typeof f.text === "string") out = await imp.createPreview(req, { text: f.text, source: f.source || "share", fields: f });
  else throw Object.assign(new Error("Dosya (file) ya da metin (text) gerekli."), { status: 400, expose: true });
  res.status(201).json(out);
}));

router.get("/imports", ...guard, wrap(async (req, res) => res.json({ items: await imp.listImports(req.user, req.query.limit) })));
router.get("/imports/:id", ...guard, wrap(async (req, res) => res.json(await imp.getImport(req.user, uuid(req.params.id)))));
router.post("/imports/:id/confirm", ...guard, wrap(async (req, res) => {
  const r = await imp.confirmImport(req, uuid(req.params.id), bodyOf(req));
  res.status(r.already ? 200 : 201).json(r);
}));
router.delete("/imports/:id", ...guard, wrap(async (req, res) => res.json(await imp.deleteImport(req, uuid(req.params.id), { keepNotes: req.query.keep_notes === "1" || req.query.keep_notes === "true" }))));

function uuid(v) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v))) throw Object.assign(new Error("Geçersiz kimlik."), { status: 400, expose: true });
  return v;
}

// ---- yazışmalar
router.get("/conversations", ...guard, wrap(async (req, res) => res.json({ items: await store.listConversations(req.user, { customerKey: req.query.customer_key, limit: req.query.limit, offset: req.query.offset }) })));
router.get("/conversations/:id", ...guard, wrap(async (req, res) => res.json(await store.getConversation(req.user, uuid(req.params.id)))));
router.get("/conversations/:id/messages", ...guard, wrap(async (req, res) => res.json(await store.listMessages(req.user, uuid(req.params.id), req.query))));
router.patch("/conversations/:id", ...guard, wrap(async (req, res) => res.json(await store.patchConversation(req, uuid(req.params.id), bodyOf(req)))));
router.delete("/conversations/:id", ...guard, wrap(async (req, res) => res.json(await store.deleteConversation(req, uuid(req.params.id)))));

// ---- öneriler
router.get("/suggestions", ...guard, wrap(async (req, res) => res.json({ items: await store.listSuggestions(req.user, req.query) })));
router.patch("/suggestions/:id", ...guard, wrap(async (req, res) => res.json(await store.decideSuggestion(req, uuid(req.params.id), bodyOf(req)))));

// ---- notlar
router.get("/notes", ...guard, wrap(async (req, res) => res.json({ items: await store.listNotes(req.user, { customerKey: req.query.customer_key, conversationId: req.query.conversation_id, q: req.query.q, limit: req.query.limit, offset: req.query.offset }) })));
router.post("/notes", ...guard, wrap(async (req, res) => res.status(201).json(await store.createNote(req, bodyOf(req)))));
router.patch("/notes/:id", ...guard, wrap(async (req, res) => res.json(await store.patchNote(req, uuid(req.params.id), bodyOf(req)))));
router.delete("/notes/:id", ...guard, wrap(async (req, res) => res.json(await store.deleteNote(req, uuid(req.params.id)))));

// ---- müşteri kartı (telefon anahtarı: rakamlar; erişim müşteri havuzu kapsamıyla)
router.get("/customers/:key/summary", ...guard, wrap(async (req, res) => res.json(await store.customerSummary(req.user, req.params.key))));
router.get("/customers/:key/conversations", ...guard, wrap(async (req, res) => res.json({ items: await store.listConversations(req.user, { customerKey: req.params.key, limit: req.query.limit, offset: req.query.offset }) })));
router.get("/customers/:key/notes", ...guard, wrap(async (req, res) => res.json({ items: await store.listNotes(req.user, { customerKey: req.params.key, limit: req.query.limit, offset: req.query.offset }) })));
router.delete("/customers/:key/data", ...guard, wrap(async (req, res) => res.json(await store.deleteCustomerData(req, req.params.key))));

// ---- rıza / aydınlatma kayıtları
router.get("/consents", ...guard, wrap(async (req, res) => res.json({ items: await store.listConsents(req.user, req.query) })));
router.post("/consents", ...guard, wrap(async (req, res) => res.status(201).json(await store.createConsent(req, bodyOf(req)))));
router.post("/consents/:id/withdraw", ...guard, wrap(async (req, res) => res.json(await store.withdrawConsent(req, uuid(req.params.id)))));

module.exports = router;
