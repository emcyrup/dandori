// 送信箱（LINE・メール）を送り出す。PM2 が5分ごとに起動する（Supabase 版の pg_cron の代わり）。
const port = process.env.LISTEN_PORT || "8032";
const key = process.env.SERVICE_ROLE_KEY;
if (!key) { console.error("SERVICE_ROLE_KEY が空です"); process.exit(1); }

const r = await fetch(`http://127.0.0.1:${port}/functions/v1/send-outbox`, {
  method: "POST",
  headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
  body: "{}",
  signal: AbortSignal.timeout(120_000),
});
console.log(new Date().toISOString(), r.status, (await r.text()).slice(0, 300));
process.exit(r.ok ? 0 : 1);
