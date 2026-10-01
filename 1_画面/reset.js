/* ============================================================================
   だんどりシリーズ / パスワードの変更（メールのリンクから開く画面）
   reset.js
   置き場所： サイトのルート（reset.html と同じ階層）

   ログイン画面の「パスワードをお忘れですか」から送られたメールの
   リンクを開くと、この画面が出ます。
   リンクの中に一時的な合言葉が入っているので、それを使って
   新しいパスワードを決めます。
   ============================================================================ */

(function () {
  "use strict";

  var MIN = 8;
  var CFG = window.DANDORI_CONFIG || {};
  var $ = function (id) { return document.getElementById(id); };

  function show(which) {
    ["rsWait", "rsBad", "rsForm"].forEach(function (id) {
      var e = $(id);
      if (e) e.classList.toggle("hidden", id !== which);
    });
  }

  function say(t, kind) {
    var m = $("rsMsg");
    if (m) { m.textContent = t; m.className = kind || ""; }
  }

  /* 見た目を、ほかの画面とそろえます（明るい／暗いの着せ替え） */
  document.body.className = "rs theme-" + (CFG.theme || "standard");

  if (!window.supabase || !CFG.supabaseUrl) { show("rsBad"); return; }
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  /* メールのリンクに入っている合言葉は、supabase が読みこんでくれます。
     読みこみが終わるのを少し待ってから、様子を見ます。 */
  var tries = 0;
  function look() {
    sb.auth.getSession().then(function (r) {
      var s = r && r.data && r.data.session;
      if (s) { show("rsForm"); $("rsA").focus(); return; }
      /* 古い形のリンク（#error=... ）が来ることもあります */
      if ((location.hash || "").indexOf("error") > -1) { show("rsBad"); return; }
      if (++tries > 12) { show("rsBad"); return; }   // 約3秒待ちます
      setTimeout(look, 250);
    }).catch(function () { show("rsBad"); });
  }
  look();

  $("rsSave").addEventListener("click", function () {
    var a = $("rsA").value, b = $("rsB").value;
    if (a.length < MIN) { say(MIN + "文字以上にしてください。", "ng"); return; }
    if (a !== b) { say("2つが同じではありません。", "ng"); return; }
    $("rsSave").disabled = true;
    say("変えています…");
    sb.auth.updateUser({ password: a }).then(function (r) {
      $("rsSave").disabled = false;
      if (r.error) { say(r.error.message || "うまくいきませんでした。", "ng"); return; }
      say("変えました。新しいパスワードでログインしてください。", "ok");
      $("rsSave").textContent = "ログイン画面へ";
      $("rsSave").onclick = function () { location.href = "index.html"; };
    }).catch(function (e) {
      $("rsSave").disabled = false;
      say(String(e && e.message || e), "ng");
    });
  });
})();
