/* ============================================================================
   だんどりシリーズ / 画面の見た目をあてる
   ui.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： supabase.js → config.js → ui.js → その画面のJS

   やること
     1. 前に使っていた見た目を、この端末の控えからすぐ当てます（ちらつき防止）
     2. そのあとサーバーの値を読んで、正しいものに直します
     3. ヘッダーに「画面の見た目」を出します

   だいじなこと
     ・見た目は<人ごと>です。ほかの人には影響しません。
     ・お客様のネット予約ページには入れません。お店の顔なので、
       スタッフの好みで変わってはいけないためです。
   ============================================================================ */

(function () {
  "use strict";

  var KEY = "dandori-ui-pref";
  var CFG = window.DANDORI_CONFIG || {};

  var SB = null;
  var FONTS = ["udp", "sans", "round", "serif", "system"];
  var PRESETS = ["standard", "large", "night", "contrast"];

  /* 見せ方ごとの、もとの文字の大きさ（px） */
  function baseSize(preset) { return preset === "large" ? 19 : 15; }

  /* ------------------------------------------------ __ACCENT__ ボタンの色

     背景色をお選びいただいたときに、ボタンやタブの色も、
     その背景に合わせた濃さ・色あいに切りかえます。
     （これまでは、背景を変えても金色のままでした）

       明るい背景 → 同じ色あいの「濃い色」＋白い文字
       暗い背景   → 同じ色あいの「明るい色」＋黒い文字

     どんな組み合わせでも読めるよう、明るさの差をとってから決めています。
  */

  function hex2rgb(h) {
    h = String(h || "").replace("#", "");
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (!/^[0-9a-fA-F]{6}$/.test(h)) return null;
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16),
            parseInt(h.slice(4, 6), 16)];
  }

  function rgb2hsl(c) {
    var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    var h = 0, sa = 0, l = (mx + mn) / 2, d = mx - mn;
    if (d) {
      sa = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0));
      else if (mx === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h = h / 6;
    }
    return [h, sa, l];
  }

  function hsl2hex(h, sa, l) {
    function f(n) {
      var k = (n + h * 12) % 12;
      var a = sa * Math.min(l, 1 - l);
      var v = l - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)));
      var x = Math.round(v * 255);
      return (x < 16 ? "0" : "") + x.toString(16);
    }
    return "#" + f(0) + f(8) + f(4);
  }

  /*  その色が、どれくらい明るく見えるか（0〜1） */
  function lum(c) {
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;
  }

  /*  背景の色から、画面ぜんぶの色を決めます。

      ボタンだけを変えると、カード（白）とちぐはぐになるので、
      カードの色・線の色・うすい文字の色も、いっしょに決めています。

      戻り値：
        on   … ボタン・タブの色
        dim  … そのうすいほう（枠線など）
        onInk… ボタンの上の文字の色
        panel / panel2 / line / muted / ink … 画面ぜんぶ  */
  function accentFrom(bg) {
    var c = hex2rgb(bg);
    if (!c) return null;
    var hsl = rgb2hsl(c), h = hsl[0], sa = hsl[1], bl = hsl[2];
    var light = lum(c) > 0.55;

    /*  ほとんど灰色のときは、少しだけ色みを足します（真っ白・真っ黒のとき） */
    var asa = sa;
    if (asa < 0.08) { asa = 0.10; h = 0.11; }      /* すこし温かい色あい */
    asa = Math.max(0.30, Math.min(0.62, asa));

    /*  カードは、背景から少しだけずらします（浮いて見えるように） */
    var psa = Math.min(sa * 0.45, 0.16);
    var pl  = light ? Math.min(bl + 0.055, 0.995) : Math.min(bl + 0.052, 0.34);
    var p2l = light ? Math.min(bl + 0.028, 0.99)  : Math.min(bl + 0.026, 0.30);
    var ll  = light ? Math.max(bl - 0.115, 0.55)  : Math.min(bl + 0.135, 0.42);

    return {
      on:     hsl2hex(h, asa, light ? 0.30 : 0.66),
      dim:    hsl2hex(h, asa * 0.7, light ? 0.55 : 0.42),
      onInk:  light ? "#FFFFFF" : "#14191F",
      panel:  hsl2hex(h, psa, pl),
      panel2: hsl2hex(h, psa, p2l),
      line:   hsl2hex(h, psa, ll),
      muted:  hsl2hex(h, Math.min(sa * 0.3, 0.14), light ? 0.42 : 0.66),
      ink:    light ? "#14181D" : "#EDF1F6"
    };
  }

  /* ---------------------------------------------------------- 当てる */

  /*  前回当てた内容。同じなら何もしません（当て直すたびに描き直されて
      ちらつくのを防ぎます。OS がダークモードのときに目立っていました） */
  var LAST_SIG = null;

  function apply(p) {
    p = p || {};
    var b = document.body;
    if (!b) return;

    var preset = PRESETS.indexOf(p.preset) >= 0 ? p.preset : "standard";

    /* 見せ方。ほかのJSが className を書きかえることがあるので、
       いまの class から自分のぶんだけ外して付け直します。 */
    var keep = (b.className || "").split(/\s+/).filter(function (c) {
      return c && c.indexOf("theme-") !== 0 && c.indexOf("force-") !== 0 &&
             c.indexOf("font-") !== 0;
    });
    keep.push("theme-" + preset);

    /* ライト／ダークの上書き */
    var sc = p.scheme || "theme";
    if (sc === "auto") {
      sc = (window.matchMedia &&
            window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light";
    }
    if (sc === "light" || sc === "dark") keep.push("force-" + sc);

    /* フォント */
    if (FONTS.indexOf(p.font) >= 0) keep.push("font-" + p.font);

    var cls = keep.join(" ");
    var sig = cls + "|" + JSON.stringify([p.text_size, p.bg_color, p.ink_color, p.bg_art, p.bg_image, p.bg_url]);
    if (sig === LAST_SIG && b.className === cls) return;   /* 変わっていない */
    LAST_SIG = sig;
    if (b.className !== cls) b.className = cls;

    /* 文字の大きさ。100（標準）のときは、見せ方のままにします。 */
    var n = Number(p.text_size || 0);
    b.style.fontSize = (n && n !== 100) ? (baseSize(preset) * n / 100).toFixed(1) + "px" : "";

    /* 背景色・文字色 */
    b.style.setProperty("--bg", p.bg_color || "");
    b.style.setProperty("--ink", p.ink_color || "");
    if (p.bg_color) b.style.backgroundColor = p.bg_color; else b.style.backgroundColor = "";

    /*  __ACCENT__ ボタン・カード・線の色も、背景に合わせます。
        背景が「標準」のときは、見せ方の色をそのまま使います。 */
    var ac = p.bg_color ? accentFrom(p.bg_color) : null;
    var PROPS = ["--gold", "--gold-dim", "--on-gold", "--panel", "--panel2",
                 "--line", "--muted"];
    if (ac) {
      b.style.setProperty("--gold", ac.on);
      b.style.setProperty("--gold-dim", ac.dim);
      b.style.setProperty("--on-gold", ac.onInk);
      b.style.setProperty("--panel", ac.panel);
      b.style.setProperty("--panel2", ac.panel2);
      b.style.setProperty("--line", ac.line);
      b.style.setProperty("--muted", ac.muted);
      /*  文字の色をお選びでないときは、背景に合う色を当てます。
          （明るい背景に白文字、暗い背景に黒文字、を防ぎます） */
      if (!p.ink_color) b.style.setProperty("--ink", ac.ink);
    } else {
      PROPS.forEach(function (k) { b.style.removeProperty(k); });
    }

    /* 背景のかざり */
    if (window.DANDORI_ART) {
      if (p.bg_art === "photo") {
        /*  取りこんだ写真は、見るためのアドレスを取ってから当てます。
            控えておいた前回のアドレスがあれば、先にそれを当てます。 */
        if (p.bg_url) window.DANDORI_ART.set("photo", p.bg_url);
        if (window.DANDORI_PHOTO && SB && p.bg_image) {
          window.DANDORI_PHOTO.signed(SB, p.bg_image).then(function (u) {
            if (!u) return;
            p.bg_url = u;
            remember(p);
            window.DANDORI_ART.set("photo", u);
          });
        }
      } else {
        window.DANDORI_ART.set(p.bg_art || "off");
      }
    }
  }

  /*  各画面の JS が「この画面の既定の見た目」を当てるときの窓口。
      ui.js が入っている画面では、その人の見た目の設定（無ければ標準）を
      そのまま当て直します。以前は各画面が className を丸ごと書きかえ、
      250ms 後にここが戻していたため、OS がダークモードのときに
      暗い→明るいの往復でちらついていました。 */
  function theme(name) {
    apply(cached());
  }

  /* この端末の控え */
  function cached() {
    try { return JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) { return null; }
  }
  function remember(p) {
    try { localStorage.setItem(KEY, JSON.stringify(p || {})); } catch (e) {}
  }

  /* ---------------------------------------------------------- 起動 */

  function start() {
    apply(cached());          /* まず控えを当てて、ちらつきを防ぎます */
    inject();

    if (!window.supabase || !CFG.supabaseUrl) return;
    var sb = SB = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

    sb.auth.getSession().then(function (r) {
      if (!(r && r.data && r.data.session)) return;   /* ログイン前はそのまま */
      return sb.rpc("ui_pref_get", {}).then(function (q) {
        if (q.error || !q.data) return;               /* 020 が未実行でも落ちません */
        remember(q.data);
        if (!window.DANDORI_UI_HOLD) apply(q.data);
      });
    }).catch(function () {});
  }

  /* ヘッダーに「画面の見た目」を出します */
  function inject() {
    var lo = document.getElementById("logoutBtn");
    if (!lo || document.getElementById("mtBtn")) return;
    var a = document.createElement("a");
    a.id = "mtBtn";
    a.className = lo.className || "btn ghost";
    a.setAttribute("style", (lo.getAttribute("style") || "") + ";text-decoration:none");
    a.href = "theme.html";
    a.textContent = "見た目";
    lo.parentNode.insertBefore(a, lo);
  }

  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  ready(function () {
    start();
    /* ほかのJSが class を書きかえたあとに、当て直します。
       設定ページでプレビュー中は、じゃまをしないように止めます。 */
    var n = 0;
    var t = setInterval(function () {
      if (!window.DANDORI_UI_HOLD) apply(cached());
      inject();
      if (++n > 20) clearInterval(t);
    }, 250);
    /*  class が書きかわった瞬間に当て直します（一瞬でも別の見た目が
        出ないように）。自分の書きかえは apply が同じ内容と判定して止まります。 */
    if (window.MutationObserver && document.body) {
      new MutationObserver(function () {
        if (!window.DANDORI_UI_HOLD) apply(cached());
      }).observe(document.body, { attributes: true, attributeFilter: ["class"] });
    }
  });

  /* 設定ページから呼びます */
  window.DANDORI_UI = { apply: apply, remember: remember, cached: cached, theme: theme };
})();
