/* ============================================================================
   ナイトだんどり / 売上の詳細（その日の伝票ごとの内訳）
   salesdetail.js   置き場所： サイトのルート（sales.html・close.html から読みこみ）

     DANDORI_SALESDETAIL.render(el, { sb, store, date, onChange })
       → el の中に、その日の伝票（卓ごと）の明細・支払い・ついたキャストを出す（ES5）
       ・会計ずみの伝票には「領収書」（receipt.js があれば）
       ・店長には「この伝票を消す」（試しの売上の削除など）
   ============================================================================ */
(function () {
  "use strict";
  var PAY = { cash: "現金", card: "カード", credit: "売掛", other: "その他" };
  var CAT = { set: "セット", extension: "延長", nomination: "指名", douhan: "同伴", drink: "ドリンク",
              bottle: "ボトル", champagne: "シャンパン", food: "フード", other: "その他" };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function yen(n) { return "¥" + (Number(n) || 0).toLocaleString("ja-JP"); }
  function hm(iso) {
    return iso ? new Date(iso).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }) : "";
  }
  function isBoss() {
    var P = window.DANDORI_PERM;
    return !!(P && P.role === "owner");
  }

  function render(el, o) {
    if (!el) return;
    el.innerHTML = "<p style='color:var(--muted)'>読みこんでいます…</p>";
    o.sb.rpc("night_sales_visits", { p_store: o.store.id, p_date: o.date }).then(function (q) {
      if (q.error) { el.innerHTML = "<p style='color:var(--bad)'>" + esc(q.error.message) + "</p>"; return; }
      var list = q.data || [];
      var closed = list.filter(function (v) { return v.status === "closed"; });
      var total = closed.reduce(function (a, v) { return a + v.total; }, 0);
      var guests = closed.reduce(function (a, v) { return a + (v.head_count || 0); }, 0);

      // 種類ごとの合計（その日）
      var byCat = {}, catOrder = [];
      closed.forEach(function (v) {
        v.items.forEach(function (i) {
          if (!byCat[i.category]) { byCat[i.category] = 0; catOrder.push(i.category); }
          byCat[i.category] += i.amount;
        });
      });

      var NW = "white-space:nowrap;display:inline-block;margin-right:16px";
      var head = "<div style='margin-bottom:8px;font-size:14px'>" +
        "<span style='" + NW + "'><span style='font-weight:700'>" + closed.length + "</span> 組　<span style='font-weight:700'>" + guests + "</span> 名</span>" +
        "<span style='" + NW + "'>合計 <span style='font-weight:700'>" + yen(total) + "</span></span>" +
        (list.length > closed.length ? "<span style='" + NW + ";color:var(--warn)'>会計前 " + (list.length - closed.length) + " 卓</span>" : "") +
        "</div>" +
        (catOrder.length ? "<div style='display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px'>" +
          catOrder.map(function (c) {
            return "<span class='tag' style='font-size:12px'>" + esc(CAT[c] || c) + " " + yen(byCat[c]) + "</span>";
          }).join("") + "</div>" : "");

      if (!list.length) { el.innerHTML = "<p style='color:var(--muted)'>この日の伝票はありません。</p>"; return; }

      el.innerHTML = head + list.map(function (v) {
        return "<details class='panel' style='margin-bottom:8px;padding:10px 14px'>" +
          "<summary style='cursor:pointer;list-style:none'>" +
            "<div class='row' style='justify-content:space-between;flex-wrap:wrap;gap:6px'>" +
              "<div><span style='font-weight:700'>" + esc(v.table_no || "—") + "</span>　" + esc(v.guest || "") + "　" + v.head_count + "名　" +
                "<span style='color:var(--muted);font-size:12px'>" + hm(v.entered_at) + "〜" + hm(v.closed_at) +
                "　" + esc(v.casts || "") + "</span>" +
                (v.status === "open" ? " <span class='tag open'>会計前</span>" : "") + "</div>" +
              "<div style='font-weight:700'>" + yen(v.total) + " <span style='color:var(--muted);font-size:11px;font-weight:400'>▾ 明細</span></div>" +
            "</div></summary>" +
          "<table class='list' style='margin-top:8px;font-size:12.5px'>" +
            v.items.map(function (i) {
              return "<tr><td><span style='color:var(--muted);font-size:11px'>" + esc(CAT[i.category] || i.category) + "</span> " +
                esc(i.name) + (i.cast ? " <small style='color:var(--muted)'>（バック：" + esc(i.cast) + "）</small>" : "") + "</td>" +
                "<td class='num'>×" + i.quantity + "</td><td class='num'>" + yen(i.amount) + "</td></tr>";
            }).join("") +
            "<tr><td>小計</td><td></td><td class='num'>" + yen(v.subtotal) + "</td></tr>" +
            (v.service_charge ? "<tr><td>サービス料</td><td></td><td class='num'>" + yen(v.service_charge) + "</td></tr>" : "") +
            (v.tax ? "<tr><td>消費税</td><td></td><td class='num'>" + yen(v.tax) + "</td></tr>" : "") +
            (v.discount ? "<tr><td>値引き</td><td></td><td class='num'>−" + yen(v.discount) + "</td></tr>" : "") +
            (v.round_adj ? "<tr><td>端数調整</td><td></td><td class='num'>" + yen(v.round_adj) + "</td></tr>" : "") +
            "<tr><td><span style='font-weight:700'>合計</span></td><td></td><td class='num'><span style='font-weight:700'>" + yen(v.total) + "</span></td></tr>" +
            (v.payments.length ? "<tr><td colspan='3' style='color:var(--muted)'>支払い：" +
              v.payments.map(function (p) { return (PAY[p.method] || p.method) + " " + yen(p.amount); }).join("／") + "</td></tr>" : "") +
          "</table>" +
          "<div class='row' style='justify-content:flex-end;gap:6px;margin-top:6px'>" +
            (v.status === "closed" && window.DANDORI_RECEIPT
              ? "<button class='btn ghost' style='padding:6px 12px' data-rc='" + v.id + "'>領収書</button>" : "") +
            (isBoss() || v.status === "open"
              ? "<button class='btn ghost danger' style='padding:6px 12px' data-vdel='" + v.id + "'>この伝票を消す</button>" : "") +
          "</div></details>";
      }).join("");

      Array.prototype.forEach.call(el.querySelectorAll("button[data-rc]"), function (b) {
        b.addEventListener("click", function () {
          var v = list.filter(function (x) { return x.id === b.dataset.rc; })[0];
          var to = window.prompt("領収書の宛名", v.guest ? v.guest + " 様" : "上様");
          if (to === null) return;
          window.DANDORI_RECEIPT.open({ store: o.store, visit: v, items: v.items, to: to.trim() || "上様" });
        });
      });
      Array.prototype.forEach.call(el.querySelectorAll("button[data-vdel]"), function (b) {
        b.addEventListener("click", function () {
          var v = list.filter(function (x) { return x.id === b.dataset.vdel; })[0];
          if (!window.confirm((v.table_no || "") + "　" + yen(v.total) + " の伝票を消します。注文・支払いも消え、元に戻せません。" +
              (v.status === "closed" ? "その日を締めてあれば締めは外れます。" : "") + "よろしいですか？")) return;
          o.sb.rpc("night_visit_delete", { p_visit: v.id }).then(function (q2) {
            if (q2.error) { window.alert(q2.error.message); return; }
            render(el, o);
            if (o.onChange) o.onChange(q2.data);
          });
        });
      });
    });
  }

  window.DANDORI_SALESDETAIL = { render: render };
})();
