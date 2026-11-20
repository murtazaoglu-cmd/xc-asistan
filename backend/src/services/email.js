const nodemailer = require("nodemailer");
require("dotenv").config();

const { parseEmail } = require("./validate");

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT),
  secure: process.env.SMTP_SECURE === "true",
  // Takılı SMTP sunucusu isteği/işlemi sonsuza dek bekletmesin
  connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 20000,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

/** Müşteri girdisi e-posta HTML'ine kaçışlanarak girer (HTML/bağlantı enjeksiyonu engellenir) */
function esc(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function notifyAdminNewOffer(offer) {
  return transporter.sendMail({
    from: process.env.MAIL_FROM,
    to: process.env.MAIL_TO_ADMIN,
    subject: `Yeni Teklif Talebi — ${String(offer.name).replace(/[\r\n]+/g, " ")}`,
    html: `
      <h2>Yeni Teklif Talebi</h2>
      <p><b>Ad:</b> ${esc(offer.name)}<br/>
      <b>Telefon:</b> ${esc(offer.phone)}<br/>
      <b>E-posta:</b> ${esc(offer.email || "-")}<br/>
      <b>Hizmet:</b> ${esc(offer.service)}<br/>
      <b>Bölge:</b> ${esc(offer.region || "-")}<br/>
      <b>Mesaj:</b> ${esc(offer.message || "-")}</p>
      <p><a href="${process.env.APP_URL}/admin/offers/${offer.id}">Panelden Görüntüle</a></p>
    `,
  });
}

/**
 * Gönderimden hemen önce alıcıyı yeniden doğrular (savunma derinliği — intake doğrulamasından ÖNCE kaydedilmiş eski
 * kayıtlar olabilir) ve nodemailer'ın adres AYRIŞTIRICISINA hiç girmeyen nesne biçiminde verir (F-21).
 */
function safeRecipient(address) {
  const r = parseEmail(address);
  if (r.error || !r.value) {
    const err = new Error("Geçersiz alıcı e-posta adresi.");
    err.code = "EBADRCPT";
    throw err;
  }
  return { name: "", address: r.value };
}

async function sendQuoteToCustomer(offer, quote, pdfPath) {
  const to = safeRecipient(offer.email);
  return transporter.sendMail({
    from: process.env.MAIL_FROM,
    to,
    subject: "X Control Yapı — Teklifiniz Hazır",
    html: `
      <p>Sayın ${esc(offer.name)},</p>
      <p>${esc(offer.service)} için hazırladığımız teklif ekte PDF olarak yer almaktadır.</p>
      <p><b>Genel Toplam:</b> ${Number(quote.total).toLocaleString("tr-TR")} ₺</p>
      <p>Teklif durumunuzu şu linkten takip edebilirsiniz:<br/>
      <a href="${process.env.SITE_URL}/teklif-takip/${offer.tracking_code}">
        ${process.env.SITE_URL}/teklif-takip/${offer.tracking_code}
      </a></p>
      <p>Saygılarımızla,<br/>X Control Yapı</p>
    `,
    attachments: [
      { filename: `teklif-${offer.code}.pdf`, path: pdfPath },
    ],
  });
}

function scrubHost(t) {
  return t.replace(/\b\d{1,3}(\.\d{1,3}){3}\b/g, "[ip]").replace(/\b[\w-]+(\.[\w-]+)+\b/g, (m) => (/^\d+(\.\d+)*$/.test(m) ? m : "[sunucu]")).trim();
}

/** E-posta gönderim hatasını kullanıcıya gösterilebilir metne çevirir (SMTP parolası vb. sızmaz) */
function describeError(err) {
  if (!process.env.SMTP_HOST) return "E-posta (SMTP) yapılandırılmamış.";
  if (err && err.code === "EBADRCPT") return "Müşterinin e-posta adresi geçersiz; gönderilmedi.";
  if (err && (err.code === "EAUTH")) return "E-posta sunucusu kimlik doğrulamasını reddetti (SMTP kullanıcı/parola).";
  if (err && (err.code === "ECONNECTION" || err.code === "ECONNREFUSED" || err.code === "ETIMEDOUT" || err.code === "ESOCKET")) return "E-posta sunucusuna bağlanılamadı.";
  // SMTP yanıt metni sunucu adı/IP içerebilir; yalnız kod ve (alan adı/IP'siz) kısa metin gösterilir
  if (err && err.responseCode >= 500) return `E-posta sunucusu iletiyi reddetti (${err.responseCode}): ${scrubHost(String(err.response || "").replace(/^\d{3}[ -]*/, "")).slice(0, 100)}`.replace(/: $/, ".");
  return `E-posta gönderilemedi${err && err.code ? " (" + String(err.code).slice(0, 30) + ")" : ""}.`;
}

module.exports = { safeRecipient, transporter, notifyAdminNewOffer, sendQuoteToCustomer, describeError };
