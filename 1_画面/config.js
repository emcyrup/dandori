// ============================================================================
//  だんどりシリーズ / 接続設定
//  config.js
//
//  置き場所： サイトのルート（index.html と同じ階層）
//  ここだけ書き換えれば、別のSupabaseプロジェクトにも向けられます。
//  anon キーはブラウザに置く前提の公開キーです（service_role キーは絶対に置かないこと）。
// ============================================================================

window.DANDORI_CONFIG = {
  supabaseUrl: "https://mfsvfolyrkrpribnwvcl.supabase.co",
  supabaseAnonKey:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mc3Zmb2x5cmtycHJpYm53dmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNjI0ODksImV4cCI6MjEwNTczODQ4OX0.bzLO2t3P-N8BXGWLFhe8aPRrjVByfOHtx83z8vMFveQ",

  // お店のLINE公式アカウント（スタッフさんの友だち追加用）
  //   lineAddUrl  … 友だち追加のリンク（LINE Official Account Manager で出ます）
  //   lineQrImage … 同じアカウントのQRコード画像。サイトに一緒に置いてください
  //   どちらも空にすると、「LINEの登録」タブにQRは出ません。
  lineAddUrl: "https://lin.ee/VGMVFXP",
  lineQrImage: "line_qr.png",

  // 業種。背景のかざり（ポップ／クール）の絵を、これで選びます。
  //   night / cast / food / salon / pet
  industry: "night",

  // 「クール」の背景に、写真を使いたいときのアドレス。
  //   例： "art/salon.jpg"（サイトと同じ場所に置いてください）
  //   空のままなら、ツールが描いた情景を使います。
  coolImage: "",



  // 画面の見た目（着せ替え）: "dark" | "standard" | "large" | "simple"
  // ナイトはカウンター内で使うので、既定は濃色にしてあります。
  theme: "dark",

  // ホール画面を自動で更新する間隔（秒）。0で自動更新オフ。
  refreshSeconds: 20
};
