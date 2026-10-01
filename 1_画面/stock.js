/* ============================================================================
   だんどりシリーズ / 在庫・発注
   stock.js
   置き場所： サイトのルート（stock.html と同じ階層）

   画面は2つに分かれています。
     ・商品・在庫 … どなたでも見られます。「使った」「捨てた」を入れるところ。
     ・発注　　　 … 店長以上の方だけ。足りない物から下書きを作り、
                    発注ずみ → 納品 と進めると、在庫が自動で増えます。

   仕入値は、店長以上の方にしか出ません（データベース側でも隠しています）。
   ============================================================================ */

(function () {
  "use strict";

  var $ = K.$, esc = K.esc;
  var VIEWS = ["list", "order"];
  var ROWS = [];          /* 商品の一覧 */
  var ORDERS = [];        /* 発注書の一覧 */
  var SEED = "night";     /* ひな形の種類。stock.html の data-seed で決まります */

  var MOVE = [
    { v: "in",    t: "仕入れ（増やす）" },
    { v: "use",   t: "使った（減らす）" },
    { v: "waste", t: "捨てた（減らす）" },
    { v: "count", t: "棚卸（数を合わせる）" }
  ];

  var STATUS = [
    { v: "",         t: "すべて" },
    { v: "draft",    t: "下書き" },
    { v: "sent",     t: "発注ずみ" },
    { v: "received", t: "納品ずみ" },
    { v: "cancel",   t: "取り消し" }
  ];

  function qty(n) {
    var v = Number(n) || 0;
    return (Math.round(v * 100) / 100).toString();
  }

  /*  style.css の「.box b は改行する」は、お知らせの箱のためのものです。
      小窓の中では、文のとちゅうで改行されると読みにくいので、もどします。 */
  (function () {
    var st = document.createElement("style");
    st.textContent = "#modalRoot b{display:inline; margin:0}";
    (document.head || document.documentElement).appendChild(st);
  })();

  /*  小窓は、中身によって広さを変えます（style.css は 420px までのため） */
  function wide(root, px) {
    var b = root.querySelector(".box");
    if (b) b.style.maxWidth = px + "px";
  }

  function prod(id) {
    var a = ROWS.filter(function (p) { return p.id === id; });
    return a.length ? a[0] : null;
  }

  /* =========================================================== 商品・在庫 */

  function loadList() {
    return K.rpc("stock_product_list", {
      p_store: K.S.store.id,
      p_q: ($("pQ").value || "").trim() || null,
      p_all: false
    }).then(function (rows) {
      ROWS = rows || [];
      drawList();
    });
  }

  function drawList() {
    var low = ROWS.filter(function (p) { return p.low; });
    $("pLow").innerHTML = low.length
      ? "<div class='box warn'><b>そろそろ頼むものが " + low.length + " 品あります。</b><br>" +
        low.map(function (p) {
          return esc(p.name) + "（残り " + qty(p.stock) + esc(p.unit) + "）";
        }).join("　／　") +
        (K.isBoss()
          ? "<br><br><button class='btn primary' id='pGoOrder'>発注の画面をひらく</button>"
          : "<br><br><small>発注は、店長以上の方がまとめて行います。</small>") +
        "</div>"
      : "";

    if (!ROWS.length) {
      $("pTable").innerHTML = "";
      $("pEmpty").classList.remove("hidden");
      return;
    }
    $("pEmpty").classList.add("hidden");

    var boss = K.isBoss();
    var body = ROWS.map(function (p) {
      return "<tr class='" + (p.low ? "bad" : "") + "'>" +
        "<td><b>" + esc(p.name) + "</b>" +
          (p.maker ? "<br><small>" + esc(p.maker) + "</small>" : "") + "</td>" +
        "<td class='nw'>" + esc(p.category || "—") + "</td>" +
        "<td class='num'><b>" + qty(p.stock) + "</b> " + esc(p.unit) + "</td>" +
        "<td class='num'>" + (p.reorder_point > 0 ? qty(p.reorder_point) : "—") + "</td>" +
        (boss ? "<td class='num'>" + K.yen(p.cost) + "</td>" : "") +
        "<td>" + (p.low ? K.pill("そろそろ") : "") + "</td>" +
        "<td class='right nw'>" +
          "<button class='btn ghost' data-move='" + p.id + "'>出し入れ</button> " +
          "<button class='btn ghost' data-hist='" + p.id + "'>記録</button>" +
          (boss ? " <button class='btn ghost' data-edit='" + p.id + "'>直す</button>" : "") +
        "</td></tr>";
    });

    var head = ["品名", "分類", { label: "在庫", num: true },
                { label: "発注点", num: true }];
    if (boss) head.push({ label: "仕入値", num: true });
    head.push("", "");

    $("pTable").innerHTML = K.table(head, body);
    K.bind($("pTable"), "[data-move]", "move", openMove);
    K.bind($("pTable"), "[data-hist]", "hist", openHistory);
    K.bind($("pTable"), "[data-edit]", "edit", function (id) { openProduct(prod(id)); });

    var g = $("pGoOrder");
    if (g) g.addEventListener("click", function () { switchView("order"); });
  }

  /* --------------------------------------------------- 商品をふやす・直す */

  function openProduct(p) {
    K.modal(
      "<h2 style='margin-top:0'>" + (p ? "商品を直す" : "商品を足す") + "</h2>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:2 1 220px'><span>品名</span>" +
        "<input id='f_name' value='" + esc(p ? p.name : "") + "'></label>" +
      "<label class='field' style='flex:1 1 140px'><span>分類</span>" +
        "<input id='f_cat' placeholder='ドリンク・消耗品 など' value='" +
        esc(p ? (p.category || "") : "") + "'></label>" +
      "<label class='field' style='flex:1 1 120px'><span>メーカー・銘柄</span>" +
        "<input id='f_maker' value='" + esc(p ? (p.maker || "") : "") + "'></label>" +
      "<label class='field' style='flex:0 0 90px'><span>単位</span>" +
        "<input id='f_unit' value='" + esc(p ? p.unit : "本") + "'></label>" +
      "<label class='field' style='flex:0 0 120px'><span>仕入値（円）</span>" +
        "<input id='f_cost' type='number' min='0' value='" + (p ? p.cost : 0) + "'></label>" +
      "<label class='field' style='flex:0 0 130px'><span>発注点</span>" +
        "<input id='f_pt' type='number' step='0.5' min='0' value='" +
        (p ? qty(p.reorder_point) : 0) + "'></label>" +
      "<label class='field' style='flex:0 0 140px'><span>1回に頼む数</span>" +
        "<input id='f_qty' type='number' step='0.5' min='0' value='" +
        (p ? qty(p.reorder_qty) : 0) + "'></label>" +
      "<label class='field' style='flex:1 1 160px'><span>仕入先</span>" +
        "<input id='f_sup' value='" + esc(p ? (p.supplier || "") : "") + "'></label>" +
      "</div>" +
      "<p style='color:var(--muted);font-size:12.5px;margin:6px 0 0'>" +
      "発注点は「これを切ったら頼む数」です。0 にすると、お知らせしません。</p>" +
      (p ? "" :
        "<p style='color:var(--muted);font-size:12.5px;margin:2px 0 0'>" +
        "いまの在庫は、登録したあと「出し入れ」の <b>棚卸</b> で合わせてください。</p>") +
      "<div class='row' style='justify-content:space-between;margin-top:16px'>" +
        "<span>" + (p ? "<button class='btn ghost' id='f_del'>使わなくする</button>" : "") + "</span>" +
        "<span><button class='btn ghost' id='f_no'>やめる</button> " +
        "<button class='btn primary' id='f_ok'>保存する</button></span>" +
      "</div>",
      function (root) {
        wide(root, 720);
        root.querySelector("#f_no").addEventListener("click", K.closeModal);
        root.querySelector("#f_ok").addEventListener("click", function () {
          var name = ($("f_name").value || "").trim();
          if (!name) { K.toast("品名を入れてください", "err"); return; }
          K.rpc("stock_product_save", {
            p_store: K.S.store.id,
            p_id: p ? p.id : null,
            p_name: name,
            p_maker: ($("f_maker").value || "").trim() || null,
            p_category: ($("f_cat").value || "").trim() || null,
            p_unit: ($("f_unit").value || "").trim() || "個",
            p_cost: Number($("f_cost").value) || 0,
            p_point: Number($("f_pt").value) || 0,
            p_qty: Number($("f_qty").value) || 0,
            p_supplier: ($("f_sup").value || "").trim() || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); K.toast("保存しました"); loadList();
          });
        });
        var d = root.querySelector("#f_del");
        if (d) d.addEventListener("click", function () {
          K.confirm("使わなくします", "<p>" + esc(p.name) +
            " を、一覧から外します。<br>これまでの記録は残ります。</p>", "外す", function () {
            K.rpc("stock_product_save", {
              p_store: K.S.store.id, p_id: p.id, p_active: false
            }).then(function (r) {
              if (!r) return;
              K.closeModal(); K.toast("外しました"); loadList();
            });
          });
        });
      });
  }

  /* --------------------------------------------------------- 出し入れ */

  function openMove(id) {
    var p = prod(id);
    if (!p) return;
    K.modal(
      "<h2 style='margin-top:0'>" + esc(p.name) + "</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
      "いまの在庫　<b style='font-size:17px;color:var(--ink)'>" + qty(p.stock) + "</b> " +
      esc(p.unit) + "</p>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:1 1 200px'><span>どうしますか</span>" +
        "<select id='m_kind'>" + MOVE.map(function (m) {
          return "<option value='" + m.v + "'>" + esc(m.t) + "</option>";
        }).join("") + "</select></label>" +
      "<label class='field' style='flex:0 0 130px'><span>数（" + esc(p.unit) + "）</span>" +
        "<input id='m_qty' type='number' step='0.5' min='0' value='1'></label>" +
      "<label class='field' style='flex:0 0 160px'><span>日にち</span>" +
        "<input id='m_date' type='date' value='" + K.today() + "'></label>" +
      "<label class='field' style='flex:1 1 220px'><span>メモ（任意）</span>" +
        "<input id='m_note' placeholder='割れた・お客様へ など'></label>" +
      "</div>" +
      "<div class='box' id='m_hint' style='margin-top:10px'></div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button> " +
      "<button class='btn primary' id='m_ok'>入れる</button></div>",
      function (root) {
        wide(root, 620);
        function hint() {
          var k = $("m_kind").value, n = Number($("m_qty").value) || 0;
          var after = k === "count" ? n
                    : k === "in" ? Number(p.stock) + n
                    : Number(p.stock) - n;
          $("m_hint").innerHTML =
            (k === "count"
              ? "数えた数をそのまま入れてください。在庫は <b>" + qty(n) + "</b> になります。"
              : "入れたあとの在庫は <b>" + qty(after) + "</b> " + esc(p.unit) + " になります。") +
            (after < 0 ? "<br><b style='color:#b34'>在庫がマイナスになります。数をご確認ください。</b>" : "");
        }
        root.querySelector("#m_kind").addEventListener("change", hint);
        root.querySelector("#m_qty").addEventListener("input", hint);
        hint();
        root.querySelector("#m_no").addEventListener("click", K.closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var k = $("m_kind").value, n = Number($("m_qty").value);
          if (k !== "count" && !(n > 0)) { K.toast("数を入れてください", "err"); return; }
          K.rpc("stock_move_add", {
            p_product: p.id, p_kind: k, p_qty: n,
            p_note: ($("m_note").value || "").trim() || null,
            p_date: $("m_date").value || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); K.toast("入れました"); loadList();
          });
        });
      });
  }

  function openHistory(id) {
    var p = prod(id);
    if (!p) return;
    K.rpc("stock_history", { p_product: id, p_limit: 60 }).then(function (rows) {
      rows = rows || [];
      var boss = K.isBoss();
      var body = rows.map(function (m) {
        return "<tr><td class='nw'>" + esc(m.ymd) + "</td>" +
          "<td class='nw'>" + esc(m.kind_label) + "</td>" +
          "<td class='num'><b>" + qty(m.qty) + "</b></td>" +
          (boss ? "<td class='num'>" + K.yen(m.amount) + "</td>" : "") +
          "<td>" + esc(m.note || "") + "</td>" +
          "<td class='nw'>" + esc(m.who || "") + "</td></tr>";
      });
      var head = ["日にち", "種類", { label: "数", num: true }];
      if (boss) head.push({ label: "金額", num: true });
      head.push("メモ", "入れた方");

      K.modal(
        "<h2 style='margin-top:0'>" + esc(p.name) + "　出し入れの記録</h2>" +
        (rows.length
          ? "<div class='scroll' style='max-height:60vh'><table class='list'>" +
            K.table(head, body) + "</table></div>"
          : K.empty("まだ記録がありません。")) +
        "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
        "<button class='btn ghost' id='h_no'>とじる</button></div>",
        function (root) {
          wide(root, 760);
          root.querySelector("#h_no").addEventListener("click", K.closeModal);
        });
    });
  }

  /* ================================================================ 発注 */

  function loadOrders() {
    if (!K.isBoss()) return Promise.resolve();
    return K.rpc("stock_order_list", {
      p_store: K.S.store.id,
      p_status: $("oStatus").value || null,
      p_limit: 60
    }).then(function (rows) {
      ORDERS = rows || [];
      drawOrders();
    });
  }

  function statusPill(s, label) {
    var kind = s === "received" ? "ok" : (s === "cancel" ? "bad" : "warn");
    return K.pill(label, kind);
  }

  function drawOrders() {
    if (!ORDERS.length) {
      $("oTable").innerHTML = "";
      $("oEmpty").classList.remove("hidden");
      return;
    }
    $("oEmpty").classList.add("hidden");
    var body = ORDERS.map(function (o) {
      return "<tr>" +
        "<td class='nw'>" + esc(o.ymd) + "</td>" +
        "<td><b>" + esc(o.supplier) + "</b>" +
          (o.deliver_ymd ? "<br><small>納品 " + esc(o.deliver_ymd) + "</small>" : "") + "</td>" +
        "<td class='num'>" + o.lines + " 品</td>" +
        "<td class='num'>" + K.yen(o.total) + "</td>" +
        "<td>" + statusPill(o.status, o.status_label) + "</td>" +
        "<td class='right nw'><button class='btn ghost' data-open='" + o.id + "'>ひらく</button></td>" +
        "</tr>";
    });
    $("oTable").innerHTML = K.table(
      ["発注日", "仕入先", { label: "品数", num: true }, { label: "金額", num: true }, "", ""],
      body);
    K.bind($("oTable"), "[data-open]", "open", openOrder);
  }

  function suggest() {
    K.confirm("足りないものから下書きを作ります",
      "<p>発注点を切っているものを、<b>仕入先ごとに1枚ずつ</b>まとめて、" +
      "下書きにします。<br>数はあとから直せます。この時点では、まだ発注していません。</p>",
      "下書きを作る",
      function () {
        K.rpc("stock_order_suggest", { p_store: K.S.store.id, p_supplier: null })
          .then(function (rows) {
            K.closeModal();
            if (!rows) return;
            if (!rows.length) { K.toast("いま足りないものはありません"); return; }
            K.toast("下書きを " + rows.length + " 枚つくりました");
            $("oStatus").value = "draft";
            loadOrders().then(function () {
              if (rows.length === 1) openOrder(rows[0].order_id);
            });
          });
      });
  }

  function openOrder(id) {
    K.rpc("stock_order_get", { p_order: id }).then(function (o) {
      if (!o) return;
      drawOrder(o);
    });
  }

  function drawOrder(o) {
    var draft = (o.status === "draft");
    var canRecv = (o.status === "draft" || o.status === "sent");
    var lines = o.lines || [];

    var body = lines.map(function (l) {
      return "<tr>" +
        "<td><b>" + esc(l.name) + "</b>" +
          (l.note ? "<br><small>" + esc(l.note) + "</small>" : "") + "</td>" +
        "<td class='num'>" +
          (draft
            ? "<input type='number' step='0.5' min='0' data-qty='" + l.id +
              "' value='" + qty(l.qty) + "' style='width:84px;text-align:right'>"
            : "<b>" + qty(l.qty) + "</b>") +
          " " + esc(l.unit || "") + "</td>" +
        "<td class='num'>" + K.yen(l.unit_price) + "</td>" +
        "<td class='num'>" + K.yen(l.amount) + "</td>" +
        (o.status === "received"
          ? "<td class='num'>" + qty(l.recv_qty) + "</td>" : "") +
        "<td class='right nw'>" +
          (draft ? "<button class='btn ghost' data-del='" + l.id + "'>消す</button>" : "") +
        "</td></tr>";
    });

    var head = ["品名", { label: "数", num: true }, { label: "単価", num: true },
                { label: "金額", num: true }];
    if (o.status === "received") head.push({ label: "届いた数", num: true });
    head.push("");

    K.modal(
      "<h2 style='margin-top:0'>発注書　" + esc(o.supplier) + "　" +
        statusPill(o.status, o.status_label) + "</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
        "発注日 " + esc(o.order_date) +
        (o.deliver_date ? "　／　納品 " + esc(o.deliver_date) : "") + "</p>" +

      (lines.length
        ? "<div class='scroll' style='max-height:44vh'><table class='list'>" +
          K.table(head, body) + "</table></div>"
        : K.empty("品がまだありません。")) +

      "<div class='row' style='justify-content:space-between;margin-top:10px'>" +
        "<b>合計（仕入値の目安）</b><b style='font-size:17px'>" + K.yen(o.total) + "</b>" +
      "</div>" +

      (draft
        ? "<div class='row' style='margin-top:12px;gap:8px;flex-wrap:wrap'>" +
          "<select id='o_add' style='flex:1 1 200px'><option value=''>品を足す…</option>" +
          ROWS.map(function (p) {
            return "<option value='" + p.id + "'>" + esc(p.name) +
                   "（残り " + qty(p.stock) + esc(p.unit) + "）</option>";
          }).join("") + "</select>" +
          "<input id='o_addq' type='number' step='0.5' min='0' value='1' " +
          "style='flex:0 0 90px;text-align:right'>" +
          "<button class='btn ghost' id='o_addbtn'>足す</button></div>"
        : "") +

      "<label class='field' style='margin-top:12px'><span>仕入先への一言（任意）</span>" +
        "<input id='o_note' value='" + esc(o.note || "") + "'" +
        (canRecv ? "" : " disabled") + "></label>" +

      "<div class='row' style='justify-content:space-between;margin-top:16px;flex-wrap:wrap;gap:8px'>" +
        "<span>" +
          (canRecv ? "<button class='btn ghost' id='o_cancel'>取り消す</button>" : "") +
        "</span>" +
        "<span class='row' style='gap:8px;flex-wrap:wrap'>" +
          "<button class='btn ghost' id='o_close'>とじる</button>" +
          "<button class='btn ghost' id='o_copy'>文面をコピー</button>" +
          (draft ? "<button class='btn ghost' id='o_send'>発注ずみにする</button>" : "") +
          (canRecv ? "<button class='btn primary' id='o_recv'>納品した</button>" : "") +
        "</span>" +
      "</div>",

      function (root) {
        wide(root, 820);
        root.querySelector("#o_close").addEventListener("click", K.closeModal);

        /* 数を直す */
        Array.prototype.forEach.call(root.querySelectorAll("[data-qty]"), function (inp) {
          inp.addEventListener("change", function () {
            K.rpc("stock_order_line_set", {
              p_line: inp.dataset.qty, p_qty: Number(inp.value) || 0
            }).then(function (r) { if (r) openOrder(o.id); });
          });
        });

        K.bind(root, "[data-del]", "del", function (lid) {
          K.rpc("stock_order_line_remove", { p_line: lid })
            .then(function (r) { if (r !== null) openOrder(o.id); });
        });

        var ab = root.querySelector("#o_addbtn");
        if (ab) ab.addEventListener("click", function () {
          var pid = $("o_add").value;
          if (!pid) { K.toast("品をえらんでください", "err"); return; }
          K.rpc("stock_order_line_add", {
            p_order: o.id, p_product: pid, p_qty: Number($("o_addq").value) || 1
          }).then(function (r) { if (r) openOrder(o.id); });
        });

        root.querySelector("#o_copy").addEventListener("click", function () {
          saveNote(o).then(function () {
            return K.rpc("stock_order_text", { p_order: o.id });
          }).then(function (t) {
            if (!t) return;
            copy(t);
          });
        });

        var sd = root.querySelector("#o_send");
        if (sd) sd.addEventListener("click", function () {
          saveNote(o).then(function () {
            return K.rpc("stock_order_send", { p_order: o.id });
          }).then(function (r) {
            if (!r) return;
            K.toast("発注ずみにしました");
            K.closeModal(); loadOrders();
          });
        });

        var rc = root.querySelector("#o_recv");
        if (rc) rc.addEventListener("click", function () { openReceive(o); });

        var cc = root.querySelector("#o_cancel");
        if (cc) cc.addEventListener("click", function () {
          K.confirm("この発注を取り消します",
            "<p>取り消すと、一覧には「取り消し」として残ります。</p>", "取り消す", function () {
              K.rpc("stock_order_cancel", { p_order: o.id }).then(function (r) {
                if (!r) return;
                K.closeModal(); K.toast("取り消しました"); loadOrders();
              });
            });
        });
      });
  }

  function saveNote(o) {
    var el = $("o_note");
    if (!el || el.disabled || (el.value || "") === (o.note || "")) return Promise.resolve();
    return K.rpc("stock_order_note", { p_order: o.id, p_note: el.value });
  }

  function openReceive(o) {
    K.rpc("stock_order_get", { p_order: o.id }).then(function (cur) {
      if (!cur) return;
      var lines = cur.lines || [];
      var body = lines.map(function (l) {
        return "<tr><td><b>" + esc(l.name) + "</b></td>" +
          "<td class='num'>" + qty(l.qty) + " " + esc(l.unit || "") + "</td>" +
          "<td class='num'><input type='number' step='0.5' min='0' data-rq='" + l.id +
            "' value='" + qty(l.qty) + "' style='width:84px;text-align:right'></td></tr>";
      });
      K.modal(
        "<h2 style='margin-top:0'>納品を入れます</h2>" +
        "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
        "届いた数を入れてください。そのぶんだけ、在庫がふえます。<br>" +
        "頼んだ数のままで良ければ、そのまま「納品する」を押してください。</p>" +
        "<label class='field' style='max-width:200px'><span>納品の日</span>" +
          "<input id='r_date' type='date' value='" + K.today() + "'></label>" +
        "<div class='scroll' style='max-height:40vh;margin-top:10px'><table class='list'>" +
          K.table(["品名", { label: "頼んだ数", num: true }, { label: "届いた数", num: true }], body) +
        "</table></div>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn ghost' id='r_no'>やめる</button> " +
        "<button class='btn primary' id='r_ok'>納品する</button></div>",
        function (root) {
          wide(root, 700);
          root.querySelector("#r_no").addEventListener("click", function () { openOrder(o.id); });
          root.querySelector("#r_ok").addEventListener("click", function () {
            var arr = [];
            Array.prototype.forEach.call(root.querySelectorAll("[data-rq]"), function (i) {
              arr.push({ line: i.dataset.rq, qty: Number(i.value) || 0 });
            });
            K.rpc("stock_order_receive", {
              p_order: o.id, p_lines: arr, p_date: $("r_date").value || null
            }).then(function (r) {
              if (!r) return;
              K.closeModal();
              K.toast("納品を入れました。在庫にくわえました");
              loadOrders(); loadList();
            });
          });
        });
    });
  }

  function copy(text) {
    K.modal(
      "<h2 style='margin-top:0'>仕入先へ送る文面</h2>" +
      "<textarea id='c_t' rows='14' style='width:100%'>" + esc(text) + "</textarea>" +
      "<p style='color:var(--muted);font-size:12.5px'>" +
      "コピーして、LINEやメールに貼りつけてください。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:12px'>" +
      "<button class='btn ghost' id='c_no'>とじる</button> " +
      "<button class='btn primary' id='c_ok'>コピーする</button></div>",
      function (root) {
        wide(root, 700);
        root.querySelector("#c_no").addEventListener("click", K.closeModal);
        root.querySelector("#c_ok").addEventListener("click", function () {
          var t = $("c_t");
          t.select();
          try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
              navigator.clipboard.writeText(t.value);
            } else { document.execCommand("copy"); }
            K.toast("コピーしました");
          } catch (e) { K.toast("コピーできませんでした。手で選んでコピーしてください", "err"); }
        });
      });
  }

  /* ============================================================== 画面 */

  function switchView(v) {
    VIEWS.forEach(function (n) {
      var s = $("view-" + n);
      if (s) s.classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    try { localStorage.setItem("dandori-stock-tab", v); } catch (e) {}
    if (v === "list") loadList();
    if (v === "order") loadOrders();
  }

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  $("pNew").addEventListener("click", function () { openProduct(null); });
  $("pReload").addEventListener("click", loadList);
  $("pQ").addEventListener("input", function () { loadList(); });
  $("pSeed").addEventListener("click", function () {
    K.confirm("ひな形を入れます",
      "<p>よく使うものを、まとめて登録します。<br>" +
      "いらないものは、あとから外せます。同じ名前のものは増えません。</p>",
      "入れる", function () {
        K.rpc("stock_seed_product", { p_store: K.S.store.id, p_kind: SEED })
          .then(function (n) {
            K.closeModal();
            if (n === null) return;
            K.toast("入れました"); loadList();
          });
      });
  });

  var oS = $("oSuggest"); if (oS) oS.addEventListener("click", suggest);
  var oN = $("oNew"); if (oN) oN.addEventListener("click", function () {
    K.modal(
      "<h2 style='margin-top:0'>からの発注書を作ります</h2>" +
      "<label class='field'><span>仕入先</span><input id='n_sup' placeholder='酒販店 など'></label>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='n_no'>やめる</button> " +
      "<button class='btn primary' id='n_ok'>作る</button></div>",
      function (root) {
        root.querySelector("#n_no").addEventListener("click", K.closeModal);
        root.querySelector("#n_ok").addEventListener("click", function () {
          K.rpc("stock_order_new", {
            p_store: K.S.store.id,
            p_supplier: ($("n_sup").value || "").trim() || null
          }).then(function (o) {
            if (!o) return;
            K.closeModal(); loadOrders(); openOrder(o.id);
          });
        });
      });
  });
  var oR = $("oReload"); if (oR) oR.addEventListener("click", loadOrders);
  var oT = $("oStatus"); if (oT) oT.addEventListener("change", loadOrders);

  K.wireLogin();
  K.boot(function () {
    var el = document.querySelector("[data-seed]");
    if (el) SEED = el.getAttribute("data-seed") || "night";
    var keep = "list";
    try { keep = localStorage.getItem("dandori-stock-tab") || "list"; } catch (e) {}
    if (keep === "order" && !K.isBoss()) keep = "list";
    switchView(keep);
  });
})();
