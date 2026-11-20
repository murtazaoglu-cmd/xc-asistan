// PM2: API ve worker AYRI süreçlerdir. Başlat/güncelle: pm2 startOrReload ecosystem.config.js --update-env && pm2 save
// Worker yalnız 1 örnek olmalı (birden fazla çalışsa da SKIP LOCKED ile iş çift çalışmaz, ama gereksiz).
module.exports = {
  apps: [
    {
      name: "xcontrol-api",
      script: "src/server.js",
      cwd: __dirname, // .env bu klasörden okunur (pm2 hangi dizinden çağrılırsa çağrılsın)
      instances: 1,
      exec_mode: "fork",
      max_memory_restart: "400M",
      env: { NODE_ENV: "production" },
    },
    {
      name: "xcontrol-worker",
      script: "src/worker.js",
      cwd: __dirname,
      instances: 1,
      exec_mode: "fork",
      kill_timeout: 15000, // SIGTERM: çalışan tick bitsin
      max_memory_restart: "300M",
      env: { NODE_ENV: "production" },
    },
  ],
};
