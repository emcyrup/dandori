// ============================================================================
//  ナイトだんどり / 入口（ポート 8032）
//
//   サーバーの nginx（https）→ 127.0.0.1:8032 → ここ
//     /                 → 1_画面 のファイルをそのまま出す
//                         （config.js だけ、末尾にこのサーバーの接続先を足して出す）
//     /rest/v1/…        → PostgREST（データ）
//     /auth/v1/…        → GoTrue（ログイン）
//     /storage/v1/…     → ファイル置き場（server/storage）
//     /functions/v1/…   → 3_サーバー の各関数（Deno）。先にログインの鍵を確かめる
//
//  Node 22 の標準機能だけで動きます（追加のライブラリなし）。
// ============================================================================
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { verify, bearer } from "../lib/jwt.mjs";
import { functionPorts } from "../lib/ports.mjs";

const env = process.env;
const PORT = Number(env.LISTEN_PORT || 8032);
const SITE = path.resolve(import.meta.dirname, "..", "..", "1_画面");
const JWT_SECRET = env.JWT_SECRET || "";
const NO_VERIFY = new Set((env.NO_VERIFY_JWT || "line-webhook").split(",").map((s) => s.trim()).filter(Boolean));
const UPSTREAM = {
  "/rest/v1/": { port: Number(env.REST_PORT), timeout: 30_000 },
  "/auth/v1/": { port: Number(env.AUTH_PORT), timeout: 30_000 },
  "/storage/v1/": { port: Number(env.STORAGE_PORT), timeout: 120_000 },
};
const FUNCTIONS = functionPorts();

if (!JWT_SECRET) { console.error("JWT_SECRET が空です"); process.exit(1); }
for (const [k, v] of Object.entries(UPSTREAM)) if (!v.port) { console.error(`${k} のポートが空です`); process.exit(1); }

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".svg": "image/svg+xml",
  ".ico": "image/x-icon", ".json": "application/json; charset=utf-8", ".txt": "text/plain; charset=utf-8",
  ".woff": "font/woff", ".woff2": "font/woff2", ".webp": "image/webp", ".pdf": "application/pdf",
};
const SITE_HEADERS = {
  "Cache-Control": "public, max-age=0, must-revalidate",   // Netlify の _headers と同じ
  "X-Robots-Tag": "noindex, nofollow",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};
const HOP = new Set(["connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "upgrade", "proxy-connection"]);

// ---- 画面
function serveStatic(req, res, urlPath) {
  if (req.method !== "GET" && req.method !== "HEAD") return text(res, 405, "Method Not Allowed");
  let rel = decodeURIComponent(urlPath.split("?")[0]);
  if (rel.endsWith("/")) rel += "index.html";
  const file = path.resolve(SITE, "." + rel);
  if (!file.startsWith(SITE + path.sep) || path.basename(file).startsWith("_")) return text(res, 404, "Not found");
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) return text(res, 404, "Not found");
    const type = MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
    if (path.basename(file) === "config.js") {
      // 接続先をこのサーバーに向ける（リポジトリの config.js はさわらない）
      const body = fs.readFileSync(file, "utf8") +
        `\n// ---- 本番サーバー用（入口が自動で追記）\n` +
        `window.DANDORI_CONFIG.supabaseUrl = ${JSON.stringify(env.SITE_URL)};\n` +
        `window.DANDORI_CONFIG.supabaseAnonKey = ${JSON.stringify(env.ANON_KEY)};\n`;
      res.writeHead(200, { ...SITE_HEADERS, "Content-Type": type, "Content-Length": Buffer.byteLength(body) });
      return res.end(req.method === "HEAD" ? undefined : body);
    }
    res.writeHead(200, { ...SITE_HEADERS, "Content-Type": type, "Content-Length": st.size });
    if (req.method === "HEAD") return res.end();
    fs.createReadStream(file).pipe(res);
  });
}

// ---- 中継
function proxy(req, res, port, newPath, timeout) {
  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) if (!HOP.has(k)) headers[k] = v;
  headers["x-forwarded-for"] = [req.headers["x-forwarded-for"], req.socket.remoteAddress].filter(Boolean).join(", ");
  headers["x-forwarded-proto"] = req.headers["x-forwarded-proto"] || "https";
  headers["x-forwarded-host"] = req.headers["x-forwarded-host"] || req.headers.host || "";
  headers.host = `127.0.0.1:${port}`;
  const up = http.request({ host: "127.0.0.1", port, method: req.method, path: newPath, headers, timeout }, (r) => {
    const out = {};
    for (const [k, v] of Object.entries(r.headers)) if (!HOP.has(k)) out[k] = v;
    res.writeHead(r.statusCode, out);
    r.pipe(res);
  });
  up.on("timeout", () => up.destroy(new Error("timeout")));
  up.on("error", (e) => {
    if (!res.headersSent) json(res, 502, { code: "UPSTREAM", message: `中の部品に届きませんでした (${e.message})` });
    else res.destroy();
  });
  req.pipe(up);
}

function text(res, code, s) { res.writeHead(code, { "Content-Type": "text/plain; charset=utf-8" }); res.end(s); }
function json(res, code, o) { res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(o)); }

http.createServer((req, res) => {
  const url = req.url || "/";
  if (url === "/health") return text(res, 200, "ok");

  for (const [prefix, u] of Object.entries(UPSTREAM)) {
    if (url.startsWith(prefix)) return proxy(req, res, u.port, url.slice(prefix.length - 1), u.timeout);
  }

  if (url.startsWith("/functions/v1/")) {
    const rest = url.slice("/functions/v1/".length);
    const name = rest.split(/[/?]/)[0];
    const port = FUNCTIONS[name];
    if (!port) return json(res, 404, { code: "NOT_FOUND", message: "Requested function was not found" });
    if (req.method !== "OPTIONS" && !NO_VERIFY.has(name)) {
      const tok = bearer(req);
      if (!tok) return json(res, 401, { code: "UNAUTHORIZED_NO_AUTH_HEADER", message: "Missing authorization header", msg: "Missing authorization header" });
      if (!verify(tok, JWT_SECRET)) return json(res, 401, { code: "UNAUTHORIZED_LEGACY_JWT", message: "Invalid JWT", msg: "Invalid JWT" });
    }
    return proxy(req, res, port, "/" + rest, 150_000);
  }

  serveStatic(req, res, url);
}).listen(PORT, "127.0.0.1", () => console.log(`gateway: 127.0.0.1:${PORT} → ${SITE}`));
