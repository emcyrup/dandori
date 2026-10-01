/* ============================================================================
   だんどりシリーズ / 画面の出し分け
   perm.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： supabase.js → config.js → perm.js → その画面のJS

   やること
     data-boss="1" が付いているもの（タブ・ボタンなど）を、
     店長以上（owner / manager）の方にだけ見せます。

     ・はじめは CSS で隠しておきます（ちらつき防止）
     ・ログインしている方が店長以上なら、body に is-boss を付けて出します
     ・そうでなければ、ボタンごと消して、そのページも隠します
       （前に開いていたタブの記憶も消して、いちばん左のタブに戻します）

   だいじなこと
     これは「見せない」だけのしくみです。
     ほんとうのふたは、データベース側（019_kengen.sql）で閉めています。
     この画面のJSを書きかえても、売上や歩合は取り出せません。
   ============================================================================ */

(function () {
  "use strict";

  /* ---------------------------------------------------- 1. まず隠します */
  var st = document.createElement("style");
  st.textContent =
    /* 画面のJSが body の class を書きかえることがあるので、
       目印は <html> のほうに付けます。
       あとから描かれるボタンにも効くように、CSSで隠します。 */
    "html:not(.is-boss) [data-boss]{display:none !important}";
  (document.head || document.documentElement).appendChild(st);

  var CFG = window.DANDORI_CONFIG || {};
  if (!window.supabase || !CFG.supabaseUrl) return;
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  /* ---------------------------------------------- 2. 店長以上かを調べます */
  sb.auth.getSession().then(function (r) {
    var u = r && r.data && r.data.session && r.data.session.user;
    if (!u) { hideAll(); return; }
    return sb.from("staff").select("role")
      .eq("auth_user_id", u.id).limit(1)
      .then(function (q) {
        var role = (q.data && q.data[0] && q.data[0].role) || "";
        if (role === "owner" || role === "manager") {
          document.documentElement.classList.add("is-boss");
        } else {
          hideAll();
        }
      });
  }).catch(function () { hideAll(); });

  /* ------------------------------------------- 3. 店長以上でなければ消す */
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
    var gone = [];

    Array.prototype.forEach.call(nav.querySelectorAll("button[data-boss]"), function (b) {
      var v = b.getAttribute("data-view") || b.getAttribute("data-t") ||
              b.getAttribute("data-k") || "";
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
