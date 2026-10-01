/* ============================================================================
   だんどりシリーズ / 左の目次（サイドメニュー）
   menu.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： いちばん最後（ui.js・pw.js が足したボタンも拾うため）

   やること
     ・左はしに、たての目次を出します
     ・「毎日つかう」「お金」「人・シフト」…と、やることの大分類でまとめます
     ・いちばん下に、いまログインしている方のお名前を出します
     ・上のならびは <使い方・パスワード・ログアウト> だけにします。
       ほかのボタンは、左の目次とダブるので、隠します。
     ・画面がせまいとき（スマホ）は、左上の ☰ でひらきます

   ★ 見た目（CSS）は、このファイルの中から差しこんでいます。
     style.css がブラウザに古いまま残っていても、ちゃんと効きます。
   ============================================================================ */

(function () {
  "use strict";

  /* -------------------------------------------------- 大分類のならび順 */

  var GROUPS = [
    { t: "毎日つかう", files: [
      "index.html", "floor.html", "karte.html", "hotel.html",
      "ride.html", "rides.html", "dispatch.html", "rooms.html",
      "customers.html", "guest.html"] },
    { t: "お金", files: [
      "sale.html", "sales.html", "close.html", "daily.html", "cost.html",
      "report.html", "hq.html"] },
    { t: "人・シフト", files: [
      "payroll.html", "shift.html", "shiftwish.html"] },
    { t: "お店のそなえ", files: [
      "stock.html", "souji.html", "docs.html", "check.html"] },
    { t: "設定", files: ["admin.html", "login.html", "theme.html"] },
    { t: "", files: ["teian.html"] }
  ];

  /*  上のならびに、そのまま残すもの
      （まちがえると面倒なもの・別タブでひらくもの） */
  var KEEP = { "guide.html": 1 };

  /*  店長以上の方だけに出す画面。
      スタッフさんには、目次から消し、直接ひらいても戻します。
      （画面で隠すだけでなく、データベース側でもふたをしています） */
  var BOSS = {
    "sales.html": 1,      /* ナイト・売上 */
    "admin.html": 1,      /* 設定 */
    "login.html": 1,      /* ログインの管理 */
    "hq.html": 1          /* キャスト・本部（多店舗） */
  };

  /*  業種ごとの、画面のならび（どのページから開いても、同じ目次が出ます） */
  var CAT = {
    night: {
      "index.html": "伝票・会計", "customers.html": "お客様", "rides.html": "送り",
      "close.html": "締め・日報",
      "sales.html": "売上", "payroll.html": "キャスト・給与",
      "shiftwish.html": "シフト希望", "stock.html": "在庫・発注",
      "souji.html": "清掃・やること", "docs.html": "届出・許可証",
      "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
      "teian.html": "こんなこともできます"
    },
    cast: {
      "index.html": "受付", "dispatch.html": "配車", "rooms.html": "部屋・備品",
      "report.html": "売上・集客", "hq.html": "本部（多店舗）",
      "payroll.html": "出勤・報酬",
      "shiftwish.html": "シフト希望", "stock.html": "在庫・発注",
      "souji.html": "清掃・やること", "docs.html": "届出・許可証",
      "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
      "teian.html": "こんなこともできます"
    },
    food: {
      "index.html": "きょう", "floor.html": "卓・オーダー", "guest.html": "集客",
      "daily.html": "締め", "cost.html": "仕入・原価", "shift.html": "シフト・給与",
      "souji.html": "清掃・やること", "check.html": "衛生・本部",
      "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
      "teian.html": "こんなこともできます"
    },
    salon: {
      "index.html": "きょう", "karte.html": "カルテ", "guest.html": "集客",
      "sale.html": "お会計・売上", "stock.html": "店販・在庫",
      "shiftwish.html": "シフト希望", "souji.html": "清掃・やること",
      "docs.html": "届出・許可証", "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
      "teian.html": "こんなこともできます"
    },
    pet: {
      "index.html": "きょう", "karte.html": "カルテ", "guest.html": "集客",
      "sale.html": "お会計・売上", "hotel.html": "ホテル・保育園",
      "ride.html": "送迎", "shiftwish.html": "シフト希望",
      "souji.html": "清掃・やること", "docs.html": "届出・許可証",
      "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
      "teian.html": "こんなこともできます"
    }
  };

  /*  いま開いている画面の名前（ヘッダーにリンクが無いため） */
  var SELF = {
    "index.html": "きょう", "floor.html": "卓・オーダー", "karte.html": "カルテ",
    "hotel.html": "ホテル・保育園", "ride.html": "送迎", "rides.html": "送り",
    "dispatch.html": "配車", "rooms.html": "部屋・備品", "customers.html": "お客様",
    "guest.html": "集客", "sale.html": "お会計・売上", "sales.html": "売上",
    "close.html": "締め・日報",
    "daily.html": "締め", "cost.html": "仕入・原価", "report.html": "売上・集客",
    "hq.html": "本部（多店舗）",
    "payroll.html": "給与", "shift.html": "シフト・給与", "shiftwish.html": "シフト希望",
    "stock.html": "在庫・発注", "souji.html": "清掃・やること",
    "docs.html": "届出・許可証", "check.html": "衛生・本部",
    "admin.html": "設定", "login.html": "ログインの管理",
      "theme.html": "見た目",
    "teian.html": "こんなこともできます"
  };

  var ROLE = {
    owner: "オーナー", manager: "店長", staff: "スタッフ", driver: "ドライバー"
  };

  /* ------------------------------------------------------------ 見た目 */

  var CSS =
  ".side-moved{display:none !important}" +
  "#sidemenu{position:fixed; top:0; left:0; bottom:0; width:222px; z-index:46;" +
    "background:var(--panel2); border-right:1px solid var(--line);" +
    "overflow:auto; -webkit-overflow-scrolling:touch; display:flex;" +
    "flex-direction:column; transform:translateX(-100%); transition:transform .18s ease}" +
  "html.side-open #sidemenu{transform:none}" +
  "#sideVeil{position:fixed; inset:0; z-index:45; background:rgba(0,0,0,.45); display:none}" +
  "html.side-open #sideVeil{display:block}" +
  ".side-top{padding:16px 16px 12px; border-bottom:1px solid var(--line)}" +
  ".side-brand{display:block; font-size:11px; letter-spacing:.18em;" +
    "color:var(--gold); font-weight:700}" +
  ".side-kind{display:block; font-size:14.5px; font-weight:700; margin-top:3px;" +
    "color:var(--ink)}" +
  "#sidemenu nav{padding:6px 8px 10px; flex:1 1 auto}" +
  ".side-g{font-size:11px; letter-spacing:.1em; color:var(--muted); font-weight:700;" +
    "padding:15px 10px 5px}" +
  ".side-sep{height:1px; background:var(--line); margin:14px 10px 6px}" +
  ".side-i{display:flex; align-items:center; gap:10px; padding:9px 10px;" +
    "border-radius:9px; text-decoration:none; color:var(--ink);" +
    "font-size:13.5px; line-height:1.35}" +
  ".side-i:hover{background:rgba(127,127,127,.14)}" +
  ".side-i .n{flex:none; width:19px; font-size:10.5px; color:var(--muted);" +
    "opacity:.75; font-variant-numeric:tabular-nums}" +
  ".side-i .t{overflow:hidden; text-overflow:ellipsis; white-space:nowrap}" +
  ".side-i.on{background:var(--gold); color:var(--on-gold,#14191F); font-weight:700}" +
  ".side-i.on .n{color:rgba(0,0,0,.45); opacity:1}" +
  ".side-me{flex:none; margin:6px 8px 14px; padding:11px 12px; border-radius:10px;" +
    "background:rgba(127,127,127,.12); border:1px solid var(--line)}" +
  ".side-me .k{display:block; font-size:10.5px; letter-spacing:.08em;" +
    "color:var(--muted)}" +
  ".side-me .nm{display:block; font-size:14.5px; font-weight:700; margin-top:2px;" +
    "color:var(--ink); overflow:hidden; text-overflow:ellipsis; white-space:nowrap}" +
  ".side-me .rl{display:inline-block; margin-top:4px; font-size:11px;" +
    "color:var(--gold); border:1px solid var(--gold-dim); border-radius:999px;" +
    "padding:1px 8px}" +
  "#sideBtn{padding:7px 12px; font-size:16px; line-height:1}" +
  /*  長いお知らせが1行で切れてしまわないようにします */
  "#toast .toast{max-width:min(92vw,720px); white-space:normal;" +
    "word-break:break-word; line-height:1.7; text-align:left}" +
  "@media (min-width:1000px){" +
    "html.hasside #sidemenu{transform:none}" +
    "html.hasside header .brand{display:none}" +
    "html.hasside #app{padding-left:222px}" +
    "html.hasside #sideBtn{display:none}" +
    "html.hasside #sideVeil{display:none !important}}" +
  "@media print{#sidemenu,#sideVeil,#sideBtn{display:none !important}" +
    "html.hasside #app{padding-left:0}}";

  (function () {
    var st = document.createElement("style");
    st.id = "sideCss";
    st.textContent = CSS;
    (document.head || document.documentElement).appendChild(st);
  })();

  /* ------------------------------------------------------------ 組み立て */

  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function base(href) {
    if (!href) return "";
    var s = String(href).split("#")[0].split("?")[0];
    var i = s.lastIndexOf("/");
    return (i < 0 ? s : s.slice(i + 1)).toLowerCase();
  }

  ready(function () {
    var app = document.getElementById("app");
    var who = document.querySelector("header .who");
    if (!app || !who) return;
    if (document.getElementById("sidemenu")) return;

    var CFG = window.DANDORI_CONFIG || {};
    var ISBOSS = false;        /* 店長以上か */
    var ROLEKNOWN = false;     /* まだ調べ終わっていないあいだは、隠しません */
    var found = {};
    var cur = base(location.pathname) || "index.html";

    var cat = CAT[CFG.industry] || null;
    if (cat) {
      for (var f0 in cat) { if (cat.hasOwnProperty(f0)) found[f0] = cat[f0]; }
    }
    if (!found[cur] && !KEEP[cur]) {
      found[cur] = SELF[cur] || (document.title.split("｜")[1] || "この画面");
    }

    /*  上のならびから、左に移すものを隠します。
        ダブって出ないように、class と style の両方で隠します。 */
    function scan() {
      Array.prototype.forEach.call(who.querySelectorAll("a[href]"), function (a) {
        var f = base(a.getAttribute("href"));
        if (!f || f.slice(-5) !== ".html") return;
        if (KEEP[f]) return;                       /* 使い方は上に残します */
        var txt = (a.textContent || "").replace(/^[←\s]+/, "").trim();
        if (!found[f]) found[f] = txt || SELF[f] || f;
        a.classList.add("side-moved");
        a.style.display = "none";
      });
      /*  お名前も、左のいちばん下に出すので、上からは消します */
      var mn = document.getElementById("meName");
      if (mn) { mn.classList.add("side-moved"); mn.style.display = "none"; }
    }
    scan();

    var brand = (document.title.split("｜")[0] || "だんどり").trim();

    var side = document.createElement("aside");
    side.id = "sidemenu";
    app.insertBefore(side, app.firstChild);

    /*  画面によっては「鈴木（オーナー）」のように、
        お名前と権限がひとつづきで入っています。分けて出します。 */
    function raw() {
      var mn = document.getElementById("meName");
      var n = mn ? (mn.textContent || "").trim() : "";
      if (n) return n;
      var S = (window.K && window.K.S) || (window.D && window.D.S) || null;
      return (S && S.me && S.me.name) || "";
    }

    function meName() {
      return raw().replace(/[（(][^）)]*[）)]\s*$/, "").trim();
    }

    function meRole() {
      var S = (window.K && window.K.S) || (window.D && window.D.S) || null;
      var r = S && S.me && S.me.role;
      if (ROLE[r]) return ROLE[r];
      var m = raw().match(/[（(]([^）)]*)[）)]\s*$/);
      return m ? m[1].trim() : "";
    }

    function draw() {
      var h = ["<div class='side-top'>" +
               "<span class='side-brand'>DANDORI</span>" +
               "<span class='side-kind'>" + esc(brand) + "</span></div><nav>"];
      var no = 0;
      GROUPS.forEach(function (g) {
        var items = g.files.filter(function (f) {
          if (!found[f]) return false;
          if (BOSS[f] && ROLEKNOWN && !ISBOSS) return false;
          return true;
        });
        if (!items.length) return;
        if (g.t) h.push("<div class='side-g'>" + esc(g.t) + "</div>");
        else h.push("<div class='side-sep'></div>");
        items.forEach(function (f) {
          no++;
          var on = (f === cur);
          h.push("<a class='side-i" + (on ? " on" : "") + "' href='" + f + "'" +
                 (on ? " aria-current='page'" : "") + ">" +
                 "<span class='n'>" + (no < 10 ? "0" + no : no) + "</span>" +
                 "<span class='t'>" + esc(found[f]) + "</span></a>");
        });
      });
      h.push("</nav>");

      var nm = meName();
      h.push("<div class='side-me'><span class='k'>ログイン中</span>" +
             "<span class='nm'>" + esc(nm || "—") + "</span>" +
             (meRole() ? "<span class='rl'>" + esc(meRole()) + "</span>" : "") +
             "</div>");
      side.innerHTML = h.join("");
    }
    draw();

    /* ------------------------------------- 画面がせまいときのボタン */

    var bar = document.createElement("button");
    bar.id = "sideBtn";
    bar.type = "button";
    bar.className = "btn ghost";
    bar.setAttribute("aria-label", "メニュー");
    bar.textContent = "☰";
    var head = who.parentNode;
    head.insertBefore(bar, head.firstChild);

    var HT = document.documentElement;
    function open() { HT.classList.add("side-open"); }
    function close() { HT.classList.remove("side-open"); }
    bar.addEventListener("click", function () {
      if (HT.classList.contains("side-open")) close(); else open();
    });

    var veil = document.createElement("div");
    veil.id = "sideVeil";
    app.insertBefore(veil, side.nextSibling);
    veil.addEventListener("click", close);
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") close();
    });

    HT.classList.add("hasside");

    /* ------------------------------------------- 真っ白のまま止まったとき
       ログインの控えは残っているのに、そのアカウントのスタッフ登録が
       見つからない、といったときに、画面がどちらも出ないことがあります。
       3秒半たってもどちらも出ていなければ、ログイン画面を出して、
       理由と抜け道（控えを消す）をご案内します。 */
    window.setTimeout(function () {
      var lg = document.getElementById("login");
      var ap = document.getElementById("app");
      if (!lg || !ap) return;
      if (!lg.classList.contains("hidden")) return;
      if (!ap.classList.contains("hidden")) return;

      lg.classList.remove("hidden");
      var box = lg.querySelector(".login-box");
      if (!box || document.getElementById("bootNote")) return;

      var d = document.createElement("div");
      d.id = "bootNote";
      d.setAttribute("style",
        "margin-top:14px;padding:11px 13px;border-radius:9px;font-size:13px;" +
        "line-height:1.75;background:rgba(180,118,42,.14);color:var(--ink,#222)");
      d.innerHTML =
        "<b>画面を出せませんでした。</b><br>" +
        "このアカウントには、こちらの業種のスタッフ登録がないようです。<br>" +
        "ほかのアカウントでお入りいただくか、担当までご連絡ください。";

      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "btn ghost";
      btn.setAttribute("style", "margin-top:10px");
      btn.textContent = "この端末のログインを消して、入り直す";
      btn.addEventListener("click", function () {
        try {
          var kill = [];
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (k && (k.indexOf("sb-") === 0 || k.indexOf("supabase") > -1)) kill.push(k);
          }
          kill.forEach(function (k) { localStorage.removeItem(k); });
        } catch (e) {}
        location.reload();
      });
      d.appendChild(btn);
      box.appendChild(d);
    }, 3500);

    /* ------------------------------------------- 店長以上かどうかを調べます */
    (function () {
      var CF = window.DANDORI_CONFIG || {};
      if (!window.supabase || !CF.supabaseUrl) { ROLEKNOWN = true; return; }
      var c = window.supabase.createClient(CF.supabaseUrl, CF.supabaseAnonKey);
      c.auth.getSession().then(function (r) {
        var u = r && r.data && r.data.session && r.data.session.user;
        if (!u) { ROLEKNOWN = true; return; }
        return c.from("staff").select("role").eq("auth_user_id", u.id).limit(1)
          .then(function (q) {
            var role = (q.data && q.data[0] && q.data[0].role) || "";
            ISBOSS = (role === "owner" || role === "manager");
            ROLEKNOWN = true;
            draw();
            /*  スタッフさんが、店長以上の画面を直接ひらいたとき */
            if (!ISBOSS && BOSS[cur]) {
              location.replace("index.html");
            }
          });
      }).catch(function () { ROLEKNOWN = true; });
    })();

    /* ------------------------------------------- ログアウトを確実にします
       画面によっては、サーバーからの返事を待ってから画面を出し直す作りに
       なっていて、返事が来ないと「押しても反応しない」ことがありました。
       いったんボタンを作り直して、
         ・押したら必ず画面を出し直す（1.5秒で見切ります）
         ・この端末に残っているログインの控えも消す
       ようにします。 */
    (function () {
      var lo = document.getElementById("logoutBtn");
      if (!lo) return;
      var nb = lo.cloneNode(true);            /* 前の押したときの動きを外します */
      lo.parentNode.replaceChild(nb, lo);

      var done = false;
      function bye() {
        if (done) return;
        done = true;
        try {
          var kill = [];
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (k && (k.indexOf("sb-") === 0 || k.indexOf("supabase") > -1)) kill.push(k);
          }
          kill.forEach(function (k) { localStorage.removeItem(k); });
        } catch (e) {}
        location.replace("index.html");
      }

      nb.addEventListener("click", function () {
        nb.disabled = true;
        nb.textContent = "ログアウト中…";
        window.setTimeout(bye, 1500);         /* 返事が来なくても進みます */
        try {
          var CF = window.DANDORI_CONFIG || {};
          var c = window.supabase.createClient(CF.supabaseUrl, CF.supabaseAnonKey);
          c.auth.signOut().then(bye, bye);
        } catch (e) { bye(); }
      });
    })();

    /*  ui.js・pw.js・ログイン後の読みこみが、あとから入るので見張ります */
    var n = 0;
    var last = "";
    var t = setInterval(function () {
      var before = 0;
      for (var k in found) { if (found.hasOwnProperty(k)) before++; }
      scan();
      var after = 0;
      for (var k2 in found) { if (found.hasOwnProperty(k2)) after++; }
      var nm = raw();
      if (after !== before || nm !== last) { last = nm; draw(); }
      if (++n > 24) clearInterval(t);
    }, 250);
  });
})();
