/* ============================================================================
   だんどりシリーズ / 背景に使う写真
   photo.js
   置き場所： サイトのルート（theme.html と同じ階層）

   ふたつのやり方があります。
     1. パソコン・スマホから取りこむ
        大きい写真は、こちらで小さくしてから入れます（通信と置き場所の節約）。
        入れた写真は、お店（法人）ごとに仕切られた場所にしまわれます。
     2. さがす
        Supabase の Edge Function「photo-search」を通して、写真をさがします。
        さがす鍵は、その関数の Secrets に入れてあります。
        <ブラウザには一切出ません。>

   だいじなこと
     ・よそのサイトの写真を、だまって持ってくることはしません。
     ・さがした写真は、そのままのアドレスを見にいきます。
       その先が消えると出なくなるので、長く使うものは
       「取りこむ」のほうをおすすめします。
   ============================================================================ */

(function () {
  "use strict";

  var MAXW = 1600;      /* これより大きい写真は、ここまで縮めます */
  var Q = 0.72;         /* JPEGの画質 */
  var MAXMB = 12;       /* これより大きいファイルは、はじめから断ります */

  /* ------------------------------------------------- 1. 取りこむ（縮める） */

  function shrink(file) {
    return new Promise(function (ok, ng) {
      if (!file) { ng(new Error("ファイルがえらばれていません")); return; }
      if (file.size > MAXMB * 1024 * 1024) {
        ng(new Error(MAXMB + "MBまでにしてください。写真なら、もう少し小さく撮ってください"));
        return;
      }
      var fr = new FileReader();
      fr.onerror = function () { ng(new Error("ファイルが読めませんでした")); };
      fr.onload = function () {
        var im = new Image();
        im.onerror = function () { ng(new Error("画像として読めませんでした")); };
        im.onload = function () {
          var w = im.width, h = im.height;
          if (w > MAXW) { h = Math.round(h * MAXW / w); w = MAXW; }
          var cv = document.createElement("canvas");
          cv.width = w; cv.height = h;
          var cx = cv.getContext("2d");
          cx.fillStyle = "#ffffff"; cx.fillRect(0, 0, w, h);
          cx.drawImage(im, 0, 0, w, h);
          cv.toBlob(function (b) {
            if (!b) { ng(new Error("小さくできませんでした")); return; }
            ok(b);
          }, "image/jpeg", Q);
        };
        im.src = fr.result;
      };
      fr.readAsDataURL(file);
    });
  }

  /*  Supabase の置き場所に入れて、見にいくアドレスを返します */
  function upload(sb, file) {
    return shrink(file).then(function (blob) {
      return sb.rpc("ui_bg_path", { p_ext: "jpg" }).then(function (q) {
        if (q.error) throw q.error;
        var path = q.data;
        return sb.storage.from("ui")
          .upload(path, blob, { upsert: true, contentType: "image/jpeg" })
          .then(function (r) {
            if (r.error) throw r.error;
            return path;
          });
      });
    });
  }

  /*  しまってある写真は、そのままでは見られないので、
      期限つきの見るためのアドレスをもらいます（7日）。 */
  function signed(sb, path) {
    if (!path) return Promise.resolve("");
    if (/^https?:\/\//i.test(path)) return Promise.resolve(path);   /* さがした写真 */
    return sb.storage.from("ui").createSignedUrl(path, 60 * 60 * 24 * 7)
      .then(function (r) {
        return (r && r.data && r.data.signedUrl) ? r.data.signedUrl : "";
      }).catch(function () { return ""; });
  }

  /* ------------------------------------------------------------ 2. さがす */

  function search(word) {
    var CFG = window.DANDORI_CONFIG || {};
    var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

    return sb.auth.getSession().then(function (r) {
      var tok = (r && r.data && r.data.session && r.data.session.access_token) || "";
      return fetch(CFG.supabaseUrl + "/functions/v1/photo-search", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": CFG.supabaseAnonKey,
          "Authorization": "Bearer " + tok
        },
        body: JSON.stringify({ q: word })
      });
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (!r.ok) {
          var m = j && j.error ? j.error : "さがせませんでした（" + r.status + "）";
          if (j && j.code === "no_key") {
            m = "写真をさがす準備がまだできていません。" +
                "「取りこむ」のほうをお使いください。";
          }
          throw new Error(m);
        }
        return j.results || [];
      });
    });
  }

  function credit(p) {
    return [p.title, p.by ? "／" + p.by : "",
            p.from ? "（" + p.from + "）" : "",
            p.page ? " " + p.page : ""].join("");
  }

  window.DANDORI_PHOTO = {
    upload: upload, signed: signed, search: search, credit: credit, shrink: shrink
  };
})();
