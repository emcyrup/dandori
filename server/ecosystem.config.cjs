// ============================================================================
//  ナイトだんどり / PM2 の定義（どのプロセスを、どう動かすか）
//    ./node_modules/.bin/pm2 start ecosystem.config.cjs
//  設定はすべて .env から読みます。
// ============================================================================
const fs = require("node:fs");
const path = require("node:path");

const HERE = __dirname;
const ROOT = path.resolve(HERE, "..");
const env = {};
for (const line of fs.readFileSync(path.join(HERE, ".env"), "utf8").split("\n")) {
  const m = /^\s*([A-Z0-9_]+)\s*=(.*)$/.exec(line);
  if (m) env[m[1]] = m[2].trim().replace(/^"(.*)"$/, "$1");
}
const need = (k) => { if (!env[k]) throw new Error(`.env の ${k} が空です（./setup.sh を実行してください）`); return env[k]; };

const DB = (user, pw) => `postgres://${user}:${encodeURIComponent(pw)}@${env.DB_HOST || "127.0.0.1"}:${env.DB_PORT || 5432}/${need("DB_NAME")}?sslmode=${env.DB_SSLMODE || "prefer"}`;
const SITE_URL = need("SITE_URL");
// 単一ロールモード：役割を作れないサーバーでは、DB のユーザー1つで全部を動かす
const SINGLE = env.DB_MODE === "single";
const dbUser = (role, pw) => SINGLE ? DB(need("DB_USER"), need("DB_PASSWORD")) : DB(role, pw);
const JWT_SECRET = need("JWT_SECRET");
// 店舗名（PM2 のプロセス名の頭に付く。同じサーバーに複数店舗を置いても混ざらない）
const STORE = (env.STORE || "dandori").replace(/[^a-z0-9_-]/gi, "").toLowerCase() || "dandori";
// 中の部品のポート：決めていなければ LISTEN_PORT + 30000 から（8032 → 38032, 38033, 38034, 38041〜）
const LISTEN = Number(env.LISTEN_PORT || 8032);
const PORTS = {
  rest: env.REST_PORT || String(LISTEN + 30000),
  auth: env.AUTH_PORT || String(LISTEN + 30001),
  storage: env.STORAGE_PORT || String(LISTEN + 30002),
  fnBase: Number(env.FN_BASE_PORT || LISTEN + 30009),
};
const LOGS = path.join(HERE, "logs");
fs.mkdirSync(LOGS, { recursive: true });
const log = (name) => ({ out_file: path.join(LOGS, `${name}.log`), error_file: path.join(LOGS, `${name}.log`), merge_logs: true, log_date_format: "YYYY-MM-DD HH:mm:ss", time: true });
const common = (short) => { const name = `${STORE}-${short}`; return { name, cwd: HERE, autorestart: true, max_restarts: 50, restart_delay: 3000, ...log(name) }; };

// 3_サーバー の関数（lib/ports.mjs と同じ計算）
const FN_DIR = path.join(ROOT, "3_サーバー");
const functions = fs.readdirSync(FN_DIR, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(FN_DIR, d.name, "index.ts")))
  .map((d) => d.name).sort();

const apps = [
  {
    ...common("rest"), script: path.join(HERE, "bin", "postgrest"), interpreter: "none",
    env: {
      PGRST_DB_URI: dbUser("authenticator", env.AUTHENTICATOR_PASSWORD || ""),
      PGRST_DB_SCHEMAS: "public", PGRST_DB_USE_LEGACY_GUCS: "false",
      // 単一ロール：匿名の役割 = DB ユーザー自身。鍵の中の role は見ない（存在しない役割に切り替えないため）
      PGRST_DB_ANON_ROLE: SINGLE ? need("DB_USER") : "anon",
      ...(SINGLE ? { PGRST_JWT_ROLE_CLAIM_KEY: ".dandori_single_role_unused" } : {}),
      PGRST_DB_POOL: "10", PGRST_SERVER_HOST: "127.0.0.1", PGRST_SERVER_PORT: PORTS.rest,
      PGRST_JWT_SECRET: JWT_SECRET, PGRST_LOG_LEVEL: "error",
    },
  },
  {
    ...common("auth"), script: path.join(HERE, "bin", "auth"), interpreter: "none",   // 引数なし = テーブル作成（migrate）→ 起動
    env: {
      GOTRUE_API_HOST: "127.0.0.1", GOTRUE_API_PORT: PORTS.auth,
      API_EXTERNAL_URL: `${SITE_URL}/auth/v1`,
      GOTRUE_DB_DRIVER: "postgres",
      GOTRUE_DB_DATABASE_URL: dbUser("supabase_auth_admin", env.AUTH_ADMIN_PASSWORD || "") + (SINGLE ? "&search_path=auth" : ""),
      GOTRUE_DB_MIGRATIONS_PATH: path.join(HERE, "bin", "migrations"),
      GOTRUE_SITE_URL: SITE_URL, GOTRUE_URI_ALLOW_LIST: `${SITE_URL}/**`,
      GOTRUE_DISABLE_SIGNUP: "true", GOTRUE_EXTERNAL_EMAIL_ENABLED: "true", GOTRUE_MAILER_AUTOCONFIRM: "false",
      GOTRUE_JWT_ADMIN_ROLES: "service_role", GOTRUE_JWT_AUD: "authenticated", GOTRUE_JWT_DEFAULT_GROUP_NAME: "authenticated",
      GOTRUE_JWT_EXP: "3600", GOTRUE_JWT_SECRET: JWT_SECRET,
      GOTRUE_SMTP_HOST: env.SMTP_HOST || "", GOTRUE_SMTP_PORT: env.SMTP_PORT || "587",
      GOTRUE_SMTP_USER: env.SMTP_USER || "", GOTRUE_SMTP_PASS: env.SMTP_PASS || "",
      GOTRUE_SMTP_ADMIN_EMAIL: env.SMTP_ADMIN_EMAIL || "", GOTRUE_SMTP_SENDER_NAME: env.SMTP_SENDER_NAME || "ナイトだんどり",
      GOTRUE_MAILER_URLPATHS_INVITE: "/auth/v1/verify", GOTRUE_MAILER_URLPATHS_CONFIRMATION: "/auth/v1/verify",
      GOTRUE_MAILER_URLPATHS_RECOVERY: "/auth/v1/verify", GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: "/auth/v1/verify",
      GOTRUE_LOG_LEVEL: "warn",
    },
  },
  {
    ...common("storage"), script: path.join(HERE, "storage", "server.mjs"),
    env: {
      STORAGE_PORT: PORTS.storage, STORAGE_DIR: path.join(HERE, "data", "storage"),
      DATABASE_URL: dbUser("supabase_storage_admin", env.STORAGE_ADMIN_PASSWORD || ""), JWT_SECRET,
      DB_SINGLE_ROLE: SINGLE ? "1" : "",
    },
  },
  ...functions.map((name, i) => ({
    ...common(`fn-${name}`), script: path.join(HERE, "bin", "deno"), interpreter: "none",
    args: ["run", "--quiet", "--node-modules-dir=none", "--allow-net", "--allow-env", "--allow-read", path.join(HERE, "functions", "run.ts"), name, String(PORTS.fnBase + i)],
    env: {
      DENO_DIR: path.join(HERE, "data", "deno"), DENO_NO_UPDATE_CHECK: "1",
      SUPABASE_URL: `http://127.0.0.1:${env.LISTEN_PORT || 8032}`,
      SUPABASE_ANON_KEY: need("ANON_KEY"), SUPABASE_SERVICE_ROLE_KEY: need("SERVICE_ROLE_KEY"),
      ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY || "", GEMINI_API_KEY: env.GEMINI_API_KEY || "",
      OPENAI_API_KEY: env.OPENAI_API_KEY || "", PIXABAY_API_KEY: env.PIXABAY_API_KEY || "",
    },
  })),
  {
    ...common("gateway"), script: path.join(HERE, "gateway", "server.mjs"),
    env: {
      LISTEN_PORT: env.LISTEN_PORT || "8032", SITE_URL, JWT_SECRET, ANON_KEY: need("ANON_KEY"),
      REST_PORT: PORTS.rest, AUTH_PORT: PORTS.auth, STORAGE_PORT: PORTS.storage, FN_BASE_PORT: String(PORTS.fnBase),
      NO_VERIFY_JWT: "line-webhook",
    },
  },
];

// 送信箱（LINE・メール）を5分ごとに送る。.env の OUTBOX=1 のときだけ
if (env.OUTBOX === "1") {
  apps.push({
    ...common("outbox"), script: path.join(HERE, "outbox", "tick.mjs"),
    autorestart: false, cron_restart: "*/5 * * * *",
    env: { LISTEN_PORT: env.LISTEN_PORT || "8032", SERVICE_ROLE_KEY: need("SERVICE_ROLE_KEY") },
  });
}

module.exports = { apps, STORE };
