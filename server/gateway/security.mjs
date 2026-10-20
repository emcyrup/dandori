// ============================================================================
//  ナイトだんどり / 入口の見張り（不正アクセスの検知と遮断）
//
//  すべての通信は入口（gateway）を通るので、ここで見張ります。店舗ごとに環境が分かれているので、
//  店舗ごとに独立して動きます。見つけたことは DB の security_event に残し、
//  遮断した接続元は security_block に入れます（店長が「設定 → 不正アクセス」で見る・解除する）。
//
//  見張っていること
//    login_fail / login_bruteforce  ログインの失敗が続く（同じ接続元・同じメール）
//    bad_token                      壊れた・期限切れの鍵でデータや関数を呼び続ける
//    scan                           ありもしない管理画面などを探す（/wp-admin, .php, .env, .git …）
//    svc_key_misuse                 サーバーの鍵（service_role）を外から使う ★最重要
//    flood                          短い時間に大量の通信
//
//  遮断は 429 を返すだけ（nginx やファイアウォールは触れません）。127.0.0.1 と
//  SECURITY_ALLOW_IPS に書いた接続元は遮断しません。
//  Node 22 の標準機能だけで動きます。
// ============================================================================
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const env = process.env;
const ON = env.SECURITY !== "0";
const ALLOW = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1", ...(env.SECURITY_ALLOW_IPS || "").split(",").map((s) => s.trim()).filter(Boolean)]);
const num = (k, d) => { const n = Number(env[k]); return Number.isFinite(n) && n > 0 ? n : d; };
const RULE = {
  loginFail:   { count: num("SEC_LOGIN_FAILS", 5),   window: 10 * 60e3, block: 15 * 60e3 },   // 10分に5回 → 15分
  loginEmail:  { count: num("SEC_EMAIL_FAILS", 10),  window: 10 * 60e3 },                     // 同じメールに10回（記録のみ）
  badToken:    { count: num("SEC_BAD_TOKENS", 20),   window: 10 * 60e3, block: 30 * 60e3 },
  scan:        { count: num("SEC_SCAN_HITS", 3),     window: 10 * 60e3, block: 60 * 60e3 },
  flood:       { count: num("SEC_FLOOD_PER_MIN", 600), window: 60e3,    block: 5 * 60e3 },
  svc:         { block: 24 * 60 * 60e3 },                                                      // 即・24時間
};
const SCAN_RE = /(\.php|\.asp|\.aspx|\.jsp|\.env|\.git\b|\.svn|\.htaccess|\.bak|\.sql|\.zip|\.tar|wp-admin|wp-login|wp-content|wp-includes|xmlrpc|phpmyadmin|phpinfo|cgi-bin|\/admin\/|\/administrator|\/manager\/|\/console|\/actuator|\/\.well-known\/[^a]|\/vendor\/|\/etc\/passwd|\.\.\/|%2e%2e|\/boaform|\/HNAP1|\/shell|\/cgi\b|\/owa\/|\/autodiscover)/i;

const LOG = path.join(path.resolve(import.meta.dirname, ".."), "logs", "security.log");

// ---- 記憶（接続元ごとの数え上げ）。古いものは捨てる
const hits = new Map();      // key → [timestamps]
const blocks = new Map();    // ip → { until, reason }
let lastDbSync = 0;

function bump(key, windowMs) {
  const now = Date.now();
  const arr = (hits.get(key) || []).filter((t) => now - t < windowMs);
  arr.push(now);
  hits.set(key, arr);
  return arr.length;
}
setInterval(() => {   // 1時間に1回、空の記憶を捨てる
  const now = Date.now();
  for (const [k, arr] of hits) if (!arr.length || now - arr[arr.length - 1] > 60 * 60e3) hits.delete(k);
  for (const [ip, b] of blocks) if (b.until < now) blocks.delete(ip);
}, 60 * 60e3).unref();

// ---- 接続元の IP。nginx が最後に足した X-Forwarded-For の値を使う（先頭は偽装できるため）
export function clientIp(req) {
  const xff = String(req.headers["x-forwarded-for"] || "").split(",").map((s) => s.trim()).filter(Boolean);
  const ip = xff.length ? xff[xff.length - 1] : (req.socket.remoteAddress || "");
  return ip.replace(/^::ffff:/, "");
}

// ---- DB へ書く（PostgREST にサーバー鍵で）。失敗しても入口は止めない
function db(method, pathname, body, extraHeaders) {
  return new Promise((resolve) => {
    if (!env.SERVICE_ROLE_KEY || !env.REST_PORT) return resolve(null);
    const data = body == null ? null : JSON.stringify(body);
    const r = http.request({
      host: "127.0.0.1", port: Number(env.REST_PORT), method, path: pathname, timeout: 5000,
      headers: {
        "content-type": "application/json", "apikey": env.SERVICE_ROLE_KEY,
        "authorization": `Bearer ${env.SERVICE_ROLE_KEY}`, "prefer": "return=representation",
        ...(data ? { "content-length": Buffer.byteLength(data) } : {}), ...(extraHeaders || {}),
      },
    }, (res) => {
      let s = ""; res.on("data", (c) => s += c); res.on("end", () => {
        if (res.statusCode >= 300) { fileLog(`db ${method} ${pathname} → ${res.statusCode} ${s.slice(0, 200)}`); return resolve(null); }
        try { resolve(s ? JSON.parse(s) : null); } catch { resolve(null); }
      });
    });
    r.on("error", (e) => { fileLog(`db error ${e.message}`); resolve(null); });
    r.on("timeout", () => r.destroy(new Error("timeout")));
    if (data) r.write(data);
    r.end();
  });
}

function fileLog(line) {
  try { fs.mkdirSync(path.dirname(LOG), { recursive: true }); fs.appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`); } catch {}
}

async function event(kind, severity, ip, req, detail, blockedUntil) {
  const row = {
    kind, severity, ip, path: req ? String(req.url || "").slice(0, 300) : null,
    user_email: detail && detail.email ? String(detail.email).slice(0, 200) : null,
    detail: { ...(detail || {}), ua: req ? String(req.headers["user-agent"] || "").slice(0, 200) : undefined },
    blocked_until: blockedUntil ? new Date(blockedUntil).toISOString() : null,
  };
  fileLog(`${severity} ${kind} ip=${ip} ${row.path || ""} ${JSON.stringify(detail || {})}`);
  await db("POST", "/security_event", row);
}

async function block(ip, reason, ms, req, detail) {
  if (ALLOW.has(ip)) return;
  const until = Date.now() + ms;
  const cur = blocks.get(ip);
  blocks.set(ip, { until: Math.max(until, cur ? cur.until : 0), reason });
  await event("blocked", "high", ip, req, { reason, minutes: Math.round(ms / 60e3), ...(detail || {}) }, until);
  await db("POST", "/security_block?on_conflict=ip", {
    ip, reason, until: new Date(blocks.get(ip).until).toISOString(), hits: 1, released: false,
  }, { prefer: "resolution=merge-duplicates,return=representation" });
}

// ---- DB と同期（店長が画面で解除したら効かせる。入口が再起動しても遮断を忘れない）
async function syncBlocks() {
  lastDbSync = Date.now();
  const rows = await db("GET", `/security_block?select=ip,until,reason,released&until=gt.${encodeURIComponent(new Date().toISOString())}`);
  if (!Array.isArray(rows)) return;
  const live = new Set();
  for (const r of rows) {
    if (r.released) { blocks.delete(r.ip); continue; }
    live.add(r.ip);
    blocks.set(r.ip, { until: new Date(r.until).getTime(), reason: r.reason });
  }
  for (const ip of [...blocks.keys()]) if (!live.has(ip)) blocks.delete(ip);   // 解除された・期限切れ
}

// ---- 入口から呼ぶ ------------------------------------------------------------

/** 遮断中なら 429 を返して true */
export function isBlocked(req, res) {
  if (!ON) return false;
  const ip = clientIp(req);
  const b = blocks.get(ip);
  if (!b || b.until < Date.now()) return false;
  res.writeHead(429, { "Content-Type": "application/json; charset=utf-8", "Retry-After": String(Math.ceil((b.until - Date.now()) / 1000)) });
  res.end(JSON.stringify({ code: "BLOCKED", message: "しばらくの間、この接続元からの利用を止めています。お店の方にご連絡ください。" }));
  return true;
}

/** 通信ごとに呼ぶ（遮断の判定のあと）。大量アクセスと、サーバー鍵の外からの利用を見る。
    この通信そのものを通してはいけないときは false を返す（入口が 403 を返す） */
export function inspect(req, claims) {
  if (!ON) return true;
  const ip = clientIp(req);
  if (ALLOW.has(ip)) return true;
  if (bump(`flood:${ip}`, RULE.flood.window) === RULE.flood.count) {
    block(ip, "flood", RULE.flood.block, req, { per_minute: RULE.flood.count });
  }
  // サーバー鍵（svc / service_role）は中の部品だけが使う。外から来たら、この通信は通さず即遮断
  if (claims && (claims.svc === true || claims.svc === "true" || claims.role === "service_role")) {
    block(ip, "svc_key_misuse", RULE.svc.block, req, {});
    return false;
  }
  return true;
}

/** ログイン（/auth/v1/token）の結果を見る。body はリクエストの本文（メールを取り出す） */
export function onLogin(req, statusCode, bodyText) {
  if (!ON) return;
  const ip = clientIp(req);
  if (ALLOW.has(ip) || statusCode < 400) {
    if (statusCode < 400) hits.delete(`login:${ip}`);   // 成功したら数え直し
    return;
  }
  let email = null;
  try { email = String(JSON.parse(bodyText || "{}").email || "").toLowerCase().slice(0, 200) || null; } catch {}
  const n = bump(`login:${ip}`, RULE.loginFail.window);
  event("login_fail", "info", ip, req, { email, status: statusCode, count: n });
  if (n === RULE.loginFail.count) block(ip, "login_bruteforce", RULE.loginFail.block, req, { email, fails: n });
  if (email) {
    const m = bump(`email:${email}`, RULE.loginEmail.window);
    if (m === RULE.loginEmail.count) event("login_bruteforce", "high", ip, req, { email, fails: m, note: "同じメールへの失敗が続いています（複数の接続元かもしれません）" });
  }
}

/** データ・関数の呼び出しが 401 で返った（鍵が壊れている・期限切れ） */
export function onBadToken(req) {
  if (!ON) return;
  const ip = clientIp(req);
  if (ALLOW.has(ip)) return;
  const n = bump(`tok:${ip}`, RULE.badToken.window);
  if (n === 1 || n % 10 === 0) event("bad_token", "info", ip, req, { count: n });
  if (n === RULE.badToken.count) block(ip, "bad_token", RULE.badToken.block, req, { count: n });
}

/** 画面のファイルが見つからなかった。探索っぽい URL なら数える */
export function onNotFound(req) {
  if (!ON) return;
  const url = String(req.url || "");
  if (!SCAN_RE.test(url)) return;
  const ip = clientIp(req);
  if (ALLOW.has(ip)) return;
  const n = bump(`scan:${ip}`, RULE.scan.window);
  event("scan", n >= RULE.scan.count ? "high" : "warn", ip, req, { count: n });
  if (n === RULE.scan.count) block(ip, "scan", RULE.scan.block, req, { count: n });
}

export function start() {
  if (!ON) { console.log("security: off (SECURITY=0)"); return; }
  syncBlocks().catch(() => {});
  setInterval(() => syncBlocks().catch(() => {}), 30e3).unref();
  setInterval(() => db("POST", "/rpc/security_prune", { p_days: 90 }).catch(() => {}), 24 * 60 * 60e3).unref();
  console.log(`security: on (allow: ${[...ALLOW].join(", ")})`);
}
