/* ============================================================================
   だんどりシリーズ / 背景のかざり
   art.js
   置き場所： サイトのルート（index.html と同じ階層）
   読みこむ順： supabase.js → config.js → ui.js → art.js → その画面のJS

   ふたとおりあります。
     ポップ … 業種に合った小さな絵が、色つきでゆっくり舞います
     クール … お店の情景を、奥行きのある絵で置きます

   ＜写真を使いたいときは＞
     config.js の coolImage に、画像のアドレスを入れてください。
       coolImage: "art/salon.jpg"
     入れると、描いた絵のかわりにその写真が背景になります（薄くぼかして出ます）。
     空のままなら、下の絵を使います。

   どちらも
     ・薄く出します。文字の読みやすさはそのままです
     ・クリックはぜんぶ通り抜けます
     ・「動きを減らす」設定の端末では、動かしません
     ・お客様のネット予約ページには入れません

   絵はすべて、このファイルの中で図形から描いています。
   よその絵は1枚も使っていません。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var IND = CFG.industry || "night";      /* night / cast / food / salon / pet */

  /* ------------------------------------------------------- 小さな絵（色つき） */
  /*  16x16 の升目。f=ぬり色 / s=線の色 */

  var ICON = {
    /* ペット */
    dog: { f: "#C98A4B", s: "#8B5A2B",
      d: "M3.2 6.6c-.2-1.8.6-3.4 1.4-3.3.9.1 1.4 1.2 1.5 2.2m6.7 1.1c.2-1.8-.6-3.4-1.4-3.3-.9.1-1.4 1.2-1.5 2.2M4 8.2C4 5.9 5.8 4.6 8 4.6s4 1.3 4 3.6c0 3-1.8 5.2-4 5.2S4 11.2 4 8.2Z" },
    dogF:{ f: "#F2E3D0", s: "#8B5A2B", d: "M6.5 8.3h.01M9.5 8.3h.01M8 10.1a1.1 1.1 0 0 1-1.2-.9h2.4a1.1 1.1 0 0 1-1.2.9Z" },
    cat: { f: "#9AA7B4", s: "#5C6B7A",
      d: "M4.2 6.3 3 2.9l3 1.8M11.8 6.3 13 2.9l-3 1.8M4 7.8C4 5.5 5.8 4.2 8 4.2s4 1.3 4 3.6c0 3-1.8 5.2-4 5.2S4 10.8 4 7.8Z" },
    paw: { f: "#E58FA0", s: "#B95C70",
      d: "M5.4 4.4c.6 0 1 .8 1 1.7s-.4 1.7-1 1.7-1-.8-1-1.7.4-1.7 1-1.7Zm5.2 0c.6 0 1 .8 1 1.7s-.4 1.7-1 1.7-1-.8-1-1.7.4-1.7 1-1.7ZM2.9 8.4c.6 0 1 .7 1 1.5s-.4 1.5-1 1.5-1-.7-1-1.5.4-1.5 1-1.5Zm10.2 0c.6 0 1 .7 1 1.5s-.4 1.5-1 1.5-1-.7-1-1.5.4-1.5 1-1.5ZM8 8.2c1.9 0 3.4 1.7 3.4 3.2S10 14.2 8 14.2s-3.4-1.2-3.4-2.8S6.1 8.2 8 8.2Z" },
    bone:{ f: "#F3EDE2", s: "#A79881",
      d: "M4.2 6.2a1.6 1.6 0 1 1 1.4-2.2 1.6 1.6 0 1 1 1 2.4l4 3.4a1.6 1.6 0 1 1 1.5 2.1 1.6 1.6 0 1 1-1.2 2.3l-4.5-3.8Z" },
    fish:{ f: "#6FBEDC", s: "#2F7E9C",
      d: "M13 8c-1.7 2.1-3.8 3.2-5.8 3.2C4.8 11.2 2.7 9.7 1.6 8c1.1-1.7 3.2-3.2 5.6-3.2C9.2 4.8 11.3 5.9 13 8Zm0 0 2.2-2.2v4.4Z" },
    /* サロン */
    sciss:{ f: "#C6CDD6", s: "#6E7A88",
      d: "M4 2.8 11.2 11.4M12 2.8 4.8 11.4M3.4 12.6a1.6 1.6 0 1 0 2.4-2.1 1.6 1.6 0 0 0-2.4 2.1Zm6.8-2.1a1.6 1.6 0 1 0 2.4 2.1 1.6 1.6 0 0 0-2.4-2.1Z", line: 1 },
    comb: { f: "#7C5E8C", s: "#4E3A5A",
      d: "M1.8 5.2h12.4v2.4H1.8Zm1.6 2.4v5m2.2-5v5m2.4-5v5m2.2-5v5m2.2-5v5", line: 1 },
    shamp:{ f: "#86C9A8", s: "#3F8567",
      d: "M6.2 2.2h3.6v2.2H6.2Zm-1 2.2h5.6c.8 0 1.4.6 1.4 1.4v6.8c0 .8-.6 1.4-1.4 1.4H5.2c-.8 0-1.4-.6-1.4-1.4V5.8c0-.8.6-1.4 1.4-1.4Z" },
    dryer:{ f: "#E2A0A8", s: "#A85F6C",
      d: "M2.4 5h7.4a2.7 2.7 0 0 1 0 5.4H2.4Zm3.4 5.4v3.2M4.4 13.6h2.8" },
    mirror:{f: "#EFD79B", s: "#A98C3E",
      d: "M8 2a3.6 3.6 0 1 1 0 7.2A3.6 3.6 0 0 1 8 2Zm0 7.2v4.4m-1.8 0h3.6" },
    /* フード */
    carrot:{f: "#EE8B3C", s: "#B4601F",
      d: "M7.4 6 3 13.6l7.6-4.4A3.2 3.2 0 0 0 7.4 6Z" },
    carrotL:{f:"#63A85B", s: "#3C7A38", d: "M8.4 5 11 2.4M9.4 5.8l3-1.1" },
    tomato:{f: "#DE5148", s: "#9D2F29",
      d: "M8 4.4a4.2 4.2 0 1 1 0 8.4 4.2 4.2 0 0 1 0-8.4Z" },
    tomatoL:{f:"#63A85B", s: "#3C7A38", d: "M8 4.4V3m0 0 2-1.2M8 3 6 1.8" },
    apple:{ f: "#D9453F", s: "#992D2A",
      d: "M8 5.2C6.7 3.7 3.8 4 3.8 7.3c0 3.1 2.1 5.6 4.2 5.6s4.2-2.5 4.2-5.6c0-3.3-2.9-3.6-4.2-2.1Z" },
    appleL:{ f: "#63A85B", s: "#3C7A38", d: "M8 5.2V3m0 0 2.1-1.2" },
    grape:{ f: "#7E5AA8", s: "#4E3570",
      d: "M6 6.3a1.25 1.25 0 1 1 2.5 0 1.25 1.25 0 0 1-2.5 0Zm3.5 0a1.25 1.25 0 1 1 2.5 0 1.25 1.25 0 0 1-2.5 0ZM7.75 8.8a1.25 1.25 0 1 1 2.5 0 1.25 1.25 0 0 1-2.5 0ZM6 11.3a1.25 1.25 0 1 1 2.5 0 1.25 1.25 0 0 1-2.5 0Z" },
    grapeL:{f: "#63A85B", s: "#3C7A38", d: "M8 4.8V2.6m0 0 2.4-1" },
    cup:  { f: "#E8E2D6", s: "#9E927E",
      d: "M3.4 4.4h7.2v4.8a3.6 3.6 0 0 1-7.2 0Zm7.2.8h1.6a1.7 1.7 0 0 1 0 3.4h-1.6" },
    /* ナイト・キャスト（季節） */
    sakura:{f: "#F3AFC6", s: "#CE7699",
      d: "M8 3.2c1.1 0 1.9 1 1.9 2.3S9.1 7.8 8 7.8 6.1 6.8 6.1 5.5 6.9 3.2 8 3.2Zm3.8 2.3c.7.9.4 2.2-.7 3s-2.4.7-3.1-.2m0 0c.7.9.4 2.2-.7 3s-2.4.7-3.1-.2m0-5.6c-.7.9-.4 2.2.7 3s2.4.7 3.1-.2" },
    snow: { f: "#BFE3F2", s: "#6FA8C4",
      d: "M8 1.6v12.8M2.4 4.8l11.2 6.4M13.6 4.8 2.4 11.2M8 4.4 6.2 2.6M8 4.4l1.8-1.8M8 11.6l-1.8 1.8M8 11.6l1.8 1.8", line: 1 },
    maple:{ f: "#DD6B33", s: "#A34618",
      d: "M8 13.6v-2.8l-3.6 1.1 1.1-2.2-3.2-1.7 2.8-.7-1.3-3 2.8.9L8 2.2l1.4 3 2.8-.9-1.3 3 2.8.7-3.2 1.7 1.1 2.2L8 10.8Z" },
    sun:  { f: "#F5C242", s: "#C08E12",
      d: "M8 4.8a3.2 3.2 0 1 1 0 6.4 3.2 3.2 0 0 1 0-6.4Zm0-3.4v1.8m0 9.6v1.8M1.4 8h1.8m9.6 0h1.8M3.3 3.3l1.3 1.3m6.8 6.8 1.3 1.3m0-9.4-1.3 1.3m-6.8 6.8L3.3 12.7" },
    wave: { f: "#4FA8C9", s: "#2C7690",
      d: "M1.4 6.2c1.7-1.7 3.4-1.7 5.1 0s3.4 1.7 5.1 0 2.6-1.3 3.4-.6M1.4 10c1.7-1.7 3.4-1.7 5.1 0s3.4 1.7 5.1 0 2.6-1.3 3.4-.6", line: 1 },
    glass:{ f: "#3B4450", s: "#1E252E",
      d: "M1.4 5.4h13.2M2.8 5.4h4.4v1.9a2.2 2.2 0 0 1-4.4 0Zm5.6 0h4.4v1.9a2.2 2.2 0 0 1-4.4 0Z" }
  };

  /*  絵は「ぬる形」と「そえる形」を重ねます（葉っぱ・顔など） */
  var PARTS = {
    dog:   ["dog", "dogF"],
    carrot:["carrot", "carrotL"],
    tomato:["tomato", "tomatoL"],
    apple: ["apple", "appleL"],
    grape: ["grape", "grapeL"]
  };

  var POP = {
    pet:   ["dog", "cat", "paw", "bone", "fish", "paw"],
    salon: ["sciss", "comb", "shamp", "dryer", "mirror", "comb"],
    food:  ["carrot", "tomato", "apple", "grape", "cup", "tomato"],
    night: null,
    cast:  null
  };

  function season() {
    var m = new Date().getMonth() + 1;
    if (m >= 3 && m <= 5)  return ["sakura", "sakura", "sakura", "sun"];
    if (m >= 6 && m <= 8)  return ["sun", "wave", "glass", "wave"];
    if (m >= 9 && m <= 11) return ["maple", "maple", "maple", "sun"];
    return ["snow", "snow", "snow", "snow"];
  }

  function one(name) {
    var o = ICON[name];
    if (!o || !o.d) return "";
    return "<path d='" + o.d + "' fill='" + (o.line ? "none" : o.f) + "' stroke='" + o.s +
           "' stroke-width='.9' stroke-linecap='round' stroke-linejoin='round'/>";
  }

  function icon(name, size) {
    var names = PARTS[name] || [name];
    var body = names.map(one).join("");
    if (!body) return "";
    return "<svg viewBox='0 0 16 16' width='" + size + "' height='" + size + "' " +
           "xmlns='http://www.w3.org/2000/svg' aria-hidden='true' focusable='false'>" +
           body + "</svg>";
  }

  /* ------------------------------------------------ クール（お店の情景） */
  /*  奥行きが出るように、上下のぼかしと影を入れています。 */

  function g(id, a, b) {
    return "<linearGradient id='" + id + "' x1='0' y1='0' x2='0' y2='1'>" +
           "<stop offset='0' stop-color='" + a + "'/><stop offset='1' stop-color='" + b +
           "'/></linearGradient>";
  }

  var COOL = {
    /* トリミング室 */
    pet:
      "<defs>" + g("w", "#DCEAF2", "#B8D2E0") + g("f", "#C9B79E", "#A8947A") +
        g("t", "#E9EEF2", "#C3CDD5") + g("tb", "#BFD8E6", "#8FB6CC") + "</defs>" +
      "<rect width='1400' height='430' fill='url(#w)'/>" +
      "<rect y='430' width='1400' height='270' fill='url(#f)'/>" +
      "<rect x='980' y='90' width='360' height='250' rx='10' fill='#F3F7FA' opacity='.85'/>" +
      "<rect x='1000' y='150' width='320' height='16' rx='8' fill='#9FB2BF'/>" +
      "<rect x='1000' y='250' width='320' height='16' rx='8' fill='#9FB2BF'/>" +
      "<rect x='1040' y='100' width='44' height='46' rx='10' fill='#E58FA0'/>" +
      "<rect x='1110' y='100' width='36' height='46' rx='8' fill='#86C9A8'/>" +
      "<rect x='1180' y='196' width='40' height='50' rx='9' fill='#EFD79B'/>" +
      "<rect x='120' y='400' width='430' height='30' rx='12' fill='url(#t)'/>" +
      "<rect x='170' y='430' width='26' height='170' fill='#8E9AA5'/>" +
      "<rect x='474' y='430' width='26' height='170' fill='#8E9AA5'/>" +
      "<ellipse cx='335' cy='612' rx='215' ry='20' fill='#000' opacity='.12'/>" +
      "<rect x='620' y='390' width='320' height='190' rx='30' fill='url(#tb)'/>" +
      "<rect x='648' y='418' width='264' height='140' rx='22' fill='#EAF4FA'/>" +
      "<path d='M916 390V250h58' stroke='#8E9AA5' stroke-width='14' fill='none'/>" +
      "<circle cx='982' cy='250' r='24' fill='#C6CDD6'/>",
    /* 施術室 */
    salon:
      "<defs>" + g("w2", "#EFE7DC", "#D9CCBC") + g("f2", "#9E8368", "#7D664F") +
        g("ch", "#4A525C", "#2E343C") + g("mi", "#E8F1F6", "#BCD2DE") + "</defs>" +
      "<rect width='1400' height='440' fill='url(#w2)'/>" +
      "<rect y='440' width='1400' height='260' fill='url(#f2)'/>" +
      "<rect x='150' y='120' width='230' height='320' rx='14' fill='url(#mi)'/>" +
      "<rect x='166' y='136' width='198' height='288' rx='10' fill='#F7FBFD' opacity='.7'/>" +
      "<rect x='700' y='400' width='560' height='22' rx='10' fill='#C3B39E'/>" +
      "<rect x='902' y='300' width='38' height='100' rx='13' fill='#86C9A8'/>" +
      "<rect x='968' y='322' width='30' height='78' rx='11' fill='#E2A0A8'/>" +
      "<rect x='1026' y='334' width='26' height='66' rx='10' fill='#EFD79B'/>" +
      "<circle cx='792' cy='356' r='30' fill='none' stroke='#C6CDD6' stroke-width='12'/>" +
      "<path d='M420 330v-100a36 36 0 0 1 36-36h80a36 36 0 0 1 36 36v100Z' fill='url(#ch)'/>" +
      "<rect x='412' y='320' width='168' height='34' rx='14' fill='#39404A'/>" +
      "<rect x='478' y='354' width='36' height='170' fill='#6E7A88'/>" +
      "<ellipse cx='496' cy='540' rx='92' ry='18' fill='#4A525C'/>" +
      "<ellipse cx='496' cy='568' rx='120' ry='20' fill='#000' opacity='.14'/>",
    /* 厨房と客席 */
    food:
      "<defs>" + g("w3", "#E6E9EC", "#C8CED4") + g("f3", "#8A6F58", "#6B553F") +
        g("hd", "#BAC3CB", "#8F9AA4") + "</defs>" +
      "<rect width='1400' height='430' fill='url(#w3)'/>" +
      "<rect y='430' width='1400' height='270' fill='url(#f3)'/>" +
      "<rect x='110' y='120' width='350' height='76' rx='12' fill='url(#hd)'/>" +
      "<path d='M142 196h286l-44 62H186Z' fill='#A6B0B9'/>" +
      "<rect x='110' y='320' width='350' height='24' rx='8' fill='#9FA8B1'/>" +
      "<circle cx='196' cy='292' r='34' fill='#3B4450'/><circle cx='196' cy='292' r='20' fill='#59636F'/>" +
      "<circle cx='300' cy='292' r='34' fill='#3B4450'/><circle cx='300' cy='292' r='20' fill='#59636F'/>" +
      "<rect x='520' y='286' width='58' height='58' rx='8' fill='#DE5148'/>" +
      "<rect x='592' y='296' width='46' height='48' rx='8' fill='#63A85B'/>" +
      "<rect x='652' y='302' width='40' height='42' rx='8' fill='#EE8B3C'/>" +
      "<rect x='760' y='372' width='560' height='26' rx='12' fill='#C9A97F'/>" +
      "<rect x='840' y='470' width='18' height='120' fill='#6E7A88'/>" +
      "<ellipse cx='849' cy='462' rx='50' ry='16' fill='#DE5148'/>" +
      "<rect x='1010' y='470' width='18' height='120' fill='#6E7A88'/>" +
      "<ellipse cx='1019' cy='462' rx='50' ry='16' fill='#EFD79B'/>" +
      "<rect x='1180' y='470' width='18' height='120' fill='#6E7A88'/>" +
      "<ellipse cx='1189' cy='462' rx='50' ry='16' fill='#4FA8C9'/>" +
      "<ellipse cx='1020' cy='612' rx='300' ry='22' fill='#000' opacity='.12'/>",
    /* ホテルの一室 */
    cast:
      "<defs>" + g("w4", "#2B2A33", "#1B1A22") + g("f4", "#3A3341", "#26212B") +
        g("bd", "#D8CFC4", "#B4A99B") + g("lp", "#F5C242", "#E09A2A") + "</defs>" +
      "<rect width='1400' height='430' fill='url(#w4)'/>" +
      "<rect y='430' width='1400' height='270' fill='url(#f4)'/>" +
      "<rect x='930' y='120' width='340' height='310' rx='12' fill='#12202E'/>" +
      "<rect x='946' y='136' width='308' height='278' rx='8' fill='#1C3A55'/>" +
      "<circle cx='1180' cy='200' r='34' fill='#F2E9C8' opacity='.7'/>" +
      "<rect x='160' y='280' width='130' height='250' rx='18' fill='#4A4152'/>" +
      "<rect x='160' y='370' width='530' height='160' rx='22' fill='url(#bd)'/>" +
      "<rect x='230' y='330' width='160' height='58' rx='18' fill='#F3EEE7'/>" +
      "<rect x='410' y='330' width='160' height='58' rx='18' fill='#F3EEE7'/>" +
      "<rect x='160' y='470' width='530' height='60' rx='14' fill='#8E5F6E' opacity='.75'/>" +
      "<rect x='744' y='468' width='126' height='62' rx='12' fill='#4A4152'/>" +
      "<rect x='796' y='382' width='22' height='86' fill='#6E7A88'/>" +
      "<path d='M758 382h98l-18-74h-62Z' fill='url(#lp)'/>" +
      "<ellipse cx='807' cy='330' rx='140' ry='96' fill='#F5C242' opacity='.18'/>",
    night: "COOL_NIGHT"
  };

  function svgWrap(inner, w, h) {
    return "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='xMidYMid slice' " +
           "xmlns='http://www.w3.org/2000/svg' aria-hidden='true' focusable='false'>" +
           inner + "</svg>";
  }

  var BEAM = ["#E8607A", "#F5C242", "#4FA8C9", "#86C9A8", "#A87ED8", "#EE8B3C"];

  /*  えらんだ写真（取りこみ／さがした）を背景にします */
  function buildPhoto(url) {
    return "<div class='daPhoto' style=\"background-image:url('" +
           String(url || "").replace(/["\\]/g, "") + "')\"></div>";
  }

  function buildCool() {
    /*  写真を入れているときは、そちらを使います */
    if (CFG.coolImage) {
      return "<div class='daPhoto' style=\"background-image:url('" +
             String(CFG.coolImage).replace(/"/g, "") + "')\"></div>";
    }

    if (IND === "night") {
      var beams = "";
      for (var i = 0; i < 12; i++) {
        var a1 = i * Math.PI / 6, a2 = (i + 0.3) * Math.PI / 6;
        beams += "<path d='M700 250 L" + (700 + Math.cos(a1) * 1000).toFixed(0) + " " +
                 (250 + Math.sin(a1) * 1000).toFixed(0) + " L" +
                 (700 + Math.cos(a2) * 1000).toFixed(0) + " " +
                 (250 + Math.sin(a2) * 1000).toFixed(0) + " Z' fill='" +
                 BEAM[i % BEAM.length] + "' opacity='.55'/>";
      }
      return "<div class='daBase'>" + svgWrap(
          "<defs><radialGradient id='nb' cx='.5' cy='.36' r='.7'>" +
          "<stop offset='0' stop-color='#3A2E52'/><stop offset='1' stop-color='#0B0E16'/>" +
          "</radialGradient></defs><rect width='1400' height='700' fill='url(#nb)'/>",
          1400, 700) + "</div>" +
        "<div class='daSpin'>" + svgWrap(beams, 1400, 700) + "</div>" +
        "<div class='daBall'>" + svgWrap(
          "<defs><radialGradient id='mb' cx='.36' cy='.32' r='.75'>" +
          "<stop offset='0' stop-color='#FFFFFF'/><stop offset='.55' stop-color='#AEB9C7'/>" +
          "<stop offset='1' stop-color='#59636F'/></radialGradient></defs>" +
          "<circle cx='700' cy='250' r='92' fill='url(#mb)'/>" +
          "<path d='M608 250h184M700 158v184M636 186l128 128M764 186 636 314' " +
          "stroke='#FFFFFF' stroke-width='5' opacity='.5' fill='none'/>", 1400, 700) + "</div>";
    }
    return "<div class='daBase'>" +
           svgWrap(COOL[IND] || COOL.salon, 1400, 700) + "</div>";
  }

  /* ------------------------------------------------------------ ポップ */

  function rnd(seed) {
    var s = seed;
    return function () { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  }

  function buildPop() {
    var list = POP[IND] || season();
    var r = rnd(20260924);
    var out = [];
    for (var i = 0; i < 24; i++) {
      var nm = list[i % list.length];
      out.push("<span class='daFly' style='left:" + (r() * 100).toFixed(1) + "%;" +
        "animation-duration:" + (26 + r() * 30).toFixed(0) + "s;" +
        "animation-delay:" + (-r() * 40).toFixed(0) + "s;" +
        "--sway:" + (14 + r() * 26).toFixed(0) + "px'>" +
        icon(nm, (30 + r() * 34).toFixed(0)) + "</span>");
    }
    return out.join("");
  }

  /* ------------------------------------------------------------ 出し入れ */

  function clear() {
    var el = document.getElementById("dandoriArt");
    if (el && el.parentNode) el.parentNode.removeChild(el);
    if (document.body) document.body.classList.remove("art-on");
  }

  var LAST = null;

  function set(kind, url) {
    kind = (kind === "pop" || kind === "cool" || kind === "photo") ? kind : "off";
    if (kind === "photo" && !url) kind = "off";
    var tag = kind + "|" + (url || "");
    if (tag === LAST && document.getElementById("dandoriArt")) return;
    LAST = tag;
    clear();
    if (kind === "off" || !document.body) return;

    var d = document.createElement("div");
    d.id = "dandoriArt";
    d.className = "da-" + (kind === "photo" ? "cool" : kind) + " da-" + IND;
    d.setAttribute("aria-hidden", "true");
    d.innerHTML = (kind === "pop") ? buildPop()
                : (kind === "photo") ? buildPhoto(url) : buildCool();
    document.body.insertBefore(d, document.body.firstChild);
    document.body.classList.add("art-on");
  }

  window.DANDORI_ART = { set: set, industry: IND };
})();
