/* ============================================================================
   だんどりシリーズ / パスワードまわり
   pw.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： supabase.js → config.js → pw.js → その画面のJS

   やること
     1. ログインしたあとのヘッダーに「パスワード」を出します。
        ご本人が、自分のパスワードを変えられます。
        ★メールを使いません。Resendの設定が終わっていなくても動きます。★
     2. ログイン画面に「パスワードをお忘れですか」を出します。
        こちらはメールでお送りするので、メールの設定が済んでから使えます。

   だいじなこと
     ・変えられるのは、いまログインしているご本人のぶんだけです。
       他の人のパスワードは、この画面からは変えられません。
     ・8文字以上にしています（Supabaseの下限は6文字ですが、少し厳しめに）。
   ============================================================================ */

(function () {
  "use strict";

  var MIN = 8;
  var CFG = window.DANDORI_CONFIG || {};
  if (!window.supabase || !CFG.supabaseUrl) return;
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  /* ------------------------------------------------------------ 見た目 */
  var st = document.createElement("style");
  st.textContent =
    "#pwWrap{position:fixed;inset:0;z-index:9999;display:flex;align-items:center;" +
      "justify-content:center;background:rgba(0,0,0,.45);padding:16px}" +
    "#pwBox{background:var(--panel,#fff);color:var(--ink,#222);border:1px solid var(--line,#ddd);" +
      "border-radius:14px;padding:20px 22px;width:100%;max-width:420px;" +
      "font-family:inherit;box-shadow:0 18px 50px rgba(0,0,0,.28)}" +
    "#pwBox h2{margin:0 0 4px;font-size:18px}" +
    "#pwBox p.hint{margin:6px 0 14px;font-size:13px;color:var(--muted,#888);line-height:1.7}" +
    "#pwBox label{display:block;margin-bottom:12px}" +
    "#pwBox label span{display:block;font-size:12.5px;color:var(--muted,#888);margin-bottom:4px}" +
    "#pwBox input{width:100%;box-sizing:border-box;padding:11px 12px;font-size:16px;" +
      "font-family:inherit;border:1px solid var(--line,#ddd);border-radius:10px;" +
      "background:var(--panel2,var(--panel,#fff));color:var(--ink,#222)}" +
    "#pwBox .row{display:flex;gap:10px;justify-content:flex-end;margin-top:16px}" +
    "#pwMsg{font-size:13.5px;line-height:1.7;margin:10px 0 0;min-height:1.2em}" +
    "#pwMsg.ng{color:var(--bad,#b4564b)}#pwMsg.ok{color:var(--ok,#4c8f6a)}" +
    "#pwForgot{display:block;margin-top:14px;font-size:13px;text-align:center;" +
      "color:var(--muted,#888);background:none;border:0;width:100%;cursor:pointer;" +
      "font-family:inherit;text-decoration:underline}";
  (document.head || document.documentElement).appendChild(st);

  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function close() {
    var w = $("pwWrap");
    if (w && w.parentNode) w.parentNode.removeChild(w);
  }

  function open(inner) {
    close();
    var w = document.createElement("div");
    w.id = "pwWrap";
    w.innerHTML = '<div id="pwBox">' + inner + "</div>";
    w.addEventListener("click", function (e) { if (e.target === w) close(); });
    document.body.appendChild(w);
    document.addEventListener("keydown", function onEsc(e) {
      if (e.key === "Escape") { close(); document.removeEventListener("keydown", onEsc); }
    });
    return w;
  }

  function say(text, kind) {
    var m = $("pwMsg");
    if (m) { m.textContent = text; m.className = kind || ""; }
  }

  /* -------------------------------------------- 1. パスワードを変える */

  function changeBox() {
    open(
      "<h2>パスワードを変える</h2>" +
      "<p class='hint'>いまログインしている、ご自分のパスワードを変えます。" +
      "ほかの方のぶんは変えられません。<br>" + MIN + "文字以上にしてください。</p>" +
      "<label><span>新しいパスワード</span>" +
        "<input id='pwA' type='password' autocomplete='new-password'></label>" +
      "<label><span>もういちど、同じものを</span>" +
        "<input id='pwB' type='password' autocomplete='new-password'></label>" +
      "<p id='pwMsg'></p>" +
      "<div class='row'>" +
        "<button class='btn ghost' id='pwCancel'>やめる</button>" +
        "<button class='btn primary' id='pwSave'>変える</button></div>");

    $("pwCancel").addEventListener("click", close);
    $("pwA").focus();

    $("pwSave").addEventListener("click", function () {
      var a = $("pwA").value, b = $("pwB").value;
      if (a.length < MIN) { say(MIN + "文字以上にしてください。", "ng"); return; }
      if (a !== b) { say("2つが同じではありません。", "ng"); return; }
      $("pwSave").disabled = true;
      say("変えています…");
      sb.auth.updateUser({ password: a }).then(function (r) {
        $("pwSave").disabled = false;
        if (r.error) {
          say(r.error.message || "うまくいきませんでした。", "ng");
          return;
        }
        say("変えました。次からは新しいパスワードでログインしてください。", "ok");
        $("pwSave").textContent = "閉じる";
        $("pwSave").onclick = close;
      }).catch(function (e) {
        $("pwSave").disabled = false;
        say(String(e && e.message || e), "ng");
      });
    });
  }

  /* ------------------------------------ 2. パスワードをお忘れですか */

  function forgotBox() {
    var pre = ($("email") && $("email").value.trim()) || "";
    open(
      "<h2>パスワードをお忘れですか</h2>" +
      "<p class='hint'>ご登録のメールアドレスに、変更用のリンクをお送りします。" +
      "リンクを開くと、新しいパスワードを決められます。</p>" +
      "<label><span>メールアドレス</span>" +
        "<input id='pwMail' type='email' autocomplete='username' value='" + esc(pre) + "'></label>" +
      "<p id='pwMsg'></p>" +
      "<div class='row'>" +
        "<button class='btn ghost' id='pwCancel'>やめる</button>" +
        "<button class='btn primary' id='pwSend'>送る</button></div>");

    $("pwCancel").addEventListener("click", close);
    $("pwMail").focus();

    $("pwSend").addEventListener("click", function () {
      var m = $("pwMail").value.trim();
      if (!m || m.indexOf("@") < 0) { say("メールアドレスを入れてください。", "ng"); return; }
      $("pwSend").disabled = true;
      say("送っています…");
      var back = location.origin + location.pathname.replace(/[^/]*$/, "") + "reset.html";
      sb.auth.resetPasswordForEmail(m, { redirectTo: back }).then(function (r) {
        $("pwSend").disabled = false;
        if (r.error) { say(r.error.message || "うまくいきませんでした。", "ng"); return; }
        say("お送りしました。メールをご確認ください。" +
            "見あたらないときは、迷惑メールのフォルダもご覧ください。", "ok");
        $("pwSend").textContent = "閉じる";
        $("pwSend").onclick = close;
      }).catch(function (e) {
        $("pwSend").disabled = false;
        say(String(e && e.message || e), "ng");
      });
    });
  }

  /* ----------------------------------------------------- 画面に出します */

  function inject() {
    /* ヘッダーの「ログアウト」のとなり */
    var lo = $("logoutBtn");
    if (lo && !$("pwBtn")) {
      var b = document.createElement("button");
      b.id = "pwBtn";
      b.className = lo.className || "btn ghost";
      b.setAttribute("style", lo.getAttribute("style") || "");
      b.type = "button";
      b.textContent = "パスワード";
      b.addEventListener("click", changeBox);
      lo.parentNode.insertBefore(b, lo);
    }

    /* ログイン画面の下 */
    var f = $("loginForm");
    if (f && !$("pwForgot")) {
      var a = document.createElement("button");
      a.id = "pwForgot";
      a.type = "button";
      a.textContent = "パスワードをお忘れですか";
      a.addEventListener("click", forgotBox);
      f.appendChild(a);
    }
  }

  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  ready(function () {
    inject();
    /* あとから描かれる画面のために、少しだけ見張ります */
    var n = 0;
    var t = setInterval(function () {
      inject();
      if (++n > 20) clearInterval(t);
    }, 250);
  });
})();
