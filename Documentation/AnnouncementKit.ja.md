<p align="right">
  <a href="AnnouncementKit.md">English</a> | <strong>日本語</strong>
</p>

# Announcement Kit

このページは、Yashima をリリース後、Swift Package Index 反映後、またはドキュメント更新後に紹介するときの公開安全な文面素材です。

大きな告知を行う前に、次を確認してください。

- 最新の GitHub Release が公開済みであること。
- 告知するリリースまたは現在のデフォルトブランチで CI が成功していること。
- インストール例、動作要件、公開リンクが現在のリリースと一致していること。
- ベンチマーク数値は、引用する環境で現在の `Benchmarks` コマンドを実行して得たものであること。

Swift Package Index の互換性結果は有用な補強材料ですが、告知の必須条件ではありません。
実測結果が表示されたら、Swift versions バッジを掲載し、ホスト版 DocC へ直接リンクします。
対応範囲は `Package.swift` の宣言を正本とし、SPI で追加の destination がビルドに成功しても、それだけで Yashima の正式対応プラットフォームを広げません。
結果が再び `pending` になった場合は互換性バッジを外し、SPI が互換性を確認済みだとは主張しません。

## 1段落ピッチ

Yashima は、Swift Concurrency を前提にした、ローカル生成アーティファクト向けのキャッシュエンジンです。対象は、アプリ側で再生成できるが、スクロール、画面遷移、起動、再表示のたびに作り直したくない値です。たとえば、サムネイル、プレビュー、Map snapshot、Chart snapshot、レンダリング済みドキュメント payload、サマリー、波形、小さな派生メタデータなどを扱います。よく使う経路はひとつの async get-or-generate 呼び出しで書けますが、codec identity、メモリとストレージの2層キャッシュ、single-flight 生成、容量 trim、UI lifecycle cancellation も保ちます。

## 短いピッチ

Yashima は、Swift アプリ内で生成されるローカルアーティファクトをキャッシュします。リモート画像でも、データベースレコードでもなく、アプリが安全に再生成できる高コストな結果のためのライブラリです。小さな async API、typed codec、メモリ + ディスク再利用、single-flight 生成、SwiftUI と相性のよいキャンセル制御を提供します。

## 公開時の主張範囲

言ってよいこと:

- Yashima 1.0.0 は、現在の generated artifact cache surface に対する最初の stable API release です。
- Yashima は disposable なローカル生成物向けであり、ユーザーの原本データ向けではありません。
- Yashima は URL 画像ダウンローダーではなく、データベースでもありません。
- リポジトリには DocC source、examples、recipes、comparison guide、adoption measurement guide、FAQ、local benchmark harness があります。
- Swift Package Index は実測 Swift 互換性を公開し、バージョン別 DocC をホストしています。告知では現在のバッジに表示される Swift バージョンだけを述べ、正式なプラットフォーム範囲は iOS 16+ / macOS 13+ のままとします。
- maintainer は、出荷済み App Store アプリ群で Yashima を利用していると報告しています。アプリ単位の利用状況やダウンロード数は、公開ソースを併記できる場合を除き maintainer-reported として扱ってください。

言わないこと:

- Yashima により disk I/O が non-blocking になる。
- benchmark の数値だけで Yashima の価値を説明できる。
- Yashima は Nuke、Kingfisher、SwiftData、Core Data、SQLite、GRDB の drop-in replacement である。
- benchmark の数値だけで、一般的な性能を証明できる。

## 定量サマリーのテンプレート

現在の確認済み値を入れた後でのみ使ってください。

```text
Yashima 1.0.0 は、ローカル生成アーティファクトをキャッシュするための stable Swift package です。
maintainer-reported では、すでに [N] 本の出荷済み App Store アプリで利用され、[workload examples] のような用途を扱っています。
[measured app workload] では、app-side counter が Yashima 導入前に [before generator runs] 回の generator run を示し、導入後は [after generator runs / memory hits / storage hits] になりました。
これは、その workload で避けられたローカル再生成を説明する数値であり、一般的な性能主張ではありません。
```

## コメント返信の種

### Kingfisher や Nuke と何が違いますか？

Kingfisher と Nuke は、リモート画像の読み込み、デコード、キャッシュのための優れた image pipeline です。Yashima は、アプリ自身がローカルで生成する値に焦点を当てています。たとえば、サムネイル、レンダリング済みプレビュー、chart snapshot、document payload などです。

### Yashima が提供する速さとは何ですか？

Yashima が提供する速さは、多くのアプリで繰り返し発生しているローカル生成物の再生成を止めることです。
AI エージェントや開発者が安心して導入できる package-shaped なローカルキャッシュとして、その無駄を減らせることに価値があります。

### データベースでは駄目ですか？

失われてはいけない構造化データにはデータベースを使ってください。Yashima は、削除されても再生成できる派生値のためのものです。

### `uiLifecycle` は何のためにありますか？

スクロール中のセルやグリッドのタイルでは、view が消えると、その生成結果を誰も必要としなくなることがあります。`YCache.Options.uiLifecycle` は、待ち手が全員いなくなったときのキャンセル方針を cache request の一部として扱えるようにします。

## リンク集

- GitHub: https://github.com/KoichiroKAMADA/Yashima
- Release: https://github.com/KoichiroKAMADA/Yashima/releases
- Swift Package Index: https://swiftpackageindex.com/KoichiroKAMADA/Yashima
- Hosted DocC: https://swiftpackageindex.com/KoichiroKAMADA/Yashima/1.0.0/documentation/yashima
- Build Results: https://swiftpackageindex.com/KoichiroKAMADA/Yashima/builds
- Discussions: https://github.com/KoichiroKAMADA/Yashima/discussions
- Recipes: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/Recipes.md
- Adoption Measurement: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/AdoptionMeasurement.md
- FAQ: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/FAQ.md
- Benchmarks: https://github.com/KoichiroKAMADA/Yashima/tree/main/Benchmarks

## 告知用メディア

- `Documentation/Assets/yashima-hero.jpg`: リポジトリとリンクプレビュー用の画像。
- `Documentation/Assets/tracer-yashima-scroll.mp4`: 合成デモデータを使い、Tracer で Yashima が生成物を再利用する様子を収録した短い H.264 動画。
- `Documentation/Assets/tracer-yashima-scroll.gif`: 同じデモの README 用 GIF。
