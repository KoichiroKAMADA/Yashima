<p align="right">
  <a href="FAQ.md">English</a> | <strong>日本語</strong>
</p>

# FAQ

このページでは、Swift アプリに Yashima を入れるべきか判断するときに出やすい質問に答えます。

## Yashima は画像読み込みライブラリですか？

いいえ。Yashima はリモート画像をダウンロードしません。HTTP キャッシュ、URL のプリフェッチ、画像表示用 View も提供しません。

Yashima が扱うのは、アプリがローカルで生成する画像的な成果物です。たとえばサムネイル、プレビュー、チャート、地図スナップショット、レンダリング済みドキュメントページなどです。キャッシュが消えても、アプリ側で再生成できるものが対象です。

リモート画像には [Nuke](https://github.com/kean/Nuke) や [Kingfisher](https://github.com/onevcat/Kingfisher) のような画像パイプラインが適しています。

## NSCache とは何が違いますか？

`NSCache` は、メモリ内の一時オブジェクト再利用に向いたよい標準キャッシュです。Yashima はそれに加えて、ファイルベースの保存層、typed codec、安定した key + codec identity、async get-or-generate API、同時 miss 時の single-flight 生成を提供します。

メモリ内だけで十分なら `NSCache` が自然です。アプリ再起動後、画面遷移後、スクロール中、起動時などにも、重いローカル生成結果を再利用したい場合は Yashima が合います。

## データベースとして使えますか？

いいえ。Yashima は disposable な派生成果物のためのキャッシュです。キャッシュ削除、容量 trim、破損復旧、アプリ側のライフサイクル処理によって entry が消えることがあります。

ユーザーが作成したファイル、原本、ドキュメント、録音・録画、アプリの正本データなど、失われてはいけないものの唯一のコピーを Yashima に置かないでください。SwiftData、Core Data、SQLite、GRDB、アプリ管理のファイル、その他の永続化層を使うべきです。

## CacheKey には何を入れるべきですか？

生成される bytes を変える入力は、すべて key に入れるべきです。サムネイルなら、asset identifier、サイズ、scale、crop mode、appearance、locale、renderer version、content revision token などが候補になります。

ある入力が変わると成果物も変わるなら、その入力を key か codec identity に含めます。Swift の `hashValue` のようなプロセス内だけの値に依存する key は避けてください。

## なぜ codec もキャッシュ identity に含まれるのですか？

同じ `CacheKey` でも、codec が違えば保存される bytes は変わります。PNG サムネイル、JPEG サムネイル、圧縮済みデータは、論理的な成果物 key が同じでも衝突してはいけません。

そのため Yashima は、実効的なキャッシュ identity を次の組み合わせとして扱います。

```text
CacheKey + CacheCodec.identifier
```

## single-flight とは何ですか？

同じ key と codec に対する miss が同時に複数発生したとき、Yashima は 1 つの producer task を実行し、その結果を待ち手全員に共有できます。高速スクロール、同じ画面への再入場、起動時の並行処理などで、同じ重いローカル生成を何度も走らせることを避けられます。

既定の policy は生成を共有します。`YCache.Options.uiLifecycle` を使うと、すべての UI waiter がいなくなった時点で producer をキャンセルできます。

## Yashima の効果はどう測ればよいですか？

導入前後で、重複していたローカル生成を測ります。
同じ論理アーティファクトに対して producer が何回走ったかを数え、導入後に memory hit、storage hit、in-flight work の共有が出ているかを確認します。

役に立つ結果は、「この thumbnail が何度も生成されず、1 回だけ生成されるようになった」という形で表せることがあります。
これは、Yashima が別の cache tool より速いという主張ではありません。

実務的な確認手順は [Adoption Measurement](AdoptionMeasurement.ja.md) にまとめています。

## `YCache.Options.uiLifecycle` はいつ使いますか？

SwiftUI の `List` セル、`LazyVGrid` のタイル、`.task(id:)` で駆動するプレビューなど、現在の UI caller が関心を失ったら生成完了にも意味がなくなる処理に使います。

background 処理、detail 画面、export、最初の caller が消えても producer が完了する価値のある生成では、既定の options を使うほうが自然です。

## ディスク I/O は完全に non-blocking ですか？

いいえ。Yashima は Swift Concurrency-first ですが、内部では Foundation のファイル I/O を使います。API は async workflow、actor、`Sendable` と相性よく設計されていますが、ディスクアクセス自体が完全に non-blocking であるとは主張していません。

## `nil` や失敗は保存されますか？

いいえ。optional generator は `nil` を返せます。その `nil` は現在の waiter には共有されますが、negative cache entry として永続化されません。

throw された error や、キャンセルされた producer の結果も保存されません。

## 質問はどこに出せばよいですか？

導入相談、「この用途に合うか」という質問、設計に関する相談は [GitHub Discussions](https://github.com/KoichiroKAMADA/Yashima/discussions) に投稿してください。

バグ、再現可能な失敗、具体的なドキュメント修正は [GitHub Issues](https://github.com/KoichiroKAMADA/Yashima/issues) が適しています。

隣接ライブラリとの詳しい比較は [Comparison](Comparison.md) を参照してください。
実装パターンは [Recipes](Recipes.ja.md) にまとめています。
