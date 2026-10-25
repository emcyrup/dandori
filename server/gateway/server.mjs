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
import * as sec from "./security.mjs";

const env = process.env;
const PORT = Number(env.LISTEN_PORT || 8032);
const SITE = path.resolve(import.meta.dirname, "..", "..", "1_画面");
// 店舗のロゴ：1_画面/logos/<店舗名>.png があれば、左上の目次・ログイン画面・タブのアイコンに使う
const LOGO = (() => {
  const st = String(env.STORE || "").replace(/[^a-z0-9_-]/gi, "").toLowerCase();
  return st && fs.existsSync(path.join(SITE, "logos", st + ".png")) ? "logos/" + st + ".png" : "";
})();
// ホーム画面のアイコン：1_画面/logos/<店舗名>-icon.png（正方形・白地）があれば、
// すべての HTML の <head> に apple-touch-icon と manifest を足し、/manifest.webmanifest を返す
const STORE_ID = String(env.STORE || "").replace(/[^a-z0-9_-]/gi, "").toLowerCase();
const ICON = STORE_ID && fs.existsSync(path.join(SITE, "logos", STORE_ID + "-icon.png")) ? "/logos/" + STORE_ID + "-icon.png" : "";
const APP_NAME = env.APP_NAME || (STORE_ID ? STORE_ID.charAt(0).toUpperCase() + STORE_ID.slice(1) : "ナイトだんどり");
const HEAD_EXTRA = ICON
  ? `<link rel="apple-touch-icon" sizes="180x180" href="${ICON.replace(".png", "-180.png")}">` +
    `<link rel="apple-touch-icon" href="${ICON}">` +
    `<link rel="icon" type="image/png" href="${ICON}">` +
    `<link rel="manifest" href="/manifest.webmanifest">` +
    `<meta name="apple-mobile-web-app-title" content="${APP_NAME.replace(/[<>"&]/g, "")}">` +
    `<meta name="application-name" content="${APP_NAME.replace(/[<>"&]/g, "")}">`
  : "";
const MANIFEST = ICON ? JSON.stringify({
  name: APP_NAME, short_name: APP_NAME, start_url: "/index.html", scope: "/", display: "browser",
  background_color: "#ffffff", theme_color: "#0E1319",
  icons: [{ src: ICON, sizes: "512x512", type: "image/png", purpose: "any" },
          { src: ICON, sizes: "512x512", type: "image/png", purpose: "maskable" }]
}) : "";
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
  ".webmanifest": "application/manifest+json",
  ".woff": "font/woff", ".woff2": "font/woff2", ".webp": "image/webp", ".pdf": "application/pdf",
};
const SITE_HEADERS = {
  "Cache-Control": "public, max-age=0, must-revalidate",   // Netlify の _headers と同じ
  "X-Robots-Tag": "noindex, nofollow",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",                                // ほかのサイトの中に埋め込ませない（クリックジャッキング）
  "Content-Security-Policy": "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'",
  "Permissions-Policy": "camera=(self), microphone=(), geolocation=()",
  "Strict-Transport-Security": "max-age=31536000",       // https でしか開かない（nginx が https を終端）
};
const BODY_LIMIT = { "/auth/v1/": 64 * 1024, "/rest/v1/": 8 * 1024 * 1024, "/functions/v1/": 2 * 1024 * 1024 };
const HOP = new Set(["connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "upgrade", "proxy-connection"]);

// ---- 画面
function serveStatic(req, res, urlPath) {
  if (req.method !== "GET" && req.method !== "HEAD") return text(res, 405, "Method Not Allowed");
  if (MANIFEST && urlPath.split("?")[0] === "/manifest.webmanifest") {
    res.writeHead(200, { ...SITE_HEADERS, "Content-Type": MIME[".webmanifest"], "Content-Length": Buffer.byteLength(MANIFEST) });
    return res.end(req.method === "HEAD" ? undefined : MANIFEST);
  }
  let rel;
  try { rel = decodeURIComponent(urlPath.split("?")[0]); } catch { return text(res, 400, "Bad Request"); }   // "%" だけ、などで落ちない
  if (rel.includes("\0")) { sec.onNotFound(req); return text(res, 404, "Not found"); }
  if (rel.endsWith("/")) rel += "index.html";
  const file = path.resolve(SITE, "." + rel);
  if (!file.startsWith(SITE + path.sep) || path.basename(file).startsWith("_")) { sec.onNotFound(req); return text(res, 404, "Not found"); }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { sec.onNotFound(req); return text(res, 404, "Not found"); }
    const type = MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
    if (HEAD_EXTRA && type.startsWith("text/html")) {
      // ホーム画面のアイコン（iPhone は <head> の apple-touch-icon を読む）
      const body = fs.readFileSync(file, "utf8").replace(/<head>/i, "<head>" + HEAD_EXTRA);
      res.writeHead(200, { ...SITE_HEADERS, "Content-Type": type, "Content-Length": Buffer.byteLength(body) });
      return res.end(req.method === "HEAD" ? undefined : body);
    }
    if (path.basename(file) === "config.js") {
      // 接続先をこのサーバーに向ける（リポジトリの config.js はさわらない）
      const body = fs.readFileSync(file, "utf8") +
        `\n// ---- 本番サーバー用（入口が自動で追記）\n` +
        `window.DANDORI_CONFIG.supabaseUrl = ${JSON.stringify(env.SITE_URL)};\n` +
        `window.DANDORI_CONFIG.supabaseAnonKey = ${JSON.stringify(env.ANON_KEY)};\n` +
        (LOGO ? `window.DANDORI_CONFIG.logoImage = ${JSON.stringify(LOGO)};\n` : "");
      res.writeHead(200, { ...SITE_HEADERS, "Content-Type": type, "Content-Length": Buffer.byteLength(body) });
      return res.end(req.method === "HEAD" ? undefined : body);
    }
    res.writeHead(200, { ...SITE_HEADERS, "Content-Type": type, "Content-Length": st.size });
    if (req.method === "HEAD") return res.end();
    fs.createReadStream(file).pipe(res);
  });
}

// ---- 中継
function proxy(req, res, port, newPath, timeout, opts) {
  const { body = null, onResponse = null } = opts || {};
  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) if (!HOP.has(k)) headers[k] = v;
  if (body !== null) { headers["content-length"] = String(body.length); delete headers["transfer-encoding"]; }
  // 接続元は入口が決めた 1 つだけを渡す（クライアントが付けた X-Forwarded-For は上流に見せない）
  headers["x-forwarded-for"] = sec.clientIp(req);
  headers["x-forwarded-proto"] = req.headers["x-forwarded-proto"] || "https";
  headers["x-forwarded-host"] = req.headers["x-forwarded-host"] || req.headers.host || "";
  headers.host = `127.0.0.1:${port}`;
  const up = http.request({ host: "127.0.0.1", port, method: req.method, path: newPath, headers, timeout }, (r) => {
    const out = {};
    for (const [k, v] of Object.entries(r.headers)) if (!HOP.has(k)) out[k] = v;
    if (onResponse) { try { onResponse(r.statusCode); } catch {} }
    res.writeHead(r.statusCode, out);
    r.pipe(res);
  });
  up.on("timeout", () => up.destroy(new Error("timeout")));
  up.on("error", (e) => {
    if (!res.headersSent) json(res, 502, { code: "UPSTREAM", message: `中の部品に届きませんでした (${e.message})` });
    else res.destroy();
  });
  if (body !== null) { up.end(body); } else { req.pipe(up); }
}

// 本文を読み切る（ログインの失敗を数えるときに、メールを取り出すため）。大きすぎれば null（413 にする）
function readBody(req, limit) {
  return new Promise((resolve) => {
    const chunks = []; let size = 0; let over = false;
    req.on("data", (c) => { size += c.length; if (size > limit) { over = true; req.destroy(); } else chunks.push(c); });
    req.on("end", () => resolve(over ? null : Buffer.concat(chunks)));
    req.on("close", () => resolve(over ? null : Buffer.concat(chunks)));
    req.on("error", () => resolve(null));
  });
}

// 申告された本文の大きさが上限を超えていれば、読む前に 413
function tooBig(req, res, limit) {
  const n = Number(req.headers["content-length"] || 0);
  if (n > limit) { json(res, 413, { code: "TOO_LARGE", message: "送られた内容が大きすぎます" }); return true; }
  return false;
}

function text(res, code, s) { res.writeHead(code, { "Content-Type": "text/plain; charset=utf-8" }); res.end(s); }
function json(res, code, o) { res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(o)); }

// 想定外の例外で入口そのものが落ちないように（落ちると画面も API も全部止まる）
process.on("uncaughtException", (e) => { console.error("uncaught:", e && e.stack || e); });
process.on("unhandledRejection", (e) => { console.error("unhandled:", e && e.stack || e); });

const server = http.createServer((req, res) => {
  try { route(req, res); } catch (e) { console.error(e); if (!res.headersSent) json(res, 500, { code: "ERROR", message: "入口でエラーになりました" }); else res.destroy(); }
});
server.headersTimeout = 20_000;      // ヘッダだけ送って待たせる接続を切る
server.requestTimeout = 180_000;     // 本文の送信が遅すぎる接続を切る（アップロード・AI の下書きは 150 秒以内）
server.maxHeadersCount = 100;

function route(req, res) {
  const url = req.url || "/";
  if (url === "/health") return text(res, 200, "ok");

  // ---- 見張り：遮断中なら 429。鍵が付いていれば中身を見て、サーバー鍵の外からの利用・大量アクセスを数える
  if (sec.isBlocked(req, res)) return;
  const tok0 = bearer(req);
  if (!sec.inspect(req, tok0 ? verify(tok0, JWT_SECRET) : null)) {
    return json(res, 403, { code: "FORBIDDEN", message: "この鍵は外からは使えません。" });
  }

  // ログイン：失敗が続いたら遮断する（本文のメールも記録）
  if (url.startsWith("/auth/v1/token") && req.method === "POST") {
    if (tooBig(req, res, BODY_LIMIT["/auth/v1/"])) return;
    return readBody(req, BODY_LIMIT["/auth/v1/"]).then((buf) => {
      if (buf === null) { if (!res.headersSent) json(res, 413, { code: "TOO_LARGE", message: "送られた内容が大きすぎます" }); return; }
      proxy(req, res, UPSTREAM["/auth/v1/"].port, url.slice("/auth/v1/".length - 1), 30_000, {
        body: buf, onResponse: (code) => sec.onLogin(req, code, buf.toString("utf8")),
      });
    });
  }

  for (const [prefix, u] of Object.entries(UPSTREAM)) {
    if (url.startsWith(prefix)) {
      if (prefix !== "/storage/v1/" && tooBig(req, res, BODY_LIMIT[prefix])) return;
      const watch = prefix === "/rest/v1/" ? { onResponse: (code) => { if (code === 401) sec.onBadToken(req); } } : null;
      return proxy(req, res, u.port, url.slice(prefix.length - 1), u.timeout, watch);
    }
  }

  if (url.startsWith("/functions/v1/")) {
    const rest = url.slice("/functions/v1/".length);
    const name = rest.split(/[/?]/)[0];
    const port = FUNCTIONS[name];
    if (!port) return json(res, 404, { code: "NOT_FOUND", message: "Requested function was not found" });
    if (tooBig(req, res, BODY_LIMIT["/functions/v1/"])) return;
    if (req.method !== "OPTIONS" && !NO_VERIFY.has(name)) {
      const tok = bearer(req);
      if (!tok) { sec.onBadToken(req); return json(res, 401, { code: "UNAUTHORIZED_NO_AUTH_HEADER", message: "Missing authorization header", msg: "Missing authorization header" }); }
      if (!verify(tok, JWT_SECRET)) { sec.onBadToken(req); return json(res, 401, { code: "UNAUTHORIZED_LEGACY_JWT", message: "Invalid JWT", msg: "Invalid JWT" }); }
    }
    return proxy(req, res, port, "/" + rest, 150_000);
  }

  serveStatic(req, res, url);
}

server.listen(PORT, "127.0.0.1", () => { console.log(`gateway: 127.0.0.1:${PORT} → ${SITE}`); sec.start(); });
