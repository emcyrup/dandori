/* ============================================================================
   だんどりシリーズ / シフト希望の提出（本人の画面）
   wish.js

   この画面は、ログインしません。
   LINE・メール・SMSで配られたリンクの「合いことば」だけで動きます。
   見えるのは、ご自分の希望と、ご自分の確定シフトだけです。
   ============================================================================ */
(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  var token = new URLSearchParams(location.search).get("t") || "";
  var D = null;          // お店から返ってきた中身
  var days = {};         // { "2026-10-01": {kind, slot_id, from, to, note} }
  var dirty = false;

  var DOW = ["日", "月", "火", "水", "木", "金", "土"];

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }

  function say(title, body) {
    $("wrap").innerHTML = "<div class='w-msgbox'><h2>" + esc(title) + "</h2>" +
                          "<p>" + esc(body || "") + "</p></div>";
  }

  function ymd(d) {
    var t = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
    return t.toISOString().slice(0, 10);
  }

  function md(s) {
    var d = new Date(s + "T00:00:00");
    return (d.getMonth() + 1) + "/" + d.getDate() + "（" + DOW[d.getDay()] + "）";
  }

  /* ------------------------------------------------------------ 読みこみ */

  function load() {
    if (!token) {
      say("リンクをもう一度ひらいてください", "アドレスが途中で切れているようです。");
      return;
    }
    return sb.rpc("wish_open", { p_token: token }).then(function (q) {
      if (q.error) {
        say("ただいま、お使いいただけません",
            (q.error.message || "").replace(/^.*?:\s*/, "") ||
            "お店にご連絡ください。");
        return;
      }
      D = q.data;
      days = {};
      (D.days || []).forEach(function (d) {
        days[d.date] = {
          kind: d.kind, slot_id: d.slot_id,
          from: d.from, to: d.to, note: d.note
        };
      });
      dirty = false;
      draw();
    });
  }

  /* ------------------------------------------------------------ 画面 */

  function draw() {
    var h = "";

    h += "<div class='w-head'>" +
      "<h1>" + esc(D.name) + " さんのシフト希望</h1>" +
      "<p>" + esc(D.store_name) + "<br>" +
      md(D.period_from) + " 〜 " + md(D.period_to) +
      (D.deadline_at
        ? "　／　締切 " + new Date(D.deadline_at).toLocaleString("ja-JP",
            { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })
        : "") + "</p>" +
      "<span class='w-state" +
        (D.status === "approved" ? " ok" : D.status === "returned" ? " rt" : "") +
        "'>" + esc(D.status_label) + "</span>" +
      "</div>";

    if (D.status === "returned" && D.reply_note) {
      h += "<div class='w-msg'><b>お店から</b>\n" + esc(D.reply_note) + "</div>";
    }
    if (D.past_deadline && D.can_edit) {
      h += "<div class='w-msg'>締切をすぎています。" +
           "出せますが、間に合わないことがあります。お店にもひとこと入れてください。</div>";
    }
    if (!D.can_edit && D.status !== "approved") {
      h += "<div class='w-msg'>いまは直せません。変えたいときは、お店にご連絡ください。</div>";
    }

    /* 確定したシフト */
    if ((D.fixed || []).length) {
      h += "<div class='w-fixed'><h2>確定したシフト</h2><ul>";
      D.fixed.forEach(function (f) {
        h += "<li><span>" + md(f.date) + "</span><span>" +
             esc(f.from || "") + "〜" + esc(f.to || "") +
             (f.name ? "　" + esc(f.name) : "") + "</span></li>";
      });
      h += "</ul></div>";
    }

    if (D.can_edit) {
      h += "<div class='w-legend'>" +
        "<span><i style='background:#e6f2e6;border-color:#9cc49c'></i>入れます</span>" +
        "<span><i style='background:#fdf0d6;border-color:#e0bd6b'></i>入りたい</span>" +
        "<span><i style='background:#f7e0de;border-color:#d79a94'></i>休みたい</span>" +
        "<span><i></i>まだ</span></div>";
    }

    h += calendar();

    if (D.can_edit) {
      h += "<div class='w-note'>" +
        "<textarea id='wNote' rows='3' placeholder='お店へのひとこと（あれば）'>" +
        esc(D.note || "") + "</textarea></div>";
    }

    var n = Object.keys(days).length;
    h += "<div class='w-bar'>" +
      "<div class='s'>" + (n ? n + "日えらびました" : "日にちをえらんでください") + "</div>" +
      (D.can_edit
        ? "<button class='w-btn sub' id='bSave'>とちゅう保存</button>" +
          "<button class='w-btn main' id='bSend'" + (n ? "" : " disabled") + ">提出する</button>"
        : "<button class='w-btn sub' id='bReload'>読みこみ直す</button>") +
      "</div>";

    $("wrap").innerHTML = h;
    wire();
  }

  function calendar() {
    var from = new Date(D.period_from + "T00:00:00");
    var to = new Date(D.period_to + "T00:00:00");

    var h = "<div class='w-cal'>";
    for (var i = 0; i < 7; i++) {
      h += "<div class='w-dow" + (i === 0 ? " sun" : i === 6 ? " sat" : "") + "'>" +
           DOW[i] + "</div>";
    }
    /* 月はじめの空白 */
    for (var p = 0; p < from.getDay(); p++) {
      h += "<div class='w-day pad'></div>";
    }
    var d = new Date(from);
    while (d <= to) {
      var key = ymd(d);
      var x = days[key];
      var cls = x ? x.kind : "";
      h += "<button class='w-day " + cls + "' data-d='" + key + "'" +
           (D.can_edit ? "" : " disabled") + ">" +
           "<span class='d'>" + d.getDate() + "</span>" +
           "<span class='t'>" + label(x) + "</span></button>";
      d.setDate(d.getDate() + 1);
    }
    h += "</div>";
    return h;
  }

  function label(x) {
    if (!x) return "";
    if (x.kind === "ng") return "休み";
    var s = slotName(x.slot_id);
    if (s) return esc(s);
    if (x.from) return esc(x.from) + (x.to ? "〜" + esc(x.to) : "〜");
    return x.kind === "want" ? "入りたい" : "おまかせ";
  }

  function slotName(id) {
    if (!id) return null;
    var s = (D.slots || []).filter(function (x) { return x.id === id; })[0];
    return s ? s.name : null;
  }

  function wire() {
    each("[data-d]", function (b) {
      b.addEventListener("click", function () { pick(b.dataset.d); });
    });
    if ($("bSave")) $("bSave").addEventListener("click", function () { save(false); });
    if ($("bSend")) $("bSend").addEventListener("click", submit);
    if ($("bReload")) $("bReload").addEventListener("click", load);
    if ($("wNote")) $("wNote").addEventListener("input", function () { dirty = true; });
  }

  function each(sel, fn) {
    Array.prototype.forEach.call(document.querySelectorAll(sel), fn);
  }

  /* ------------------------------------------------------- 1日をえらぶ */

  function pick(key) {
    var cur = days[key] || {};
    var h = "<div class='w-pick'><div class='b'>" +
      "<h2>" + md(key) + "</h2>" +
      "<p>この日は、どうしますか？</p>";

    (D.slots || []).forEach(function (s) {
      h += "<button class='w-opt" +
           (cur.kind !== "ng" && cur.slot_id === s.id ? " on" : "") +
           "' data-slot='" + esc(s.id) + "'>" +
           "<b>" + esc(s.name) + "</b>" +
           "<small>" + esc(s.from) + "〜" + esc(s.to) + "</small></button>";
    });

    h += "<button class='w-opt" +
         (cur.kind === "ok" && !cur.slot_id && !cur.from ? " on" : "") +
         "' data-any='1'><b>時間はおまかせ</b>" +
         "<small>入れます。時間はお店にお任せします</small></button>";

    h += "<button class='w-opt" + (cur.kind === "want" ? " on" : "") +
         "' data-want='1'><b>この日はぜひ入りたい</b>" +
         "<small>優先してほしい日</small></button>";

    h += "<button class='w-opt" + (cur.kind === "ng" ? " on" : "") +
         "' data-ng='1'><b>この日は休みたい</b></button>";

    h += "<p style='margin-top:14px'>時間を自分で決めるとき</p>" +
      "<div class='w-times'>" +
      "<label>はじめ<input id='pFrom' type='time' step='300' value='" +
        esc(cur.kind === "ng" ? "" : (cur.from || "")) + "'></label>" +
      "<label>おわり<input id='pTo' type='time' step='300' value='" +
        esc(cur.kind === "ng" ? "" : (cur.to || "")) + "'></label>" +
      "</div>" +
      "<button class='w-opt' data-time='1'><b>この時間で入れます</b></button>" +

      "<div style='display:flex;gap:10px;margin-top:14px'>" +
      (days[key]
        ? "<button class='w-btn sub' style='flex:1' data-clear='1'>この日を消す</button>"
        : "") +
      "<button class='w-btn sub' style='flex:1' data-close='1'>とじる</button>" +
      "</div></div></div>";

    $("pickRoot").innerHTML = h;

    var root = $("pickRoot");
    root.querySelector(".w-pick").addEventListener("click", function (e) {
      if (e.target === root.querySelector(".w-pick")) close();
    });

    each2(root, "[data-slot]", function (b) {
      b.addEventListener("click", function () {
        var s = (D.slots || []).filter(function (x) { return x.id === b.dataset.slot; })[0];
        set(key, { kind: "ok", slot_id: b.dataset.slot, from: s.from, to: s.to });
      });
    });
    each2(root, "[data-any]", function (b) {
      b.addEventListener("click", function () { set(key, { kind: "ok" }); });
    });
    each2(root, "[data-want]", function (b) {
      b.addEventListener("click", function () {
        var cur2 = days[key] || {};
        set(key, { kind: "want", slot_id: cur2.slot_id, from: cur2.from, to: cur2.to });
      });
    });
    each2(root, "[data-ng]", function (b) {
      b.addEventListener("click", function () { set(key, { kind: "ng" }); });
    });
    each2(root, "[data-time]", function (b) {
      b.addEventListener("click", function () {
        var f = $("pFrom").value, t = $("pTo").value;
        if (!f || !t) { toast("はじめと終わりを入れてください", "err"); return; }
        set(key, { kind: "ok", from: f, to: t });
      });
    });
    each2(root, "[data-clear]", function (b) {
      b.addEventListener("click", function () {
        delete days[key];
        dirty = true;
        close();
        draw();
      });
    });
    each2(root, "[data-close]", function (b) {
      b.addEventListener("click", close);
    });
  }

  function each2(root, sel, fn) {
    Array.prototype.forEach.call(root.querySelectorAll(sel), fn);
  }

  function set(key, v) {
    days[key] = v;
    dirty = true;
    close();
    draw();
  }

  function close() { $("pickRoot").innerHTML = ""; }

  /* ------------------------------------------------------------ 保存 */

  function payload() {
    return Object.keys(days).sort().map(function (k) {
      var x = days[k];
      return {
        date: k, kind: x.kind,
        slot_id: x.slot_id || null,
        from: x.from || null, to: x.to || null,
        note: x.note || null
      };
    });
  }

  function save(quiet) {
    return sb.rpc("wish_set", {
      p_token: token,
      p_days: payload(),
      p_note: $("wNote") ? $("wNote").value : null
    }).then(function (q) {
      if (q.error) {
        toast((q.error.message || "").replace(/^.*?:\s*/, ""), "err");
        return false;
      }
      dirty = false;
      if (!quiet) toast((q.data && q.data.message) || "控えました");
      return true;
    });
  }

  function submit() {
    save(true).then(function (okd) {
      if (!okd) return;
      return sb.rpc("wish_submit", {
        p_token: token,
        p_note: $("wNote") ? $("wNote").value : null
      }).then(function (q) {
        if (q.error) {
          toast((q.error.message || "").replace(/^.*?:\s*/, ""), "err");
          return;
        }
        toast((q.data && q.data.message) || "お店に送りました");
        load();
      });
    });
  }

  /* ------------------------------------------------------------ 起動 */

  window.addEventListener("beforeunload", function (e) {
    if (!dirty) return;
    e.preventDefault();
    e.returnValue = "";
  });

  load();

  /* 確定したかどうかが変わるので、ときどき見にいきます */
  setInterval(function () {
    if (document.hidden || dirty) return;
    if ($("pickRoot").innerHTML) return;
    load();
  }, 60000);
})();
