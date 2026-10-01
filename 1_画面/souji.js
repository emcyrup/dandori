/* ============================================================================
   だんどりシリーズ / 清掃・やること
   souji.js
   置き場所： サイトのルート（souji.html と同じ階層）

   3つに分かれています。
     ・きょう … その日にやることが出ます。チェックを入れると記録に残ります。
                 「＋」で、その日だけの項目を3つまで足せます。
                 「紙に出す」で、チェック表を印刷できます。
     ・場所　 … 清掃する場所の台帳。周期と、業者さんの間隔を決めます。
     ・業者　 … 前に業者さんが入った日からの日数。期限がきたものが出ます。

   紙は、チェック欄でも、ハンコ欄でも出せます。
   ============================================================================ */

(function () {
  "use strict";

  var $ = K.$, esc = K.esc;
  var VIEWS = ["today", "spot", "pro"];
  var ROWS = [];      /* きょうの一覧 */
  var EXTRA = [];     /* その日だけの追加ぶん */
  var SPOTS = [];     /* 場所の台帳 */
  var PRO = [];       /* 業者さんの案内 */
  var MAXEXTRA = 3;

  var CYCLE = [
    { v: "daily",     t: "毎日" },
    { v: "weekly",    t: "週に1回" },
    { v: "monthly",   t: "月に1回" },
    { v: "quarterly", t: "3か月に1回" },
    { v: "yearly",    t: "年に1回" }
  ];

  var PROM = [
    { v: 0,  t: "ご案内しない" },
    { v: 3,  t: "3か月に1回" },
    { v: 6,  t: "半年に1回" },
    { v: 12, t: "年に1回" },
    { v: 24, t: "2年に1回" }
  ];

  function theDate() { return $("dDate").value || K.today(); }

  function cycleLabel(v) {
    for (var i = 0; i < CYCLE.length; i++) if (CYCLE[i].v === v) return CYCLE[i].t;
    return v;
  }

  /* =============================================================== きょう */

  function loadToday() {
    return Promise.all([
      K.rpc("clean_today", { p_store: K.S.store.id, p_date: theDate() }),
      K.rpc("clean_sheet", { p_store: K.S.store.id, p_date: theDate(), p_extra: 0 })
    ]).then(function (r) {
      ROWS = r[0] || [];
      EXTRA = (r[1] && r[1].extras) || [];
      drawToday();
    });
  }

  function drawToday() {
    var due = ROWS.filter(function (x) { return x.due; });
    var done = due.filter(function (x) { return x.done; }).length;
    var late = ROWS.filter(function (x) { return x.late && !x.done; });

    $("dSum").innerHTML =
      "<div class='stats'>" +
      K.stat("きょうやること", due.length + " か所") +
      K.stat("すんだところ", done + " か所", done >= due.length && due.length ? "" : "warn") +
      K.stat("のこり", (due.length - done) + " か所") +
      "</div>" +
      (late.length
        ? "<div class='box warn' style='margin-top:10px'><b>しばらく手が回っていないところが " +
          late.length + " か所あります。</b>" +
          late.map(function (x) {
            return esc(x.name) + "（" + (x.days != null ? x.days + "日ぶり" : "記録なし") + "）";
          }).join("　／　") + "</div>"
        : "");

    if (!due.length) {
      $("dTable").innerHTML = "";
      $("dEmpty").classList.remove("hidden");
    } else {
      $("dEmpty").classList.add("hidden");
      var body = due.map(function (x) {
        return "<tr class='" + (x.done ? "off" : (x.late ? "bad" : "")) + "'>" +
          "<td style='width:44px'><input type='checkbox' data-do='" + x.id + "'" +
            (x.done ? " checked" : "") + " style='width:22px;height:22px'></td>" +
          "<td><b>" + esc(x.name) + "</b>" +
            (x.how ? "<br><small>" + esc(x.how) + "</small>" : "") + "</td>" +
          "<td class='nw'>" + esc(x.area || "—") + "</td>" +
          "<td class='nw'>" + esc(x.cycle_label) + "</td>" +
          "<td class='nw'>" + esc(x.last_label) +
            (x.late ? " " + K.pill("あいています") : "") + "</td>" +
          "<td>" + ((x.pro_due && x.pro_last) ? K.pill("業者さんの時期", "warn") : "") + "</td>" +
          "</tr>";
      });
      $("dTable").innerHTML = K.table(
        ["", "場所", "区分", "周期", "前にやった日", ""], body);
      Array.prototype.forEach.call($("dTable").querySelectorAll("[data-do]"), function (c) {
        c.addEventListener("change", function () { toggle(c.dataset.do, c.checked); });
      });
    }

    /* その日だけの追加ぶん */
    $("dExtra").innerHTML = EXTRA.length
      ? "<table class='list'>" + K.table(["その日の追加", ""], EXTRA.map(function (e) {
          return "<tr><td><b>" + esc(e.name) + "</b>" +
            (e.note ? "<br><small>" + esc(e.note) + "</small>" : "") + "</td>" +
            "<td class='right'><button class='btn ghost' data-xdel='" + e.id +
            "'>消す</button></td></tr>";
        })) + "</table>"
      : "";
    K.bind($("dExtra"), "[data-xdel]", "xdel", function (id) {
      K.rpc("clean_extra_remove", { p_log: id }).then(function () { loadToday(); });
    });
    $("dAdd").disabled = (EXTRA.length >= MAXEXTRA);
    $("dAddNote").textContent = EXTRA.length >= MAXEXTRA
      ? "その日の追加は、3つまでです。"
      : "あと " + (MAXEXTRA - EXTRA.length) + " つ足せます。";
  }

  function toggle(id, on) {
    var fn = on ? "clean_done" : "clean_undo";
    var args = on
      ? { p_store: K.S.store.id, p_spot: id, p_date: theDate(), p_kind: "self" }
      : { p_store: K.S.store.id, p_spot: id, p_date: theDate(), p_kind: "self" };
    K.rpc(fn, args).then(function (r) {
      if (r === null) { loadToday(); return; }
      K.toast(on ? "記録しました" : "もどしました");
      loadToday();
    });
  }

  function addExtra() {
    K.modal(
      "<h2 style='margin-top:0'>きょうだけの、やることを足す</h2>" +
      "<label class='field'><span>やること</span>" +
        "<input id='x_name' placeholder='例： 看板の電球を替える'></label>" +
      "<label class='field'><span>ひとこと（任意）</span>" +
        "<input id='x_note' placeholder='例： 脚立は事務所'></label>" +
      "<p style='color:var(--muted);font-size:12.5px'>" +
      "ここで足したものは、その日かぎりです。毎回やることは「場所」から登録してください。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='x_no'>やめる</button> " +
      "<button class='btn primary' id='x_ok'>足す</button></div>",
      function (root) {
        root.querySelector("#x_no").addEventListener("click", K.closeModal);
        root.querySelector("#x_ok").addEventListener("click", function () {
          var n = ($("x_name").value || "").trim();
          if (!n) { K.toast("やることを入れてください", "err"); return; }
          K.rpc("clean_done", {
            p_store: K.S.store.id, p_spot: null, p_name: n,
            p_date: theDate(), p_kind: "self",
            p_note: ($("x_note").value || "").trim() || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); loadToday();
          });
        });
      });
  }

  /* ============================================================== 紙に出す */

  function openPrint() {
    K.modal(
      "<h2 style='margin-top:0'>紙に出す</h2>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:1 1 200px'><span>確認のしかた</span>" +
        "<select id='p_mode'>" +
        "<option value='check'>チェック欄（レ点）</option>" +
        "<option value='hanko'>ハンコ欄</option>" +
        "<option value='both'>チェック欄とハンコ欄</option>" +
        "</select></label>" +
      "<label class='field' style='flex:0 0 160px'><span>追加ぶんの空欄</span>" +
        "<select id='p_extra'><option value='3'>3行</option>" +
        "<option value='2'>2行</option><option value='1'>1行</option>" +
        "<option value='0'>なし</option></select></label>" +
      "<label class='field' style='flex:1 1 200px'><span>すんだところ</span>" +
        "<select id='p_done'><option value='blank'>空欄で出す（これから書く）</option>" +
        "<option value='mark'>画面の記録を入れて出す</option></select></label>" +
      "</div>" +
      "<label class='field'><span>下の確認欄</span>" +
        "<select id='p_foot'>" +
        "<option value='hanko'>確認者の印</option>" +
        "<option value='sign'>確認者の署名</option>" +
        "<option value='none'>なし</option></select></label>" +
      "<p style='color:var(--muted);font-size:12.5px'>" +
      "ハンコの運用でも、レ点の運用でも、どちらでもお使いいただけます。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='p_no'>やめる</button> " +
      "<button class='btn primary' id='p_ok'>印刷する</button></div>",
      function (root) {
        root.querySelector("#p_no").addEventListener("click", K.closeModal);
        root.querySelector("#p_ok").addEventListener("click", function () {
          var o = {
            mode: $("p_mode").value,
            extra: Number($("p_extra").value),
            done: $("p_done").value,
            foot: $("p_foot").value
          };
          K.closeModal();
          makeSheet(o);
        });
      });
  }

  function box() { return "<span class='pbox'></span>"; }

  function makeSheet(o) {
    K.rpc("clean_sheet", {
      p_store: K.S.store.id, p_date: theDate(), p_extra: o.extra
    }).then(function (s) {
      if (!s) return;
      var cols = (o.mode === "both") ? 2 : 1;
      var h = [];

      h.push("<div class='psheet'>");
      h.push("<div class='phead'><div class='ptitle'>清掃チェック表</div>" +
             "<div class='pmeta'><span>" + esc(s.store) + "</span>" +
             "<span>" + esc(s.date) + "</span></div></div>");

      h.push("<table class='ptable'><thead><tr>" +
             "<th style='width:13%'>区分</th><th>場所</th>" +
             "<th style='width:12%'>周期</th>" +
             (o.mode === "hanko" || o.mode === "both"
               ? "<th style='width:13%'>印</th>" : "") +
             (o.mode === "check" || o.mode === "both"
               ? "<th style='width:9%'>確認</th>" : "") +
             "</tr></thead><tbody>");

      (s.rows || []).forEach(function (r) {
        var mark = (o.done === "mark" && r.done) ? "レ" : "";
        h.push("<tr><td>" + esc(r.area) + "</td>" +
          "<td><b>" + esc(r.name) + "</b>" +
          (r.how ? "<span class='phow'>" + esc(r.how) + "</span>" : "") + "</td>" +
          "<td class='c'>" + esc(r.cycle) + "</td>" +
          (o.mode === "hanko" || o.mode === "both" ? "<td class='c'><span class='phanko'></span></td>" : "") +
          (o.mode === "check" || o.mode === "both" ? "<td class='c'>" + (mark || box()) + "</td>" : "") +
          "</tr>");
      });

      /* その日だけの追加ぶん（書きこんだもの＋空欄） */
      (s.extras || []).forEach(function (e) {
        h.push("<tr><td class='c'>追加</td><td><b>" + esc(e.name) + "</b></td>" +
          "<td class='c'>きょう</td>" +
          (o.mode === "hanko" || o.mode === "both" ? "<td class='c'><span class='phanko'></span></td>" : "") +
          (o.mode === "check" || o.mode === "both" ? "<td class='c'>" + box() + "</td>" : "") +
          "</tr>");
      });
      var n = s.extra_slots || 0;
      for (var i = 0; i < n; i++) {
        h.push("<tr><td class='c'>追加</td><td class='pline'></td><td></td>" +
          (o.mode === "hanko" || o.mode === "both" ? "<td class='c'><span class='phanko'></span></td>" : "") +
          (o.mode === "check" || o.mode === "both" ? "<td class='c'>" + box() + "</td>" : "") +
          "</tr>");
      }
      h.push("</tbody></table>");

      if ((s.pro || []).length) {
        h.push("<div class='pnote'><b>業者さんのクリーニング（そろそろの時期です）</b><ul>");
        (s.pro || []).forEach(function (p) {
          h.push("<li>" + esc(p.name) + "　前回： " + esc(p.last) +
                 "　／　目安： " + p.months + "か月に1回" +
                 (p.note ? "　／　" + esc(p.note) : "") + "</li>");
        });
        h.push("</ul></div>");
      }

      if (o.foot !== "none") {
        h.push("<div class='pfoot'><span>確認者</span>" +
               "<span class='pfline'></span>" +
               (o.foot === "hanko" ? "<span class='phanko big'></span>" : "") +
               "</div>");
      }
      h.push("<div class='pby'>" + esc(s.store) +
             "　／　だんどりシリーズ</div>");
      h.push("</div>");

      $("printArea").innerHTML = h.join("");
      document.body.classList.add("printing");
      window.setTimeout(function () {
        window.print();
        window.setTimeout(function () {
          document.body.classList.remove("printing");
        }, 300);
      }, 120);
    });
  }

  /* ================================================================ 場所 */

  function loadSpots() {
    return K.rpc("clean_spot_list", { p_store: K.S.store.id, p_all: false })
      .then(function (rows) {
        SPOTS = rows || [];
        drawSpots();
      });
  }

  function drawSpots() {
    if (!SPOTS.length) {
      $("sTable").innerHTML = "";
      $("sEmpty").classList.remove("hidden");
      return;
    }
    $("sEmpty").classList.add("hidden");
    var body = SPOTS.map(function (s) {
      return "<tr>" +
        "<td class='nw'>" + esc(s.area || "—") + "</td>" +
        "<td><b>" + esc(s.name) + "</b>" +
          (s.how ? "<br><small>" + esc(s.how) + "</small>" : "") + "</td>" +
        "<td class='nw'>" + esc(cycleLabel(s.cycle)) + "</td>" +
        "<td class='nw'>" + (s.pro_months > 0
          ? s.pro_months + "か月に1回" : "—") + "</td>" +
        "<td class='nw'>" + (s.pro_last ? esc(K.md(s.pro_last)) : "—") + "</td>" +
        "<td class='right nw'><button class='btn ghost' data-edit='" + s.id +
          "'>直す</button></td></tr>";
    });
    $("sTable").innerHTML = K.table(
      ["区分", "場所", "周期", "業者さん", "前に業者さんが入った日", ""], body);
    K.bind($("sTable"), "[data-edit]", "edit", function (id) {
      var a = SPOTS.filter(function (x) { return x.id === id; });
      openSpot(a[0]);
    });
  }

  function openSpot(s) {
    K.modal(
      "<h2 style='margin-top:0'>" + (s ? "場所を直す" : "場所を足す") + "</h2>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:2 1 220px'><span>場所</span>" +
        "<input id='s_name' value='" + esc(s ? s.name : "") + "'></label>" +
      "<label class='field' style='flex:1 1 130px'><span>区分</span>" +
        "<input id='s_area' placeholder='客席・厨房 など' value='" +
        esc(s ? (s.area || "") : "") + "'></label>" +
      "<label class='field' style='flex:1 1 150px'><span>どれくらいの周期で</span>" +
        "<select id='s_cycle'>" + CYCLE.map(function (c) {
          return "<option value='" + c.v + "'" +
            (s && s.cycle === c.v ? " selected" : "") + ">" + esc(c.t) + "</option>";
        }).join("") + "</select></label>" +
      "<label class='field' style='flex:1 1 170px'><span>業者さんのクリーニング</span>" +
        "<select id='s_pro'>" + PROM.map(function (c) {
          return "<option value='" + c.v + "'" +
            (s && Number(s.pro_months) === c.v ? " selected" : "") + ">" +
            esc(c.t) + "</option>";
        }).join("") + "</select></label>" +
      "<label class='field' style='flex:1 1 170px'><span>前に業者さんが入った日</span>" +
        "<input id='s_last' type='date' value='" + (s && s.pro_last ? s.pro_last : "") +
        "'></label>" +
      "<label class='field' style='flex:2 1 220px'><span>業者さんの連絡先など</span>" +
        "<input id='s_pnote' value='" + esc(s ? (s.pro_note || "") : "") + "'></label>" +
      "<label class='field' style='flex:2 1 260px'><span>やり方のひとこと</span>" +
        "<input id='s_how' value='" + esc(s ? (s.how || "") : "") + "'></label>" +
      "</div>" +
      "<div class='row' style='justify-content:space-between;margin-top:16px'>" +
        "<span>" + (s ? "<button class='btn ghost' id='s_del'>使わなくする</button>" : "") + "</span>" +
        "<span><button class='btn ghost' id='s_no'>やめる</button> " +
        "<button class='btn primary' id='s_ok'>保存する</button></span></div>",
      function (root) {
        wide(root, 760);
        root.querySelector("#s_no").addEventListener("click", K.closeModal);
        root.querySelector("#s_ok").addEventListener("click", function () {
          var nm = ($("s_name").value || "").trim();
          if (!nm) { K.toast("場所の名前を入れてください", "err"); return; }
          K.rpc("clean_spot_save", {
            p_store: K.S.store.id, p_id: s ? s.id : null, p_name: nm,
            p_area: ($("s_area").value || "").trim() || null,
            p_cycle: $("s_cycle").value,
            p_pro: Number($("s_pro").value) || 0,
            p_pro_last: $("s_last").value || null,
            p_pro_note: ($("s_pnote").value || "").trim() || null,
            p_how: ($("s_how").value || "").trim() || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); K.toast("保存しました");
            loadSpots(); loadPro();
          });
        });
        var d = root.querySelector("#s_del");
        if (d) d.addEventListener("click", function () {
          K.confirm("使わなくします", "<p>" + esc(s.name) +
            " を、一覧から外します。これまでの記録は残ります。</p>", "外す", function () {
            K.rpc("clean_spot_save", {
              p_store: K.S.store.id, p_id: s.id, p_active: false
            }).then(function (r) {
              if (!r) return;
              K.closeModal(); K.toast("外しました"); loadSpots(); loadPro();
            });
          });
        });
      });
  }

  /* ================================================================ 業者 */

  function loadPro() {
    return K.rpc("clean_pro_due", { p_store: K.S.store.id }).then(function (rows) {
      PRO = rows || [];
      drawPro();
    });
  }

  function drawPro() {
    var never = PRO.filter(function (p) { return !p.pro_last; });
    var over = PRO.filter(function (p) { return !!p.pro_last; });

    $("pSum").innerHTML =
      "<div class='box" + (over.length ? " warn" : "") + "'>" +
      (over.length
        ? "<b>業者さんに見てもらう時期がきたところが " + over.length + " か所あります。</b>" +
          "前に入っていただいた日から、決めた月数がたっています。"
        : "<b>いまのところ、期限がきているところはありません。</b>") +
      "</div>" +
      (never.length
        ? "<div class='box' style='margin-top:10px'><b>まだ記録がない場所が " +
          never.length + " か所あります。</b>" +
          "前に業者さんが入った日を入れておくと、つぎの時期をお知らせできます。" +
          "覚えていなければ、だいたいで大丈夫です。</div>"
        : "");

    if (!PRO.length) {
      $("pTable").innerHTML = "";
      $("pEmpty").classList.remove("hidden");
      return;
    }
    $("pEmpty").classList.add("hidden");
    var body = PRO.map(function (p) {
      return "<tr class='" + (p.pro_last ? "bad" : "") + "'>" +
        "<td class='nw'>" + esc(p.area || "—") + "</td>" +
        "<td><b>" + esc(p.name) + "</b>" +
          (p.pro_note ? "<br><small>" + esc(p.pro_note) + "</small>" : "") + "</td>" +
        "<td class='nw'>" + p.pro_months + "か月に1回</td>" +
        "<td class='nw'>" + esc(p.last_label) +
          (p.days != null ? "<br><small>" + p.days + "日たちました</small>" : "") + "</td>" +
        "<td class='right nw'>" +
          "<button class='btn primary' data-pro='" + p.id + "'>入ってもらった</button></td>" +
        "</tr>";
    });
    $("pTable").innerHTML = K.table(
      ["区分", "場所", "目安", "前回", ""], body);
    K.bind($("pTable"), "[data-pro]", "pro", openPro);
  }

  function openPro(id) {
    var a = PRO.filter(function (x) { return x.id === id; });
    var p = a[0];
    if (!p) return;
    K.modal(
      "<h2 style='margin-top:0'>" + esc(p.name) + "</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
      "業者さんに入っていただいた日を入れます。<br>" +
      "つぎのご案内は、そこから " + p.pro_months + "か月後になります。</p>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:0 0 180px'><span>入っていただいた日</span>" +
        "<input id='v_date' type='date' value='" + K.today() + "'></label>" +
      "<label class='field' style='flex:1 1 220px'><span>業者さん・金額など（任意）</span>" +
        "<input id='v_note' placeholder='例： ○○クリーニング 22,000円'></label>" +
      "</div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='v_no'>やめる</button> " +
      "<button class='btn primary' id='v_ok'>記録する</button></div>",
      function (root) {
        wide(root, 620);
        root.querySelector("#v_no").addEventListener("click", K.closeModal);
        root.querySelector("#v_ok").addEventListener("click", function () {
          K.rpc("clean_done", {
            p_store: K.S.store.id, p_spot: p.id, p_date: $("v_date").value || K.today(),
            p_kind: "pro", p_note: ($("v_note").value || "").trim() || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); K.toast("記録しました");
            loadPro(); loadSpots(); loadToday();
          });
        });
      });
  }

  /* ================================================================ 画面 */

  function wide(root, px) {
    var b = root.querySelector(".box");
    if (b) b.style.maxWidth = px + "px";
  }

  (function () {
    var st = document.createElement("style");
    st.textContent = "#modalRoot b{display:inline; margin:0}";
    (document.head || document.documentElement).appendChild(st);
  })();

  function switchView(v) {
    VIEWS.forEach(function (n) {
      var s = $("view-" + n);
      if (s) s.classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    try { localStorage.setItem("dandori-souji-tab", v); } catch (e) {}
    if (v === "today") loadToday();
    if (v === "spot") loadSpots();
    if (v === "pro") loadPro();
  }

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  $("dDate").addEventListener("change", loadToday);
  $("dReload").addEventListener("click", loadToday);
  $("dAdd").addEventListener("click", addExtra);
  $("dPrint").addEventListener("click", openPrint);

  var sn = $("sNew"); if (sn) sn.addEventListener("click", function () { openSpot(null); });
  var sr = $("sReload"); if (sr) sr.addEventListener("click", loadSpots);
  var ss = $("sSeed"); if (ss) ss.addEventListener("click", function () {
    K.confirm("ひな形を入れます",
      "<p>この業種でよくある清掃の場所を、まとめて登録します。<br>" +
      "いらないものは、あとから外せます。同じ名前のものは増えません。</p>",
      "入れる", function () {
        K.rpc("clean_seed", { p_store: K.S.store.id, p_kind: null })
          .then(function (n) {
            K.closeModal();
            if (n === null) return;
            K.toast("入れました"); loadSpots(); loadPro(); loadToday();
          });
      });
  });
  var pr = $("pReload"); if (pr) pr.addEventListener("click", loadPro);

  K.wireLogin();
  K.boot(function () {
    if (!$("dDate").value) $("dDate").value = K.today();
    var keep = "today";
    try { keep = localStorage.getItem("dandori-souji-tab") || "today"; } catch (e) {}
    if (VIEWS.indexOf(keep) < 0) keep = "today";
    switchView(keep);
  });
})();
