/* ============================================================================
   ナイトだんどり / 領収書の印刷
   receipt.js   置き場所： サイトのルート（index.html・sales.html から読みこみ）

     DANDORI_RECEIPT.open({ store: S.store, visit: v, items: [...], to: "〇〇様" })
       → 新しいタブに領収書を出して、印刷ダイアログを開きます（ES5）
   ============================================================================ */
(function () {
  "use strict";
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function yen(n) { return "¥" + (Number(n) || 0).toLocaleString("ja-JP"); }
  function jdate(iso) {
    var d = iso ? new Date(iso) : new Date();
    return d.getFullYear() + "年" + (d.getMonth() + 1) + "月" + d.getDate() + "日";
  }
  function open(o) {
    var st = o.store || {}, v = o.visit || {}, items = o.items || [];
    var no = (v.id || "").replace(/-/g, "").slice(0, 8).toUpperCase();
    var lines = items.map(function (i) {
      return "<tr><td>" + esc(i.name) + "</td><td class='n'>" + (i.quantity || 1) + "</td><td class='n'>" + yen(i.amount) + "</td></tr>";
    }).join("");
    var html = "<!doctype html><html lang='ja'><head><meta charset='utf-8'><title>領収書</title>" +
      "<style>body{font-family:'Hiragino Sans','Yu Gothic',sans-serif;color:#111;margin:0;padding:28px;max-width:640px}" +
      "h1{font-size:26px;letter-spacing:.3em;text-align:center;margin:0 0 18px}" +
      ".to{font-size:20px;border-bottom:1px solid #111;padding:6px 4px;margin:14px 0}" +
      ".amt{font-size:30px;font-weight:700;border-bottom:3px double #111;padding:8px 4px;margin:10px 0 4px}" +
      ".tadashi{margin:6px 4px 18px}.meta{display:flex;justify-content:space-between;font-size:13px;color:#333}" +
      "table{width:100%;border-collapse:collapse;font-size:13px;margin-top:14px}td,th{padding:4px 6px;border-bottom:1px solid #ccc}" +
      ".n{text-align:right}.store{margin-top:26px;text-align:right;font-size:13px;line-height:1.6}" +
      ".stamp{display:inline-block;border:2px solid #c33;color:#c33;border-radius:50%;width:54px;height:54px;line-height:54px;text-align:center;font-size:12px;margin-left:12px;vertical-align:middle}" +
      "@media print{button{display:none}}</style></head><body>" +
      "<div class='meta'><span>No. " + esc(no) + "</span><span>" + jdate(v.closed_at) + "</span></div>" +
      "<h1>領収書</h1>" +
      "<div class='to'>" + esc(o.to || ((v.guest || v.guest_name) ? (v.guest || v.guest_name) + " 様" : "上様")) + "</div>" +
      "<div class='amt'>金 " + yen(v.total) + " −</div>" +
      "<div class='tadashi'>但し　" + esc(o.note || "お飲食代として") + "　上記正に領収いたしました</div>" +
      (lines ? "<table><tr><th style='text-align:left'>内訳</th><th class='n'>数</th><th class='n'>金額</th></tr>" + lines +
        (v.service_charge ? "<tr><td>サービス料</td><td></td><td class='n'>" + yen(v.service_charge) + "</td></tr>" : "") +
        (v.tax ? "<tr><td>消費税</td><td></td><td class='n'>" + yen(v.tax) + "</td></tr>" : "") +
        (v.discount ? "<tr><td>値引き</td><td></td><td class='n'>−" + yen(v.discount) + "</td></tr>" : "") +
        (v.round_adj ? "<tr><td>端数調整</td><td></td><td class='n'>" + yen(v.round_adj) + "</td></tr>" : "") +
        "</table>" : "") +
      "<div class='store'><b>" + esc(st.name || "") + "</b>" +
        (st.address ? "<br>" + esc(st.address) : "") + (st.tel ? "<br>TEL " + esc(st.tel) : "") +
        "<span class='stamp'>収入印紙</span></div>" +
      "<p style='text-align:center;margin-top:24px'><button onclick='window.print()' style='padding:10px 24px;font-size:15px'>印刷する</button></p>" +
      "</body></html>";
    var w = window.open("", "_blank");
    if (!w) { alert("ポップアップがブロックされました。許可してからもう一度押してください"); return; }
    w.document.open(); w.document.write(html); w.document.close();
    setTimeout(function () { try { w.focus(); w.print(); } catch (e) {} }, 400);
  }
  window.DANDORI_RECEIPT = { open: open };
})();
