require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const { authenticate } = require("./middleware/auth");
const { uploadsMiddleware } = require("./services/fileAccess");
const { logRequestError } = require("./services/logging");

// Express 4, async route hatalarını kendiliğinden yakalamaz (istek askıda kalır). Bu yama, async
// handler'dan dönen reddedilmiş Promise'i otomatik olarak hata yakalayıcıya (next) iletir.
const Layer = require("express/lib/router/layer");
const origHandleRequest = Layer.prototype.handle_request;
Layer.prototype.handle_request = function (req, res, next) {
  const fn = this.handle;
  if (fn.length > 3) return next();
  try {
    const result = fn(req, res, next);
    if (result && typeof result.catch === "function") result.catch(next);
  } catch (err) {
    next(err);
  }
};
void origHandleRequest;

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 16) {
  console.error("JWT_SECRET tanımlı değil veya çok kısa (en az 16 karakter). Sunucu başlatılmadı.");
  process.exit(1);
}
if (process.env.JWT_SECRET.length < 32) {
  // Geriye uyum için varsayılan olarak başlatmayı engellemez; JWT_SECRET_STRICT=true ile 32 karakter ZORUNLU olur (HS256: openssl rand -hex 32).
  if (process.env.JWT_SECRET_STRICT === "true") { console.error("JWT_SECRET en az 32 karakter olmalı (JWT_SECRET_STRICT=true). Sunucu başlatılmadı."); process.exit(1); }
  console.warn("UYARI: JWT_SECRET 32 karakterden kısa. `openssl rand -hex 32` ile yeni bir anahtar üretin (değişince açık oturumlar sona erer).");
}

const authRoutes = require("./routes/auth");
const offerRoutes = require("./routes/offers");
const quoteRoutes = require("./routes/quotes");
const projectRoutes = require("./routes/projects");
const reportRoutes = require("./routes/reports");
const trackRoutes = require("./routes/track");
const pushRoutes = require("./routes/push");
const expenseRoutes = require("./routes/expenses");
const appointmentRoutes = require("./routes/appointments");
const customerRoutes = require("./routes/customers");
const reminderRoutes = require("./routes/reminders");
const userRoutes = require("./routes/users");
const galleryRoutes = require("./routes/gallery");
const quoteTemplateRoutes = require("./routes/quoteTemplates");
const materialRoutes = require("./routes/materials");
const dashboardInitRoutes = require("./routes/dashboardInit");
const shareRoutes = require("./routes/shares");
const activityRoutes = require("./routes/activity");
const documentRoutes = require("./routes/documents");
const recurringExpenseRoutes = require("./routes/recurringExpenses");
const mobileRoutes = require("./routes/mobile");
const configRoutes = require("./routes/config");
const assistantRoutes = require("./routes/assistant");
const assistantManagerRoutes = require("./routes/assistantManager"); // v20: müdür, brifing, kapanış
const healthRoutes = require("./routes/health");
const bookkeepingRoutes = require("./routes/bookkeeping"); // v18: fatura takibi, KDV, vergi takvimi, tahsilat planı, mesaj şablonları
const assistantCommandRoutes = require("./routes/assistantCommands");
const assistantImportRoutes = require("./routes/assistantImports");
const idempotency = require("./middleware/idempotency");

const app = express();
app.disable("x-powered-by");

// Yakalanmamış hataları logla — bir route'ta try/catch unutulursa istek sessizce
// askıda kalmak yerine en azından PM2 loglarında görünür.
process.on("unhandledRejection", (err) => {
  console.error("YAKALANMAMIŞ PROMISE HATASI:", require("./services/logging").describeErrorForLog(err));
});

// Ters proxy (nginx/Apache; varsa önünde Cloudflare) arkasında gerçek istemci IP'si için güvenilir proxy SAYISI.
// TRUST_PROXY: 0/false (proxy yok — doğrudan erişim), 1 (varsayılan: yalnız nginx/Apache), 2 (Cloudflare + nginx), "loopback" veya CIDR listesi.
// Yanlış ayar hız sınırını etkisiz kılar: sayı gerçek proxy sayısından büyükse istemci X-Forwarded-For'u taklit edebilir.
function parseTrustProxy(v) {
  if (v === undefined || v === "") return 1;
  if (v === "false" || v === "0") return false;
  if (v === "true") { console.warn("UYARI: TRUST_PROXY=true güvensizdir; 1 olarak kullanılıyor (proxy sayısını yazın)."); return 1; }
  if (/^\d+$/.test(v)) return Number(v);
  return v;
}
app.set("trust proxy", parseTrustProxy(process.env.TRUST_PROXY));

// /api/v1 takma yolu (v17): /api/v1/... istekleri /api/... ile AYNI router'lara gider; eski /api yolu aynen çalışır.
app.use((req, res, next) => {
  if (req.url === "/api/v1" || req.url.startsWith("/api/v1/") || req.url.startsWith("/api/v1?")) req.url = "/api" + req.url.slice("/api/v1".length);
  next();
});

// Güvenlik başlıkları: Helmet varsayılanları (CSP script-src 'self', nosniff, HSTS...) + sıkı Referrer-Policy.
// Panel başka bir alt alan adından (panel.controlx.com.tr) PDF/görsel gösterebilsin diye CORP cross-origin.
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" },
  referrerPolicy: { policy: "no-referrer" },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));
// CORS: CORS_ORIGINS="https://panel.controlx.com.tr,https://controlx.com.tr" verilirse yalnız bu kökenler; verilmezse (geriye uyum) her köken
// yansıtılır — jeton Authorization başlığıyla taşındığı (çerez yok) için CSRF riski sınırlıdır ama üretimde CORS_ORIGINS tanımlayın.
const corsOrigins = String(process.env.CORS_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
if (process.env.NODE_ENV === "production" && corsOrigins.length === 0) console.warn("UYARI: CORS_ORIGINS tanımlı değil; tüm kökenlere izin veriliyor.");
app.use(cors({ origin: corsOrigins.length ? corsOrigins : true, exposedHeaders: ["X-Total-Count", "Idempotent-Replay"], maxAge: 600 }));
// Gövde sınırları: herkese açık uçlar küçük tutulur (varsayılan 5 MB yalnız oturumlu uçlar için)
app.use("/api/offers", express.json({ limit: "100kb" }));
app.use("/api/auth", express.json({ limit: "20kb" }));
app.use("/api/track", express.json({ limit: "20kb" }));
app.use(express.json({ limit: "5mb" }));

// Yüklenen dosyalar: imzalı bağlantı (10 dk) veya Authorization başlığı ile; yalnız yayınlanmış galeri görselleri herkese açık
app.use("/uploads", uploadsMiddleware());

// Anonim teklif formuna karşı kötüye kullanımı sınırla (15 dk'da en fazla 20 gönderim/IP).
// Geçerli bir oturum jetonu olan panel kullanıcıları ve okuma (GET) istekleri sınırlanmaz.
// "Geçerli" = imza + süre + kullanıcı hâlâ var + token_version güncel (silinmiş/iptal edilmiş jeton hız sınırını atlatamaz)
async function hasValidToken(req) {
  return !!(await authenticate(req.headers.authorization)).user;
}
const publicOfferLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 20,
  skip: async (req) => req.method !== "POST" || (await hasValidToken(req)),
  message: { error: "Çok fazla istek. Lütfen biraz sonra tekrar deneyin." },
});
const trackLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 60,
  message: { error: "Çok fazla istek. Lütfen biraz sonra tekrar deneyin." },
});
// Kaba kuvvet şifre denemelerine karşı: başarısız girişler 15 dk'da 10 ile sınırlı
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 10, skipSuccessfulRequests: true,
  message: { error: "Çok fazla hatalı giriş denemesi. 15 dakika sonra tekrar deneyin." },
});
// Genel API sınırı (IP başına 15 dk'da RATE_LIMIT_API_MAX, varsayılan 3000; 0 = kapalı) — kontrolsüz otomasyonu/kaba taramayı keser
const apiMax = process.env.RATE_LIMIT_API_MAX === undefined ? 3000 : Number(process.env.RATE_LIMIT_API_MAX);
if (apiMax > 0) {
  app.use("/api", rateLimit({
    windowMs: 15 * 60 * 1000, max: apiMax, skip: (req) => req.path === "/health",
    message: { error: "Çok fazla istek. Lütfen biraz sonra tekrar deneyin." },
  }));
}
app.use("/api/offers", publicOfferLimiter);
app.use("/api/track", trackLimiter);
app.use("/api/auth/login", loginLimiter);

app.get("/api/health", (req, res) => res.json({ status: "ok", time: new Date().toISOString() }));

// Opsiyonel Idempotency-Key (yalnız POST; başlık yoksa etkisiz) — gövde ayrıştırıcılardan sonra, route'lardan önce
app.use("/api", idempotency);

app.use("/api/auth", authRoutes);
app.use("/api/offers", offerRoutes);
app.use("/api/quotes", quoteRoutes);
app.use("/api/projects", projectRoutes);
app.use("/api/reports", reportRoutes);
app.use("/api/track", trackRoutes);
app.use("/api/push", pushRoutes);
app.use("/api/expenses", expenseRoutes);
app.use("/api/appointments", appointmentRoutes);
app.use("/api/customers", customerRoutes);
app.use("/api/reminders", reminderRoutes);
app.use("/api/users", userRoutes);
app.use("/api/gallery", galleryRoutes);
app.use("/api/quote-templates", quoteTemplateRoutes);
app.use("/api/materials", materialRoutes);
app.use("/api/dashboard-init", dashboardInitRoutes);
app.use("/api/shares", shareRoutes);
app.use("/api/activity", activityRoutes);
app.use("/api/documents", documentRoutes);
app.use("/api/recurring-expenses", recurringExpenseRoutes);
app.use("/api/mobile", mobileRoutes);
app.use("/api/config", configRoutes);
app.use("/api/assistant", assistantRoutes);
app.use("/api/assistant", assistantManagerRoutes); // v20: brifing, kapanış, insight, hatırlatma ek uçları
app.use("/api/assistant", assistantCommandRoutes); // v19: komut çubuğu + onay kartları
app.use("/api/assistant", assistantImportRoutes); // v19: yazışma içe aktarma, öneriler, notlar
app.use("/api/health", healthRoutes);
app.use("/api", bookkeepingRoutes); // /invoices, /vat, /tax-calendar, /payment-schedule, /receivables, /message-templates

app.use((req, res) => res.status(404).json({ error: "Uç nokta bulunamadı." }));

app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  // Doğrulama ve veritabanı kısıt hatalarını anlaşılır HTTP kodlarına çevir (iç ayrıntı sızdırmadan)
  if (err.type === "entity.parse.failed") return res.status(400).json({ error: "Geçersiz JSON gövdesi." });
  if (err.type === "entity.too.large") return res.status(413).json({ error: "İstek çok büyük." });
  if (err.type === "charset.unsupported" || err.type === "encoding.unsupported") return res.status(415).json({ error: "Desteklenmeyen içerik kodlaması." });
  if (err.name === "MulterError") {
    const msg = { LIMIT_FILE_SIZE: "Dosya çok büyük.", LIMIT_FILE_COUNT: "Tek seferde en çok 1 dosya yüklenebilir.", LIMIT_UNEXPECTED_FILE: "Beklenmeyen dosya alanı." }[err.code];
    return res.status(err.code === "LIMIT_FILE_SIZE" ? 413 : 400).json({ error: msg || "Dosya yüklenemedi." });
  }
  // Bozuk multipart gövdesi (busboy düz Error fırlatır: "Malformed part header", "Unexpected end of form"…) → 500 değil 400
  if (/^(Malformed part header|Malformed urlencoded|Unexpected end of form|Multipart: |Missing Content-Type|Boundary not found|Unsupported content-type)/i.test(err.message || "")) return res.status(400).json({ error: "Geçersiz çok parçalı (multipart) istek." });
  if (/yüklenemez/.test(err.message || "")) return res.status(400).json({ error: err.message });
  if (err.status && err.status < 500) return res.status(err.status).json({ error: err.expose === false ? "Geçersiz istek." : err.message });
  switch (err.code) {
    case "23505": return res.status(409).json({ error: "Bu kayıt zaten mevcut." });
    case "23503": return res.status(409).json({ error: "Bu kayıt başka kayıtlarla ilişkili olduğu için işlem yapılamadı." });
    case "23514":
    case "23502":
    case "22P02":
    case "22003": return res.status(400).json({ error: "Geçersiz veya eksik değer girildi." });
  }
  logRequestError(req, err); // sorgu dizesi/imza/DB değerleri olmadan
  res.status(500).json({ error: "Sunucu hatası." });
});

const PORT = process.env.PORT || 4000;
// HOST=127.0.0.1 → yalnız yerel ters proxy erişebilir (önerilen). Verilmezse tüm arayüzlerde dinler (eski davranış).
const HOST = process.env.HOST || undefined;
app.listen(PORT, HOST, () => {
  console.log(`X Control Yapı API çalışıyor → http://${HOST || "localhost"}:${PORT}`);
});
