/* ============================================================================
   だんどりシリーズ / 共通ページの小さな土台
   kyotsu.js
   置き場所： サイトのルート（index.html と同じ階層）

   「シフト希望」と「届出・許可証」の2ページが、これを使います。
   ナイト・キャスト・フードのどれに置いても、そのまま動きます。
   すでにある画面のJSには、いっさい触れません。
   ============================================================================ */

window.K = (function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  var S = { me: null, stores: [], store: null };
  var ready = null;

  var DOW = ["日", "月", "火", "水", "木", "金", "土"];

  /* ------------------------------------------------------------ 小さな道具 */

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function yen(n) { return "¥" + (Number(n) || 0).toLocaleString("ja-JP"); }
  function num(n) { return (Number(n) || 0).toLocaleString("ja-JP"); }

  function ymd(d) {
    var t = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
    return t.toISOString().slice(0, 10);
  }

  function today() { return ymd(new Date()); }

  function md(s) {
    if (!s) return "";
    var d = new Date(String(s).slice(0, 10) + "T00:00:00");
    return (d.getMonth() + 1) + "/" + d.getDate() + "（" + DOW[d.getDay()] + "）";
  }

  function dt(s) {
    if (!s) return "—";
    return new Date(s).toLocaleString("ja-JP",
      { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
  }

  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }

  function fail(e) {
    var m = (e && (e.message || e.details)) || String(e);
    toast(m.replace(/^.*?:\s*/, ""), "err");
    if (window.console) console.error(e);
  }

  function modal(html, onReady) {
    var root = $("modalRoot");
    root.innerHTML = '<div class="modal"><div class="box">' + html + "</div></div>";
    var wrap = root.querySelector(".modal");
    wrap.addEventListener("click", function (e) { if (e.target === wrap) closeModal(); });
    if (onReady) onReady(root);
  }

  function closeModal() { $("modalRoot").innerHTML = ""; }

  function confirmBox(title, body, okLabel, fn) {
    modal(
      "<h2 style='margin-top:0'>" + esc(title) + "</h2><div>" + body + "</div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='k_no'>やめる</button>" +
      "<button class='btn primary' id='k_ok'>" + esc(okLabel || "はい") + "</button></div>",
      function (root) {
        root.querySelector("#k_no").addEventListener("click", closeModal);
        root.querySelector("#k_ok").addEventListener("click", function () { fn(root); });
      });
  }

  function rpc(name, args) {
    return sb.rpc(name, args || {}).then(function (q) {
      if (q.error) { fail(q.error); return null; }
      return q.data;
    });
  }

  function table(head, rows) {
    if (!rows.length) return "";
    return "<thead><tr>" + head.map(function (h) {
      return "<th" + (h.num ? " class='num'" : "") + ">" + esc(h.label || h) + "</th>";
    }).join("") + "</tr></thead><tbody>" + rows.join("") + "</tbody>";
  }

  function empty(msg) { return "<div class='empty'>" + esc(msg) + "</div>"; }

  function pill(text, kind) {
    if (!text) return "";
    return "<span class='pill " + (kind || "warn") + "'>" + esc(text) + "</span>";
  }

  function stat(k, v, cls) {
    return "<div class='stat " + (cls || "") + "'><span class='k'>" + esc(k) +
           "</span><span class='v'>" + v + "</span></div>";
  }

  function bind(root, sel, attr, fn) {
    Array.prototype.forEach.call((root || document).querySelectorAll(sel), function (b) {
      b.addEventListener("click", function () { fn(b.dataset[attr], b); });
    });
  }

  function opts(list, valueKey, labelKey, selected, blank) {
    var h = blank ? "<option value=''>" + esc(blank) + "</option>" : "";
    return h + (list || []).map(function (x) {
      var v = x[valueKey];
      return "<option value='" + esc(v) + "'" + (v === selected ? " selected" : "") + ">" +
             esc(x[labelKey]) + "</option>";
    }).join("");
  }

  function isBoss() {
    return S.me && (S.me.role === "owner" || S.me.role === "manager");
  }

  function baseUrl() { return location.href.replace(/[^/]*$/, ""); }

  /* ------------------------------------------------------------ ログイン */

  function showLogin() {
    $("login").classList.remove("hidden");
    $("app").classList.add("hidden");
  }

  function wireLogin() {
    var f = $("loginForm");
    if (!f) return;
    f.addEventListener("submit", function (e) {
      e.preventDefault();
      $("loginBtn").disabled = true;
      sb.auth.signInWithPassword({
        email: $("email").value.trim(),
        password: $("password").value
      }).then(function (r) {
        $("loginBtn").disabled = false;
        if (r.error) { fail(r.error); return; }
        boot();
      });
    });
    var lo = $("logoutBtn");
    if (lo) lo.addEventListener("click", function () {
      sb.auth.signOut().then(function () { location.reload(); });
    });
  }

  function boot(onReady) {
    if (onReady) ready = onReady;
    return sb.auth.getSession().then(function (r) {
      var u = (r && r.data && r.data.session) ? r.data.session.user : null;
      if (!u) { showLogin(); return; }
      return sb.from("staff").select("*").eq("auth_user_id", u.id).maybeSingle()
        .then(function (q) {
          if (q.error) { fail(q.error); return; }
          if (!q.data) {
            toast("このアカウントにスタッフ登録がありません。担当までご連絡ください。", "err");
            return;
          }
          S.me = q.data;
          if ($("meName")) $("meName").textContent = S.me.name;
          $("login").classList.add("hidden");
          $("app").classList.remove("hidden");
          document.body.className = "theme-" + (CFG.theme || "standard");
          return loadStores();
        });
    }).catch(fail);
  }

  /*  お店のえらびかた
      ・その業種のお店だけを出します（store.industry を見ています）
      ・えらんだお店は、業種ごとに別々に覚えます。
        ほかの業種の画面をひらいても、入れかわりません。
      ・画面を更新しても、前にえらんだお店のままです。 */
  var MISEKEY = "dandori-store-" + (CFG.industry || "x");

  function loadStores() {
    return sb.rpc("store_list", { p_kind: CFG.industry || null })
      .then(function (q) {
        if (q.error || !q.data || !q.data.length) return storesFromTable();
        return putStores(q.data);
      })
      .catch(storesFromTable);
  }

  /*  store_list（022_mise.sql）がまだ入っていないときの、ひかえの道です */
  function storesFromTable() {
    return sb.from("store").select("*").eq("is_active", true).order("name")
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var all = q.data || [];
        var mine = all.filter(function (s) { return s.industry === CFG.industry; });
        return putStores(mine.length ? mine : all);
      });
  }

  function putStores(rows) {
    S.stores = rows || [];
    if (!S.stores.length) { toast("店舗が登録されていません。", "err"); return; }
    var sel = $("storeSel");
    if (sel) {
      sel.innerHTML = opts(S.stores, "id", "name");
      if (!sel.getAttribute("data-wired")) {
        sel.setAttribute("data-wired", "1");
        sel.addEventListener("change", function () { selectStore(this.value); });
      }
    }
    var keep = null;
    try { keep = localStorage.getItem(MISEKEY); } catch (e) {}
    var hit = S.stores.filter(function (s) { return s.id === keep; })[0];
    return selectStore(hit ? hit.id : S.stores[0].id);
  }

  function selectStore(id) {
    S.store = S.stores.filter(function (s) { return s.id === id; })[0];
    if ($("storeSel")) $("storeSel").value = id;
    try { localStorage.setItem(MISEKEY, id); } catch (e) {}
    if (ready) ready(S.store);
  }

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  return {
    sb: sb, S: S, cfg: CFG, DOW: DOW,
    $: $, esc: esc, yen: yen, num: num, ymd: ymd, today: today, md: md, dt: dt,
    toast: toast, fail: fail, modal: modal, closeModal: closeModal, confirm: confirmBox,
    rpc: rpc, table: table, empty: empty, pill: pill, stat: stat,
    bind: bind, opts: opts, isBoss: isBoss, baseUrl: baseUrl,
    wireLogin: wireLogin, boot: boot, selectStore: selectStore
  };
})();
