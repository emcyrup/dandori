/* ============================================================================
   だんどりシリーズ / 画面の見た目の設定
   theme.js
   置き場所： サイトのルート（theme.html と同じ階層）

   ここで選んだ見た目は、その人のぶんだけサーバーに覚えられます。
   保存する前に、下のプレビューで確かめられます。
   ============================================================================ */

(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var UI = window.DANDORI_UI;

  /*  この画面ではプレビューを出すので、ui.js の当て直しを止めます。
      （止めないと、えらんだ見た目がすぐ元に戻ってしまいます） */
  window.DANDORI_UI_HOLD = true;

  /*  はじめの読みこみでは、自動保存しません */
  var READY = false;

  var CUR = { preset: "standard", font: null, scheme: "theme",
              text_size: null, bg_color: null, ink_color: null, bg_art: null,
              bg_image: null, bg_from: null, bg_credit: null, bg_url: null };

  /*  背景のかざり。業種で呼び名を変えます。 */
  var IND = (window.DANDORI_ART && window.DANDORI_ART.industry) || "night";
  var ARTNAME = {
    pet:   { pop: "小さな動物が舞う",     cool: "トリミング室" },
    salon: { pop: "はさみやシャンプーが舞う", cool: "施術室" },
    food:  { pop: "食べものや野菜が舞う", cool: "厨房と客席" },
    night: { pop: "季節のものが舞う",     cool: "ミラーボール" },
    cast:  { pop: "季節のものが舞う",     cool: "ホテルの一室" }
  }[IND] || { pop: "イラストが舞う", cool: "お店の情景" };

  var ART = [
    { v: "",      t: "なし",                  c: "" },
    { v: "pop",   t: "ポップ（" + ARTNAME.pop + "）",  c: "#F6D9A8" },
    { v: "cool",  t: "クール（" + ARTNAME.cool + "）", c: "#9FB4C7" },
    { v: "photo", t: "写真",                  c: "#A8C8A0" }
  ];

  var PH = window.DANDORI_PHOTO;
  var SB = K.sb;

  /* ------------------------------------------------------------ 見せ方 */

  var PRESETS = [
    { v: "standard", t: "標準", who: "どのお店でも",
      d: "いまの画面そのままです。明るい背景で、ふだんの営業に使いやすい見た目にしています。",
      shot: { bg: "#F2F4F7", ink: "#16202A", btn: "#9A7B2E", fs: 13 } },
    { v: "large", t: "大きな文字", who: "年配のスタッフさん・パートの方",
      d: "文字を約1.3倍にし、ボタンも指で押しやすい大きさにします。老眼でも読みやすくなります。",
      shot: { bg: "#F2F4F7", ink: "#0C1620", btn: "#8A6C22", fs: 16 } },
    { v: "night", t: "夜の画面", who: "ナイト系・夜だけのお店",
      d: "濃い背景の画面です。暗いお店で見てもまぶしくなく、まわりのお客様の目にも入りにくくなります。",
      shot: { bg: "#0E1319", ink: "#E8EEF4", btn: "#C9A65A", fs: 13 } },
    { v: "contrast", t: "高コントラスト", who: "手元が暗いお店",
      d: "白と黒の差を強くします。厨房や薄暗いカウンターでも、数字がはっきり読めます。",
      shot: { bg: "#FFFFFF", ink: "#000000", btn: "#6B4E00", fs: 13 } }
  ];

  var BG = [
    { v: "", t: "標準（テーマの色）", c: "" },
    { v: "#FFFFFF", t: "白", c: "#FFFFFF" },
    { v: "#FAF6EF", t: "生成り", c: "#FAF6EF" },
    { v: "#EAF3F8", t: "薄い水色", c: "#EAF3F8" },
    { v: "#EDF5EC", t: "薄い緑", c: "#EDF5EC" },
    { v: "#FBEEF0", t: "薄い桃", c: "#FBEEF0" },
    { v: "#FBF5E3", t: "薄い黄", c: "#FBF5E3" },
    { v: "#101A2B", t: "濃紺（ダーク向け）", c: "#101A2B" },
    { v: "#15171A", t: "墨（ダーク向け）", c: "#15171A" }
  ];

  var INK = [
    { v: "", t: "標準（テーマの色）", c: "" },
    { v: "#000000", t: "黒", c: "#000000" },
    { v: "#123F3A", t: "濃い青緑", c: "#123F3A" },
    { v: "#4A2E22", t: "焦げ茶", c: "#4A2E22" },
    { v: "#152A63", t: "紺", c: "#152A63" },
    { v: "#3E1E63", t: "紫", c: "#3E1E63" },
    { v: "#FFFFFF", t: "白（ダーク向け）", c: "#FFFFFF" },
    { v: "#F3E4BE", t: "クリーム（ダーク向け）", c: "#F3E4BE" }
  ];

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function drawCards() {
    $("mtCards").innerHTML = PRESETS.map(function (p) {
      var s = p.shot;
      return "<div class='mtCard" + (CUR.preset === p.v ? " on" : "") + "'>" +
        "<div class='mtShot' style='background:" + s.bg + ";color:" + s.ink +
          ";font-size:" + s.fs + "px'>" +
          "<b>きょうのご予約</b>" +
          "<i class='w85'></i><i class='w60'></i>" +
          "<span class='mtBtn' style='background:" + s.btn + ";color:" +
            (p.v === "night" ? "#14191F" : "#FFFFFF") + "'>確定する</span>" +
        "</div>" +
        "<div class='mtBody'>" +
          "<h3>" + esc(p.t) + "</h3>" +
          "<p class='mtWho'>" + esc(p.who) + "</p>" +
          "<p>" + esc(p.d) + "</p>" +
          (CUR.preset === p.v
            ? "<button class='btn' disabled>この画面を使っています</button>"
            : "<button class='btn primary' data-pv='" + p.v + "'>この画面にする</button>") +
        "</div></div>";
    }).join("");

    Array.prototype.forEach.call($("mtCards").querySelectorAll("[data-pv]"), function (b) {
      b.addEventListener("click", function () {
        CUR.preset = b.getAttribute("data-pv");
        drawCards();
        preview();
      });
    });
  }

  function drawSwatch(el, list, cur, onPick, free) {
    el.innerHTML = list.map(function (o) {
      return "<button type='button' data-c='" + o.v + "' aria-pressed='" +
        (cur === o.v || (!cur && !o.v)) + "'>" +
        (o.c ? "<span class='dot' style='background:" + o.c + "'></span>"
             : "<span class='dot' style='background:linear-gradient(135deg,#888,#ddd)'></span>") +
        esc(o.t) + "</button>";
    }).join("") + (free === false ? "" :
      "<label style='display:inline-flex;align-items:center;gap:7px;padding:7px 13px;" +
      "border:1px solid var(--line);border-radius:999px;font-size:13.5px;cursor:pointer'>" +
      "<input type='color' data-free='1' value='" + (cur || "#ffffff") + "'>好きな色</label>");

    Array.prototype.forEach.call(el.querySelectorAll("[data-c]"), function (b) {
      b.addEventListener("click", function () { onPick(b.getAttribute("data-c")); });
    });
    var f = el.querySelector("[data-free]");
    if (f) f.addEventListener("change", function (e) { onPick(e.target.value); });
  }

  /* ------------------------------------------------------- プレビュー */

  function preview() {
    if (UI) UI.apply(CUR);
    warn();
    if (READY) autosave();
  }

  /*  えらんだら、そのまま覚えます。
      「保存する」を押し忘れても、ほかの画面に効きます。
      続けて何度もいじったときに書きすぎないよう、少し待ってから送ります。 */
  var T = null;
  function autosave() {
    if (T) clearTimeout(T);
    T = setTimeout(function () { save(true); }, 700);
  }

  function save(quiet) {
    if (!quiet) $("mtSave").disabled = true;
    K.rpc("ui_pref_set", {
      p_preset: CUR.preset,
      p_font:   CUR.font   || "",
      p_scheme: CUR.scheme || "",
      p_size:   CUR.text_size || 0,
      p_bg:     CUR.bg_color  || "",
      p_ink:    CUR.ink_color || "",
      p_art:    CUR.bg_art    || "",
      p_image:  CUR.bg_image  || "",
      p_from:   CUR.bg_from   || "",
      p_credit: CUR.bg_credit || ""
    }).then(function (p) {
      if (!quiet) $("mtSave").disabled = false;
      if (!p) return;
      if (UI) UI.remember(p);
      var m = $("mtSaved");
      if (m) {
        m.textContent = "保存しました（" +
          new Date().toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }) + "）";
      }
      if (!quiet) K.toast("保存しました");
    });
  }

  /* 背景と文字が近すぎると読めないので、お知らせします */
  function lum(hex) {
    if (!hex || hex.charAt(0) !== "#") return null;
    var n = parseInt(hex.slice(1), 16);
    var r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }

  function warn() {
    var a = lum(CUR.bg_color), b = lum(CUR.ink_color);
    $("mtWarn").innerHTML = (a !== null && b !== null && Math.abs(a - b) < 0.35)
      ? "<div class='box warn'>背景と文字の明るさが近すぎます。" +
        "このままだと、読みにくい画面になります。" +
        "どちらかを、もっと明るい（または暗い）色にしてください。</div>"
      : "";
  }

  /* ------------------------------------------------------------ 起動 */

  function fill() {
    $("mtFont").value   = CUR.font || "";
    $("mtScheme").value = CUR.scheme || "theme";
    $("mtSize").value   = String(CUR.text_size || 100);
    drawCards();
    drawSwatch($("mtArt"), ART, CUR.bg_art, pickArt, false);
    drawSwatch($("mtBg"), BG, CUR.bg_color, pickBg);
    drawSwatch($("mtInk"), INK, CUR.ink_color, pickInk);
    preview();
  }

  /* えらび直したら、印を付け替えてプレビューを更新します */
  function pickArt(v) {
    CUR.bg_art = v || null;
    drawSwatch($("mtArt"), ART, CUR.bg_art, pickArt, false);
    $("mtPhoto").classList.toggle("hidden", CUR.bg_art !== "photo");
    if (CUR.bg_art === "photo") showNow();
    preview();
  }

  /* ---------------------------------------------------------- 写真 */

  function showNow() {
    var n = $("mtNow");
    if (!n) return;
    if (!CUR.bg_image) { n.innerHTML = "まだ写真をえらんでいません。"; return; }
    n.innerHTML =
      (CUR.bg_url ? "<img class='mtNowShot' src='" + esc(CUR.bg_url) + "' alt=''>" : "") +
      "いまの写真：" + (CUR.bg_from === "upload" ? "取りこんだもの" : "さがしたもの") +
      (CUR.bg_credit ? "<br><small>" + esc(CUR.bg_credit) + "</small>" : "") +
      " <button class='btn small' id='mtClr'>外す</button>";
    var c = $("mtClr");
    if (c) c.addEventListener("click", function () {
      CUR.bg_image = CUR.bg_from = CUR.bg_credit = CUR.bg_url = null;
      showNow(); preview();
    });
  }

  function useUrl(url, path, from, cred) {
    CUR.bg_url = url; CUR.bg_image = path; CUR.bg_from = from; CUR.bg_credit = cred || null;
    CUR.bg_art = "photo";
    drawSwatch($("mtArt"), ART, CUR.bg_art, pickArt, false);
    showNow();
    preview();
  }

  function wirePhoto() {
    $("mtPick").addEventListener("click", function () { $("mtFile").click(); });

    $("mtFile").addEventListener("change", function (e) {
      var f = e.target.files && e.target.files[0];
      if (!f || !PH) return;
      K.toast("取りこんでいます…");
      PH.upload(SB, f).then(function (path) {
        return PH.signed(SB, path).then(function (u) {
          useUrl(u, path, "upload", null);
          K.toast("取りこみました");
        });
      }).catch(function (err) {
        K.toast(String(err && err.message || err), "err");
      });
      e.target.value = "";
    });

    function go() {
      var w = $("mtQ").value.trim();
      if (!w) { K.toast("さがす言葉を入れてください", "err"); return; }
      if (!PH) return;
      $("mtHits").innerHTML = "<p class='hint'>さがしています…</p>";
      PH.search(w).then(function (list) {
        if (!list.length) {
          $("mtHits").innerHTML =
            "<p class='hint'>見つかりませんでした。別の言葉（英語もおすすめです）でお試しください。</p>";
          return;
        }
        $("mtHits").innerHTML = list.map(function (x, i) {
          return "<button type='button' data-i='" + i + "' title='" + esc(x.title) +
                 (x.by ? "／" + esc(x.by) : "") + "'>" +
                 "<img loading='lazy' src='" + esc(x.thumb) + "' alt=''></button>";
        }).join("") +
        "<p class='hint' style='grid-column:1/-1;margin:6px 0 0'>写真の出どころ： " +
        esc(list[0].from || "") + "</p>";
        Array.prototype.forEach.call($("mtHits").querySelectorAll("[data-i]"), function (b) {
          b.addEventListener("click", function () {
            var x = list[Number(b.getAttribute("data-i"))];
            useUrl(x.full, x.full, "search", PH.credit(x));
          });
        });
      }).catch(function (err) {
        $("mtHits").innerHTML =
          "<div class='box warn'>いま写真をさがせませんでした（" +
          esc(String(err && err.message || err)) + "）。<br>" +
          "しばらくしてからお試しいただくか、「取りこむ」のほうをお使いください。</div>";
      });
    }
    $("mtGo").addEventListener("click", go);
    $("mtQ").addEventListener("keydown", function (e) { if (e.key === "Enter") go(); });
  }
  function pickBg(v) {
    CUR.bg_color = v || null;
    drawSwatch($("mtArt"), ART, CUR.bg_art, pickArt, false);
    drawSwatch($("mtBg"), BG, CUR.bg_color, pickBg);
    preview();
  }
  function pickInk(v) {
    CUR.ink_color = v || null;
    drawSwatch($("mtInk"), INK, CUR.ink_color, pickInk);
    preview();
  }

  K.wireLogin();
  K.boot(function () {
    K.rpc("ui_pref_get", {}).then(function (p) {
      if (p) {
        CUR.preset    = p.preset || "standard";
        CUR.font      = p.font || null;
        CUR.scheme    = p.scheme || "theme";
        CUR.text_size = p.text_size || null;
        CUR.bg_color  = p.bg_color || null;
        CUR.ink_color = p.ink_color || null;
        CUR.bg_art    = p.bg_art || null;
        CUR.bg_image  = p.bg_image || null;
        CUR.bg_from   = p.bg_from || null;
        CUR.bg_credit = p.bg_credit || null;
      }
      READY = false;
      fill();
      $("mtPhoto").classList.toggle("hidden", CUR.bg_art !== "photo");
      if (CUR.bg_art === "photo" && PH && CUR.bg_image) {
        PH.signed(SB, CUR.bg_image).then(function (u) {
          CUR.bg_url = u; showNow(); if (UI) UI.apply(CUR);
        });
      }
      wirePhoto();
      READY = true;
    });
  });

  $("mtFont").addEventListener("change", function () {
    CUR.font = $("mtFont").value || null; preview();
  });
  $("mtScheme").addEventListener("change", function () {
    CUR.scheme = $("mtScheme").value || "theme"; preview();
  });
  $("mtSize").addEventListener("change", function () {
    CUR.text_size = Number($("mtSize").value) || 100; preview();
  });

  $("mtSave").addEventListener("click", function () { save(false); });

  $("mtReset").addEventListener("click", function () {
    K.confirm("すべて標準に戻しますか",
      "<p>見せ方も、細かい設定も、はじめの状態に戻します。</p>",
      "戻す", function () {
        K.rpc("ui_pref_reset", {}).then(function (p) {
          if (!p) return;
          K.closeModal();
          CUR = { preset: "standard", font: null, scheme: "theme",
                  text_size: null, bg_color: null, ink_color: null, bg_art: null,
              bg_image: null, bg_from: null, bg_credit: null, bg_url: null };
          if (UI) { UI.remember(CUR); UI.apply(CUR); }
          fill();
          K.toast("戻しました");
        });
      });
  });
})();
