const jwt = require("jsonwebtoken");

/**
 * Jeton ömrü: web paneli JWT_EXPIRES_IN (varsayılan 7d); mobil uygulama ("client":"mobile" ya da
 * "X-Client: mobile" başlığı) JWT_EXPIRES_IN_MOBILE (varsayılan 30d). Mobil, uygulama her açıldığında
 * POST /auth/refresh ile süreyi yeniler (kayan oturum); iptal için token_version kullanılır.
 */
function issueToken(user, client) {
  const mobile = client === "mobile";
  const token = jwt.sign(
    { id: user.id, name: user.name, role: user.role, tv: user.token_version || 0, cl: mobile ? "mobile" : "web" },
    process.env.JWT_SECRET,
    { algorithm: "HS256", expiresIn: mobile ? (process.env.JWT_EXPIRES_IN_MOBILE || "30d") : (process.env.JWT_EXPIRES_IN || "7d") }
  );
  const { exp } = jwt.decode(token);
  return {
    token,
    tokenType: "Bearer",
    expiresAt: new Date(exp * 1000).toISOString(),
    expiresIn: exp - Math.floor(Date.now() / 1000),
  };
}

module.exports = { issueToken };
