/* ============================================================================
   だんどりシリーズ / Excel（.xlsx）をブラウザの中だけで読む小さな部品
   xlsx.js
   置き場所： サイトのルート（payroll.html と同じ階層）

   使い方：
     DANDORI_XLSX.read(file).then(function (book) {
       var sh = book.find(/総合計/);      // 名前で（正規表現）シートを探す
       sh.cell(4, 2);                      // 4行目・B列の値（数値・文字。式は Excel が保存した計算結果）
       sh.rows;                            // 値のある行番号（小さい順）
       sh.maxCol;                          // いちばん右の列番号
     });

   ・外のサーバーには何も送りません。ライブラリも読みこみません（.xlsx は zip なので、
     ブラウザに入っている展開機能 DecompressionStream を使います。iPhone は iOS 16.4 以降）。
   ・画面の JS は ES5 で書くきまりなので、ここも ES5 です。
   ============================================================================ */
(function () {
  "use strict";

  function u16(b, p) { return b[p] | (b[p + 1] << 8); }
  function u32(b, p) { return (b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)) >>> 0; }

  function readFile(file) {
    return new Promise(function (ok, ng) {
      var fr = new FileReader();
      fr.onload = function () { ok(new Uint8Array(fr.result)); };
      fr.onerror = function () { ng(new Error("ファイルを読めませんでした")); };
      fr.readAsArrayBuffer(file);
    });
  }

  function inflate(bytes) {
    if (typeof DecompressionStream === "undefined") {
      return Promise.reject(new Error("このブラウザでは Excel を読めません。Chrome か、新しい Safari で開いてください。"));
    }
    var ds = new DecompressionStream("deflate-raw");
    var stream = new Blob([bytes]).stream().pipeThrough(ds);
    return new Response(stream).arrayBuffer().then(function (ab) { return new Uint8Array(ab); });
  }

  /* zip の中のファイル一覧（名前 → 取り出す関数） */
  function unzip(b) {
    var dec = new TextDecoder("utf-8");
    var eocd = -1;
    for (var i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
      if (u32(b, i) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error("Excel（.xlsx）のファイルではないようです");
    var count = u16(b, eocd + 10);
    var p = u32(b, eocd + 16);
    var files = {};
    for (var n = 0; n < count; n++) {
      if (u32(b, p) !== 0x02014b50) break;
      var method = u16(b, p + 10);
      var csize = u32(b, p + 20);
      var nlen = u16(b, p + 28), xlen = u16(b, p + 30), clen = u16(b, p + 32);
      var off = u32(b, p + 42);
      var name = dec.decode(b.subarray(p + 46, p + 46 + nlen));
      files[name] = { method: method, csize: csize, off: off };
      p += 46 + nlen + xlen + clen;
    }
    return function (name) {
      var f = files[name];
      if (!f) return Promise.resolve(null);
      var start = f.off + 30 + u16(b, f.off + 26) + u16(b, f.off + 28);
      var data = b.subarray(start, start + f.csize);
      var got = f.method === 0 ? Promise.resolve(data) : inflate(data);
      return got.then(function (raw) { return dec.decode(raw); });
    };
  }

  function xml(text) { return text ? new DOMParser().parseFromString(text, "application/xml") : null; }
  function kids(el, tag) {
    var out = [];
    for (var c = el.firstChild; c; c = c.nextSibling) if (c.nodeType === 1 && (c.localName || c.nodeName) === tag) out.push(c);
    return out;
  }
  function colNum(ref) {
    var m = /^([A-Z]+)/.exec(ref || ""), n = 0;
    if (!m) return 0;
    for (var i = 0; i < m[1].length; i++) n = n * 26 + (m[1].charCodeAt(i) - 64);
    return n;
  }

  /* 共有文字列。ふりがな（rPh）は読まない */
  function sharedStrings(doc) {
    if (!doc) return [];
    return Array.prototype.map.call(doc.getElementsByTagName("si"), function (si) {
      var s = "";
      for (var c = si.firstChild; c; c = c.nextSibling) {
        var tag = c.localName || c.nodeName;
        if (tag === "t") s += c.textContent;
        else if (tag === "r") kids(c, "t").forEach(function (t) { s += t.textContent; });
      }
      return s;
    });
  }

  function sheet(doc, sst) {
    var data = {}, rows = [], maxCol = 0;
    Array.prototype.forEach.call(doc.getElementsByTagName("c"), function (c) {
      var ref = c.getAttribute("r");
      var row = Number((/(\d+)$/.exec(ref || "") || [])[1] || 0);
      var col = colNum(ref);
      if (!row || !col) return;
      var t = c.getAttribute("t");
      var v = kids(c, "v")[0];
      var val = null;
      if (t === "s") val = v ? sst[Number(v.textContent)] : null;
      else if (t === "inlineStr") { var is = kids(c, "is")[0]; val = is ? is.textContent : null; }
      else if (t === "str" || t === "e") val = v ? v.textContent : null;
      else if (t === "b") val = v ? v.textContent === "1" : null;
      else if (v) val = Number(v.textContent);
      if (val === null || val === "") return;
      if (!data[row]) { data[row] = {}; rows.push(row); }
      data[row][col] = val;
      if (col > maxCol) maxCol = col;
    });
    rows.sort(function (a, b) { return a - b; });
    return {
      rows: rows,
      maxCol: maxCol,
      cell: function (r, c) { return data[r] && data[r][c] !== undefined ? data[r][c] : null; }
    };
  }

  function read(file) {
    return readFile(file).then(function (bytes) {
      var get = unzip(bytes);
      return Promise.all([get("xl/workbook.xml"), get("xl/_rels/workbook.xml.rels"), get("xl/sharedStrings.xml")])
        .then(function (r) {
          var wb = xml(r[0]), rels = xml(r[1]);
          if (!wb || !rels) throw new Error("Excel（.xlsx）のファイルではないようです");
          var sst = sharedStrings(xml(r[2]));
          var target = {};
          Array.prototype.forEach.call(rels.getElementsByTagName("Relationship"), function (x) {
            var t = x.getAttribute("Target") || "";
            target[x.getAttribute("Id")] = t.charAt(0) === "/" ? t.slice(1) : "xl/" + t;
          });
          var list = Array.prototype.map.call(wb.getElementsByTagName("sheet"), function (s) {
            var rid = s.getAttribute("r:id") ||
              s.getAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "id");
            return { name: s.getAttribute("name"), path: target[rid] };
          });
          return Promise.all(list.map(function (s) { return get(s.path); })).then(function (texts) {
            var sheets = list.map(function (s, i) {
              var sh = sheet(xml(texts[i]), sst);
              sh.name = s.name;
              return sh;
            });
            return {
              sheets: sheets,
              find: function (re) { return sheets.filter(function (s) { return re.test(s.name); })[0] || null; }
            };
          });
        });
    });
  }

  window.DANDORI_XLSX = { read: read };
})();
