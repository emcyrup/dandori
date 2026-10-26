/* ============================================================================
   だんどりシリーズ / 画面の出し分け
   perm.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： supabase.js → config.js → perm.js → その画面のJS

   権限は2つです。
     店長（中では owner）… 管理者。設定 → 権限 で、店長・スタッフが使える機能を決められます
     スタッフ（staff）
   ・機能の一覧は下の FEATURES。画面（○○.html）と、画面の中のタブ（○○.html#タブ）です
   ・boss: true の機能は、データベース側でも店長だけに閉じているので、スタッフには出せません
   ・data-boss="1" が付いたボタンは、店長にだけ出します（いままでどおり）

   だいじなこと
     これは「見せない」しくみです。お金の全体像など大事なものは、
     データベース側（019_kengen.sql ほか）でも店長だけに閉じています。
   ============================================================================ */

(function () {
  "use strict";

  /* ------------------------------------------------- 機能の一覧（ナイト） */
  var FEATURES = [
    { k: "index.html",          t: "伝票・会計",        staff: true },
    { k: "rides.html",          t: "送り",              staff: true },
    { k: "customers.html",      t: "お客様",            staff: true },
    { k: "sales.html",          t: "売上",              staff: false },
    { k: "close.html",          t: "締め・日報",        staff: true },
    { k: "payroll.html",        t: "キャスト・給与",    staff: true },
    { k: "payroll.html#attend", t: "出勤",              staff: true,  sub: 1 },
    { k: "payroll.html#calc",   t: "給与の計算",        boss: true,   sub: 1 },
    { k: "payroll.html#slip",   t: "明細（スタッフはご自分のぶん）", staff: false, sub: 1 },
    { k: "payroll.html#month",  t: "月別",              boss: true,   sub: 1 },
    { k: "payroll.html#cast",   t: "キャスト設定",      boss: true,   sub: 1 },
    { k: "payroll.html#roster", t: "名簿",              staff: false, sub: 1 },
    { k: "payroll.html#xl",     t: "過去給与と照合",    boss: true,   sub: 1 },
    { k: "shiftwish.html",      t: "シフト希望（スタッフはご自分の希望だけ）", staff: true },
    { k: "stock.html",          t: "在庫・発注",        staff: true },
    { k: "souji.html",          t: "清掃・やること",    staff: true },
    { k: "docs.html",           t: "届出・許可証",      staff: true },
    { k: "docs.html#line",      t: "LINEの登録",        boss: true,   sub: 1 },
    { k: "admin.html",          t: "設定",              boss: true,   lock: true },
    { k: "login.html",          t: "ログインの管理",    boss: true,   lock: true },
    { k: "theme.html",          t: "見た目",            staff: false },
    { k: "teian.html",          t: "こんなこともできます", staff: false }
  ];
  /* 一覧に無い画面（ほかの業種）で、スタッフに出さないもの */
  var BOSS_PAGES = { "sales.html": 1, "admin.html": 1, "login.html": 1, "hq.html": 1 };

  var BY = {};
  FEATURES.forEach(function (f) { BY[f.k] = f; });

  var P = {
    role: "",           // "owner"（店長）/ "staff"（スタッフ）/ ""（まだ分からない）
    known: false,
    features: {},       // tenant.role_features
    canEdit: false,
    list: FEATURES,
    can: function (key, role) {
      role = role || P.role;
      var f = BY[key];
      var set = (P.features && P.features[role === "owner" ? "owner" : "staff"]) || {};
      if (role === "owner") {
        if (f && f.lock) return true;
        return set[key] !== false;
      }
      if (f && f.boss) return false;
      if (!f) {
        var page = key.split("#")[0];
        if (key.indexOf("#") > -1) return P.can(page, role);
        return !BOSS_PAGES[page];
      }
      return set.hasOwnProperty(key) ? set[key] === true : !!f.staff;
    },
    ready: function (cb) { if (P.known) cb(P); else WAIT.push(cb); }
  };
  var WAIT = [];
  window.DANDORI_PERM = P;

  function done() {
    P.known = true;
    var w = WAIT; WAIT = [];
    w.forEach(function (cb) { try { cb(P); } catch (e) {} });
  }

  /* ---------------------------------------------------- 1. まず隠します */
  var st = document.createElement("style");
  st.textContent =
    /* 目印は <html> に付けます（画面のJSが body の class を書きかえるため） */
    "html:not(.is-boss) [data-boss]{display:none !important}";
  (document.head || document.documentElement).appendChild(st);

  var CFG = window.DANDORI_CONFIG || {};
  if (!window.supabase || !CFG.supabaseUrl) { done(); return; }
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  /* ------------------------------------------- 2. 権限と、使える機能を調べます */
  sb.auth.getSession().then(function (r) {
    var u = r && r.data && r.data.session && r.data.session.user;
    if (!u) { done(); return; }
    return sb.rpc("role_features_get").then(function (q) {
      var d = q.data || {};
      P.role = d.role || "";
      P.features = d.features || {};
      P.canEdit = !!d.can_edit;
      if (P.role === "owner") document.documentElement.classList.add("is-boss");
      done();
      hideAll();
    });
  }).catch(function () { done(); hideAll(); });

  /* ---------------------------------- 3. 使えないタブ・ボタンを消します */
  function page() {
    var p = location.pathname.split("/").pop() || "index.html";
    return p;
  }

  function hideAll() {
    run();
    /* タブがあとから描かれる画面のために、少しだけ見張ります */
    var n = 0;
    var t = setInterval(function () {
      run();
      if (++n > 20) clearInterval(t);   // 約5秒で終わります
    }, 250);
  }

  function run() {
    var nav = document.querySelector("nav.tabs");
    if (!nav) return;
    var pg = page(), gone = [];

    Array.prototype.forEach.call(nav.querySelectorAll("button"), function (b) {
      var v = b.getAttribute("data-view") || b.getAttribute("data-t") ||
              b.getAttribute("data-k") || "";
      var off = (b.hasAttribute("data-boss") && P.role !== "owner") ||
                (v && !P.can(pg + "#" + v));
      if (!off) return;
      if (v) gone.push(v);
      if (b.parentNode) b.parentNode.removeChild(b);
    });
    if (!gone.length) return;

    gone.forEach(function (v) {
      var el = document.getElementById("view-" + v) ||
               document.getElementById("s-" + v) ||
               document.getElementById("p-" + v);
      if (el) { el.classList.add("hidden"); el.hidden = true; }
    });

    /* 前に開いていたタブの記憶が、消したタブだったら捨てます */
    try {
      for (var i = localStorage.length - 1; i >= 0; i--) {
        var k = localStorage.key(i);
        if (k && k.indexOf("-tab-") > -1 && gone.indexOf(localStorage.getItem(k)) > -1) {
          localStorage.removeItem(k);
        }
      }
    } catch (e) {}

    /* いま選ばれているタブが消えていたら、いちばん左に戻します */
    var cur = nav.querySelector('button[aria-selected="true"]');
    if (!cur) {
      var first = nav.querySelector("button");
      if (first) first.click();
    }
  }
})();
