<p align="right">
  <a href="README.md">English</a> | <strong>日本語</strong>
</p>

# Yashima

<p align="center">
  <a href="https://github.com/KoichiroKAMADA/Yashima/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/KoichiroKAMADA/Yashima/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/KoichiroKAMADA/Yashima/releases"><img alt="Release" src="https://img.shields.io/github/v/release/KoichiroKAMADA/Yashima?sort=semver"></a>
  <img alt="Swift 6.1+" src="https://img.shields.io/badge/Swift-6.1%2B-F05138?logo=swift&logoColor=white">
  <img alt="iOS 16+ | macOS 13+" src="https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/KoichiroKAMADA/Yashima"></a>
</p>

<p align="center">
  <img src="Documentation/Assets/yashima-hero.jpg" alt="Yashima" width="840">
</p>

Swift Concurrency を前提にした、ローカル生成アーティファクト向けのキャッシュエンジンです。

画像ダウンローダーではありません。データベースでもありません。

Yashima は、再生成可能だが生成コストの高いローカル結果のために設計されています。たとえば、サムネイル、プレビュー、レンダリング済みチャート、波形、サマリー、その他の派生アーティファクトを扱います。

アプリ側で値を再生成できるが、毎回生成したくはない。Yashima はその用途に対して、小さな公開 API、typed codec、メモリ + ストレージキャッシュ、容量ベースの trim、Swift Concurrency と相性のよい single-flight 生成を提供します。

## Yashima が提供するもの

- 一般的な用途をひとつの async get-or-generate 呼び出しで扱える API。
- L1 メモリキャッシュ + L2 ファイルベースストレージ。
- `Data`、LZFSE 圧縮 `Data`、`Codable`、PNG、JPEG アーティファクト向けの typed codec。
- `CacheKey` と `CacheCodec.identifier` の両方に基づくキャッシュ ID。
- 同じ未生成アーティファクトへ並行リクエストが来たときに生成処理を共有する single-flight。
- UI 上の表示・非表示に合わせて、待ち手がいなくなった生成を止められる cancellation-aware single-flight。
- 破損した保存済みアーティファクトを miss として扱い、再生成できる disposable cache 向けの失敗ポリシー。

## Yashima を使わないほうがよい場合

Yashima は、用途を意図的に狭くしています。アプリが再生成できる disposable なローカル生成物のためのライブラリです。次の用途では、別の道具を選ぶほうが自然です。

- Web 画像のダウンロード、デコード、キャッシュには、[Nuke](https://github.com/kean/Nuke) や [Kingfisher](https://github.com/onevcat/Kingfisher) のような画像パイプラインが適しています。
- 失われてはいけない構造化データには、SwiftData、Core Data、SQLite、GRDB などの永続化層を使ってください。
- ユーザーが作成したファイル、原本、ドキュメント、録画など、消えてはいけないものの唯一のコピーを Yashima に置かないでください。
- メモリ内だけでオブジェクトを一時再利用したい場合は、`NSCache` のほうがシンプルなことがあります。
- 「値が存在しない」という negative cache を永続化したい場合は、アプリ側の状態として表現してください。Yashima は `nil` の生成結果を保存しません。

隣接するキャッシュ・画像読み込みライブラリとの比較は [Comparison](Documentation/Comparison.md) にまとめています。

## インストール

Yashima は Swift Package として配布されます。Xcode では File > Add Package Dependencies からこのリポジトリを追加します。

`Package.swift` で指定する場合、Yashima が 1.0 に到達するまでは `0.5.x` 系を使います。

```swift
dependencies: [
    .package(
        url: "https://github.com/KoichiroKAMADA/Yashima.git",
        .upToNextMinor(from: "0.5.0")
    ),
]
```

そのうえで、ローカル生成アーティファクトを生成・再利用する target に `Yashima` product を追加します。

```swift
.target(
    name: "YourApp",
    dependencies: ["Yashima"]
)
```

## ドキュメントとガイド

- [Swift Package Index](https://swiftpackageindex.com/KoichiroKAMADA/Yashima): パッケージページ。SPI のビルド結果がそろうと、ホストされたドキュメントもここから辿れます。
- [PublicAPI.md](PublicAPI.md): 公開 API の一覧と設計意図。
- [DocC catalog](Sources/Yashima/Yashima.docc): Swift Package Index のドキュメントホスティングに使うソース。
- [Comparison](Documentation/Comparison.md): Yashima を選ぶべき場合と、隣接する道具を選ぶべき場合の比較。
- [FAQ](Documentation/FAQ.ja.md): 導入判断と質問先をすばやく確認するためのFAQ。
- [CHANGELOG.md](CHANGELOG.md): リリース履歴。
- [Benchmarks](Benchmarks): 再現可能なローカル測定用ハーネス。
- [GitHub Discussions](https://github.com/KoichiroKAMADA/Yashima/discussions): 導入相談、適合性の確認、設計に関する質問。

## AI コーディングエージェントに適合性を調べてもらう

Yashima は、狭いが効果の大きい問題を解決するためのライブラリです。対象は、生成にコストがかかるローカル成果物を、再生成せずに再利用することです。

アプリ内で、地図画像、サムネイル、グラフ、集計サマリー、プレビュー、エンコード済みデータなどを、スクロール、画面遷移、起動、再表示のたびに繰り返し生成している場合、Yashima が大きく効く可能性があります。

次のプロンプトを AI コーディングエージェントに貼り付けると、現在のプロジェクトに Yashima が適しているかを調査できます。

```text
私の Swift アプリに Yashima を導入する価値があるか調査してください。

Yashima:
https://github.com/KoichiroKAMADA/Yashima

まず Yashima の README と公開 API を読んでください。そのうえで、このプロジェクト内に、地図画像、サムネイル、グラフ、集計サマリー、プレビュー、エンコード済みデータ、レンダリング済みドキュメント、その他の決定的な生成結果など、ローカルで繰り返し生成している成果物がないか調査してください。

特に、スクロール中、画面遷移時、アプリ起動時、同じ画面の再表示時、過去に見たコンテンツへ戻る場面で繰り返し発生する重い処理を探してください。

次の内容を報告してください。
1. このプロジェクトに Yashima が適しているか。適していない場合は、はっきりそう説明してください。
2. 具体的にどのコードパスで効果がありそうか。
3. どのような CacheKey と Codec を使うべきか。
4. Yashima でキャッシュすべきでないものは何か。
5. 主なリスク。古い cache key、プライバシーに関わるデータ、ディスク使用量、キャンセル挙動を確認してください。
6. バージョン 0.5.0 を前提にした、最小限の Swift Package Manager 導入案。

まだ依存関係の追加やコード編集は行わず、期待できる効果、リスク、最小の安全な導入計画を先に説明してください。
```

## 基本的な使い方

```swift
let cache = YCache(storageDirectory: cacheDirectory)

let thumbnails = cache.using(ImageCodec.jpeg(quality: 0.85))

let thumbnail = try await cache.jpeg(for: key) {
    try await renderThumbnail()
}

let summary: Summary = try await cache.codable(for: key) {
    try await calculateSummary()
}
```

公開 API は意図的に小さくしています。標準の convenience API は codec ベースのコア API の薄いラッパーなので、シンプルな使い方と拡張しやすい使い方が同じキャッシュ意味論を共有します。

`YCache` がルート型です。`Y` は Yashima に由来します。一方で、補助的な語彙は `CacheKey` や `CacheCodec` のように説明的な名前を使います。

画像向け convenience API は、プラットフォーム画像を明示的な PNG または JPEG データとしてキャッシュします。iOS では `UIImage` を受け取り返し、macOS では `NSImage` を受け取り返します。codec を直接使う場合、プラットフォーム画像は小さな Sendable ラッパーを通して保存されます。デフォルトの JPEG 品質は `0.85` です。

codec ベースのコア API も最初から利用できます。

```swift
let cache = YCache(storageDirectory: cacheDirectory)
let reports = cache.using(ReportCodec())

let report = try await reports.value(for: key) {
    try await renderReport()
}

let immediate = try await reports.peek(for: key)
```

## 圧縮 Data アーティファクト

レンダリング済み HTML、JSON、manifest、summary のような大きめのテキスト系生成データでは、`CompressedDataCodec` を選ぶことで LZFSE 圧縮を明示的に使えます。

```swift
let documents = cache.using(CompressedDataCodec())

let htmlData = try await documents.value(for: key) {
    Data(renderedHTML.utf8)
}
```

圧縮は自動ではなく明示的です。`DataCodec` は非圧縮のままで、圧縮された entry は別の codec identity を持ちます。JPEG、PNG、動画データのようにすでに圧縮されている形式では、実測して効果がある場合を除き `CompressedDataCodec` は使わないでください。

## Optional な生成物

生成処理によっては、正当な結果として「返せるアーティファクトがない」ことがあります。たとえば、動画サムネイル生成中に元ファイルが消えた場合や、写真サムネイルとして表示できる画像がないと判断した場合です。

そのような用途では、`optionalValue`、`optionalJPEG`、`optionalPNG` を使います。

```swift
let thumbnail = try await cache.optionalJPEG(
    for: key,
    options: .uiLifecycle
) {
    try await renderThumbnailIfAvailable()
}
```

`nil` は「生成物なし」を表すだけで、negative cache entry ではありません。Yashima は `nil`、`CancellationError`、throw された失敗を保存しません。同じ key への miss が同時に発生した場合でも、optional な生成は single-flight の対象になります。1 つの producer だけが走り、値が返った場合は保存され、`nil` の場合は現在の waiter にだけ共有されて永続化されません。

## CacheKey の設計

キャッシュで最も重要なのは key です。Yashima はストレージ、メモリ、並行生成を扱いやすくしますが、生成物が何に依存しているのかは、アプリ側が正しく表現する必要があります。

小さなアプリでは、key は安定した文字列だけでも始められます。

```swift
let key = CacheKey("thumbnail-\(photoID)", namespace: "thumbnails")
```

本当に単純な対象であれば、この形で十分です。ただ、文字列補間でいくつもの要素をつなぎ始めると、その key が何に依存しているのかをレビューしづらくなります。Yashima では、不透明な長い文字列になる前に、それぞれの要素を名前付きの component として分けられます。`identity` にはキャッシュしたい安定した対象を入れます。`variant(_:_:)` には描画結果を変える入力を入れます。`version(_:_:)` は renderer や schema を変えたときに使います。

```swift
let key = CacheKey(namespace: "summary-maps", identity: summaryID)
    .variant("kind", "route-map")
    .variant("size", "\(pixelWidth)x\(pixelHeight)")
    .variant("appearance", appearance)
    .variant("routeDigest", routeDigest)
    .variant("annotationDigest", annotationDigest)
    .variant("lineWidth", normalizedLineWidth)
    .version("renderer", 2)
```

よい key は、必ずしも長い key ではありません。ただし、完全な key である必要があります。サイズ、scale、appearance、locale、renderer option、元データの revision、そして大きな入力を要約した安定 digest など、生成結果を変え得る入力を含めます。永続的なキャッシュ ID には Swift の `hashValue` や `Hasher` を使わないでください。ルート、チャートのデータセット、レンダリング対象のドキュメントなど、大きな入力を要約したい場合は SHA-256 のような安定 digest を使います。

Yashima の外側で key 由来の文字列が必要な場合は、`key.stableIdentifier` を使えます。これは `CacheKey` 単独から導出される安定した不透明 ID で、補助ファイル名、ログ用ラベル、プロセスをまたぐ重複排除などに使えます。ただし、保存済みキャッシュ entry の ID として扱わないでください。storage entry は `CacheKey` と `CacheCodec.identifier` の組み合わせで識別されます。

判断基準はシンプルです。2 回の生成で違う bytes ができる可能性があるなら、`CacheKey` も違うべきです。key が正しければ、キャッシュ値は消えたり再生成されたりしても、要求と違う生成物が返ることはありません。

動画サムネイルでは、絶対パスや raw file URL を key や public log に入れないでください。アプリ側で安定した identity を用意し、そのうえでサムネイル結果を変え得る入力を variant として含めます。

```swift
let key = CacheKey(namespace: "video-thumbnails", identity: videoIdentity)
    .variant("fileSize", fileSize)
    .variant("createdAt", createdAt.timeIntervalSince1970)
    .variant("modifiedAt", modifiedAt.timeIntervalSince1970)
    .variant("second", thumbnailSecond)
    .variant("pixels", "\(pixelWidth)x\(pixelHeight)")
    .variant("scale", scale)
    .variant("crop", "center-square")
    .version("renderer", 1)
```

`thumbnailSecond` のような素材のタイムライン上の位置は key に含めます。一方で、その時刻が生成物の bytes を本当に変えるのでない限り、リクエスト時刻や生成時刻のような wall-clock time は key に含めないでください。

## YCache インスタンスの共有

一般的な iOS アプリでは、再生成可能な成果物キャッシュ用の `YCache` は、アプリ内で共有される 1 つの長寿命インスタンスとして持つことをおすすめします。小さな cache service、dependency container、actor、または `AppArtifactCache.shared` のような共有 owner に置く形で十分です。

成果物の種類は、別々の `YCache` を作るのではなく、`CacheKey.namespace` で分けます。

```swift
enum AppArtifactCache {
    static let shared = YCache(storageDirectory: cacheDirectory)
}

let thumbnailKey = CacheKey(namespace: "video-thumbnails", identity: videoID)
let durationKey = CacheKey(namespace: "video-durations", identity: videoID)

let thumbnail = try await AppArtifactCache.shared.jpeg(for: thumbnailKey) {
    try await renderThumbnail()
}

let duration: Double = try await AppArtifactCache.shared.codable(for: durationKey) {
    try await loadDuration()
}
```

namespace は、1 つの cache の中で key や削除範囲を分けるための論理的な区分です。namespace ごとに別々の `YCache` を作る必要はありません。複数の `YCache` を作るのは、保存先ディレクトリ、容量ポリシー、ライフサイクル、セキュリティ境界、App Extension との境界、テスト/Preview 用の隔離ストアを明確に分けたい場合に限るのが基本です。複数の cache instance が同じ `storageDirectory` を指す設計になりそうな場合は、1 つの共有 instance にまとめることを優先してください。迷った場合は、1 つの共有 `YCache` と namespace の組み合わせを選んでください。

## デフォルトのキャッシュ容量

`YCache` はデフォルトで、メモリ 64 MiB、ストレージ 128 MiB の容量上限を使います。メモリの entry 件数上限はデフォルトでは設定していません。そのため、小さなサムネイルを大量に扱う用途でも、任意の件数制限で早く追い出されず、容量上限の範囲でメモリを使えます。

このデフォルトは安全寄りに設定しています。Yashima はストレージ hit も多くのローカル生成アーティファクトに対して十分高速なので、まずはデフォルトで使い、実際のワークロードを測ってから必要な分だけメモリを増やすことをおすすめします。メモリを控えめに保つことで、ホストアプリの安定性を守りつつ、より大きな生成結果はファイルベースのストレージ層で受け止められます。

必要な場合は、容量を明示的に調整できます。

```swift
let cache = YCache(
    storageDirectory: cacheDirectory,
    memoryMaximumCost: 96 * 1024 * 1024,
    memoryMaximumEntryCount: 500,
    storageMaximumByteCount: 256 * 1024 * 1024
)
```

無制限にしたい場合は、`nil` を明示的に渡します。

```swift
let cache = YCache(
    storageDirectory: cacheDirectory,
    memoryMaximumCost: nil,
    storageMaximumByteCount: nil
)
```

## キャンセルと UI ライフサイクル

デフォルトの single-flight は互換性を重視した挙動です。同じ key への並行リクエストは 1 つの producer を共有し、1 つの waiter がキャンセルされても producer は継続します。

スクロール中のセル、サムネイル、MapKit snapshot、チャート snapshot のように、画面から消えた caller が待つ必要のない用途では、`uiLifecycle` preset を使います。

```swift
let snapshot = try await cache.png(for: key, options: .uiLifecycle) {
    try Task.checkCancellation()
    return try await renderSnapshot()
}
```

`YCache.Options.uiLifecycle` は、`singleFlightPolicy: .cancelWhenNoWaiters` と `writeFailurePolicy: .bestEffort` を組み合わせた preset です。background 処理、detail 画面、export、生成が完了すること自体に意味がある処理では、既定の `.share` のまま使うことをおすすめします。

`.bestEffort` を含むため、storage write failure は、memory write が有効であれば memory-only の結果へ静かに degrade します。generator 自体の失敗は通常どおり throw されます。

Yashima は waiter のキャンセルと producer のキャンセルを分けて扱います。1 つの waiter だけがキャンセルされ、他の waiter が残っている場合、producer は残りの caller のために継続します。すべての waiter がキャンセルされた場合、Yashima は producer をキャンセルし、in-flight entry を取り除き、キャンセルされた生成結果を保存しません。

ただし、生成処理の中身は generator 側の責任です。時間のかかる renderer は `Task.checkCancellation()` を確認し、必要であれば snapshotter など下層の処理もキャンセルしてください。

同じ key でも caller ごとに独立して生成させたい場合だけ、`.disabled` を使います。

## iOS 向け recipe

Yashima core は AVFoundation、PhotoKit、SwiftUI、アプリ固有のサムネイル生成器を import しません。そうした producer はアプリ側、または別の adapter package の責務です。Yashima は、生成済みの `Data`、`Codable`、PNG、JPEG 値を、予測しやすい key、single-flight、キャンセル意味論でキャッシュすることに集中します。

SwiftUI のセルやグリッドでは、`.task(id:)` で caller task を view lifecycle に結びつけ、`.uiLifecycle` を使い、state に反映する直前に identity を確認します。

```swift
.task(id: videoID) {
    let requestID = videoID
    let image = try? await cache.optionalJPEG(for: key, options: .uiLifecycle) {
        try await renderVideoThumbnail()
    }

    guard !Task.isCancelled, requestID == videoID else { return }
    thumbnailImage = image
}
```

スクロールするセルでは、`.onAppear { Task { ... } }` から非構造化 task を開始する形はおすすめしません。要求元の view よりも task が長生きしやすく、古いセルへ別の生成結果を反映してしまう事故を招きやすくなります。

AVFoundation のサムネイルでは、対応 OS では async な `AVAssetImageGenerator.image(at:)` を優先し、task cancellation を producer に接続します。

```swift
let generator = AVAssetImageGenerator(asset: asset)
let time = CMTime(seconds: thumbnailSecond, preferredTimescale: 600)

let cgImage = try await withTaskCancellationHandler {
    let result = try await generator.image(at: time)
    return result.image
} onCancel: {
    generator.cancelAllCGImageGeneration()
}
```

`copyCGImage(at:actualTime:)` を使う場合、その API は同期処理です。呼び出し前後で task cancellation を確認することには意味がありますが、同期生成が始まった後に即座に中断できるとは限りません。

PhotoKit のサムネイルでは、key を一時的な `UIImage` ではなく、`PHAsset` の identity と要求する表現に結びつけます。

```swift
let key = CacheKey(namespace: "photo-thumbnails", identity: asset.localIdentifier)
    .variant("pixels", "\(pixelWidth)x\(pixelHeight)")
    .variant("contentMode", "aspectFill")
    .variant("deliveryMode", "highQuality")
    .version("renderer", 1)
```

`PHImageManager` は request options によって複数回 result を返すことがあります。key に対応する最終的な表現だけをキャッシュするか、品質段階を key に含めてください。周囲の task がキャンセルされた場合は、`requestImage` が返す `PHImageRequestID` を保持し、`cancelImageRequest(_:)` に渡して Photos 側の request もキャンセルします。UI lifecycle に結びつく用途では、開始後にキャンセルできない同期 PhotoKit request は避けることをおすすめします。

動画の duration のような小さな派生値は、画像とは別 namespace で `Codable` として扱います。

```swift
let key = CacheKey(namespace: "video-durations", identity: videoIdentity)
    .variant("durationSource", "asset-metadata")
    .version("schema", 1)

let duration: Double = try await cache.codable(for: key) {
    try await loadDuration()
}
```

サムネイル画像と小さなメタデータは、`video-thumbnails`、`photo-thumbnails`、`video-durations`、`video-metadata` のように namespace を分けておくと、キャッシュクリアや将来の容量調整を理解しやすくなります。これらの namespace は、通常、同じ共有 `YCache` instance の中で使います。

## キャッシュのライフサイクル

Yashima は再生成可能な値をキャッシュするため、ライフサイクル操作は明示的で小さく保っています。

```swift
let metadata = try await cache.metadata(for: key, codec: ImageCodec.jpeg())
let isCached = try await cache.contains(for: key, codec: ImageCodec.jpeg())

try await cache.remove(for: key, codec: ImageCodec.jpeg())
try await cache.removeAll(in: "thumbnails")

let usage = try await cache.storageUsage()
try await cache.trimStorageIfNeeded()
```

`storageMaximumByteCount` を設定すると、ストレージ entry は least-recently-used の metadata に基づいて trim されます。storage hit は access time を更新します。Yashima は canonical `CacheKey` と codec identity を内部的にハッシュします。`CacheKey.stableIdentifier` は、キャッシュ外で安定文字列が必要な呼び出し側のために、そのうち key 側だけを公開する API です。

既定の read failure policy では、破損したキャッシュファイルを miss として扱い、呼び出し側が再生成できます。厳密にエラーを扱いたい場合は `readFailurePolicy: .throwError` を指定できます。write では `writeFailurePolicy: .bestEffort` により、ストレージ永続化に失敗しても生成値を返し、メモリのみのキャッシュへフォールバックできます。

## サンプルアプリ

iOS サンプルアプリは [`Examples/YashimaPreviewLab`](Examples/YashimaPreviewLab) にあります。

このサンプルは、3 種類のアプリ内プレビューアーティファクトを生成し、生成された JPEG をキャッシュします。生成、メモリヒット、ストレージヒットの速度差を横並びで確認できます。

- 五色台・屋島周辺の 9,426 点のサニタイズ済み座標ルートを使った MapKit ルートスナップショット。
- Swift Charts によるパフォーマンススナップショット。
- `ImageRenderer` でレンダリングした SwiftUI のチケット風マニフェスト。

このサンプルは、Yashima が重いアプリ内生成物をキャッシュするためのライブラリであることを示すためのものです。地図専用エンジンでも、Web 画像ダウンローダーでもありません。

## 負荷テスト

任意で実行できるローカル負荷テストを [`StressTests`](StressTests) に用意しています。通常の `swift test` とは分離しているため、日常的な検証は速く保ちつつ、大きな変更時には非同期処理とファイルベースストレージをより重い条件で確認できます。

この stress runner は合成データだけを使い、次の観点で正しさを検証します。

- 多数の task が同じ未生成アーティファクトを要求する single-flight burst。
- `Data`、`Codable`、PNG、JPEG を混在させた並行生成。
- refresh、lookup、metadata、remove、namespace remove を混ぜたライフサイクル操作。
- storage quota pressure、容量ぴったりでの置き換え、上限超過 entry の cleanup。
- デフォルトのメモリ上限下で、古いメモリエントリがストレージへフォールバックする挙動。
- 破損からの回復と、cancellation-aware single-flight の安定性。

```sh
swift run --package-path StressTests YashimaStressRunner --profile smoke
```

大きな挙動変更では、より広いローカル profile も実行できます。

```sh
swift run --package-path StressTests YashimaStressRunner --profile standard
```

stress runner はベンチマーク結果を主張するためのものではありません。小さな unit test だけでは覆いにくい、並行性、ディスク保存、trim、破損回復、再生成の正しさを退行検出するための仕組みです。

## ベンチマークハーネス

[`Benchmarks`](Benchmarks) には、小さなローカルベンチマークハーネスがあります。これは正しさを検証する stress runner とは別のもので、性能主張を公開する前に再現可能な測定を行うための入口です。

```sh
swift run --package-path Benchmarks YashimaBenchmarks --iterations 200
```

ベンチマーク値は、ハードウェア、OS バージョン、ストレージ状態、payload の形に強く左右されます。ローカル出力は測定材料であり、普遍的な性能主張として扱わないでください。

## 採用アプリ

### Tracer かんたん位置記録

<p align="center">
  <img src="Documentation/Assets/tracer-yashima-scroll.gif" alt="Yashima がキャッシュした地図アーティファクトを Tracer でスクロールしている画面" width="360">
</p>

Yashima は、App Store の位置情報記録アプリ「Tracer かんたん位置記録」で、生成アーティファクトのキャッシュ基盤として使われています。Tracer は記録されたアクティビティデータから、多数の地図スナップショット、サマリー、グラフ用データ、一覧プレビューをローカルで生成します。これらはログ一覧のスクロールや、過去の記録を開き直す場面で繰り返し必要になります。

<p align="center">
  <a href="https://apps.apple.com/jp/app/tracer-%E3%81%8B%E3%82%93%E3%81%9F%E3%82%93%E4%BD%8D%E7%BD%AE%E8%A8%98%E9%8C%B2/id1136146951">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/ja-jp?size=250x83" alt="Download on the App Store" height="40">
  </a>
</p>

こうした生成物をスクロール、更新、画面遷移のたびに毎回作り直すと、体験は重くなってしまいます。Yashima は、生成済みの結果をメモリまたはストレージから再利用し、同じアーティファクトへの並行リクエストでは生成処理を共有し、UI 側で待ち手がいなくなった生成はキャンセルできるようにします。

このような実アプリのワークロードこそ、Yashima が想定している用途です。Yashima はデモ専用の画像キャッシュではありません。再生成はできるが、毎回作り直すには高コストなローカル生成物を扱うための、App Store 品質のキャッシュエンジンです。上の録画は、Yashima を組み込んだ Tracer のビルドで、デモデータを使っています。

### 複数アプリでの実運用

「Tracer かんたん位置記録」は最も詳しく紹介している公開事例ですが、Yashima の実運用は Tracer だけに限られません。プロジェクト作者は、出荷済みの複数の個人開発 App Store アプリでも Yashima を使っています。これらのアプリで扱っている実際の生成アーティファクトが、Yashima の設計を支えています。

- [無限時計 - 見やすい時計](https://apps.apple.com/jp/app/%E7%84%A1%E9%99%90%E6%99%82%E8%A8%88-%E8%A6%8B%E3%82%84%E3%81%99%E3%81%84%E6%99%82%E8%A8%88/id1064833509): 大きく見やすい表示と豊富なカスタマイズを備えた、作者報告で 200 万ダウンロード超の時計アプリです。Yashima は背景画像サムネイル、色/ぼかしフィルタープレビュー、背景動画サムネイル、動画時間メタデータの再利用に使われています。
- [無限サウンド](https://apps.apple.com/jp/app/%E7%84%A1%E9%99%90%E3%82%B5%E3%82%A6%E3%83%B3%E3%83%89/id6748948810): 集中、睡眠、ノイズマスキングなどに使える環境サウンド再生アプリです。Yashima はグリッド、プレイリスト、フルスクリーン再生で使うサウンドアートワークのダウンサンプリング済み JPEG 派生画像をキャッシュしています。
- [無限プレーヤー 連続メディア再生](https://apps.apple.com/jp/app/%E7%84%A1%E9%99%90%E3%83%97%E3%83%AC%E3%83%BC%E3%83%A4%E3%83%BC-%E9%80%A3%E7%B6%9A%E3%83%A1%E3%83%87%E3%82%A3%E3%82%A2%E5%86%8D%E7%94%9F/id1265142965): メディアを流れるように連続再生する軽量プレーヤーです。Yashima はファイル、Photo Library、ブックマークのサムネイルを、一覧表示や再生画面で再利用するために使われています。
- [無限カメラ 超長時間ビデオを録画](https://apps.apple.com/jp/app/%E7%84%A1%E9%99%90%E3%82%AB%E3%83%A1%E3%83%A9-%E8%B6%85%E9%95%B7%E6%99%82%E9%96%93%E3%83%93%E3%83%87%E3%82%AA%E3%82%92%E9%8C%B2%E7%94%BB/id1142214008): 長時間のビデオ録画と保存を重視したカメラアプリです。Yashima はアプリ内ストレージで記録・管理する動画のサムネイルと動画時間メタデータをキャッシュしています。
- [最速起動 ゼロカメラ](https://apps.apple.com/jp/app/%E6%9C%80%E9%80%9F%E8%B5%B7%E5%8B%95-%E3%82%BC%E3%83%AD%E3%82%AB%E3%83%A1%E3%83%A9/id1449814538): すばやく起動してすぐ録画できることを重視したビデオカメラアプリです。Yashima はアプリ内ストレージ動画のサムネイルと動画時間メタデータをキャッシュしています。
- [ZeroMD](https://apps.apple.com/jp/app/zeromd/id6770927023): Mac で Markdown ファイルをすばやく読むための軽量 Markdown ビューアです。Yashima は Markdown の first-paint 用レンダリング成果物をキャッシュし、再表示時に生成済み HTML とナビゲーション payload を再利用します。

これらの実運用では、画像のダウンサンプリング、フィルタープレビュー生成、AVFoundation による動画サムネイル抽出、小さなメタデータの保存、圧縮された文書レンダリング成果物など、複数種類のワークロードで Yashima が使われています。

### あなたのアプリも紹介できます

Yashima を利用していて、App Store で公開されているアプリがあれば、ぜひお知らせください。このセクションで採用事例として紹介させていただきます。

## 状態

キャッシュ ID、メモリストア、ストレージストア、コアエンジン、codec ベースの `YCache` 公開 API、標準 codec、README で紹介している convenience helper は実装済みで、Swift Testing によるテストも用意されています。さらに、並行性、キャンセル、ストレージ境界を合成ワークロードで検証する stress runner も用意しています。

## 設計メモ

- Swift Concurrency-first の公開 API。
- L1 メモリキャッシュ + L2 ストレージキャッシュ。
- get-or-generate を主な利用モデルにする。
- typed codec による data-first な保存。
- 実効的なキャッシュエントリ ID は `CacheKey` + codec identifier。
- キャッシュの意味論: 値は消えることがあります。ただし、キャッシュから返る値は、必ず key、codec、metadata と一致している必要があります。
- Swift Concurrency-first は、ディスク I/O が完全に non-blocking になるという意味ではありません。公開 API を async かつ actor ベースに保ちつつ、内部では Foundation のファイル I/O を使います。

## 要件

- Swift 6.1 以降
- iOS 16+
- macOS 13+

## コントリビュート

Yashima は公開 Swift Package です。コントリビュートする前に [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md)、[PublicAPI.md](PublicAPI.md)、[CHANGELOG.md](CHANGELOG.md) を確認してください。

## ライセンス

Yashima は MIT ライセンスで提供されます。詳しくは [LICENSE](LICENSE) を参照してください。
