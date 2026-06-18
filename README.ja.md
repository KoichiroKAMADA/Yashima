<p align="right">
  <a href="README.md">English</a> | <strong>日本語</strong>
</p>

# Yashima

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
- `Data`、`Codable`、PNG、JPEG アーティファクト向けの typed codec。
- `CacheKey` と `CacheCodec.identifier` の両方に基づくキャッシュ ID。
- 同じ未生成アーティファクトへ並行リクエストが来たときに生成処理を共有する single-flight。
- UI 上の表示・非表示に合わせて、待ち手がいなくなった生成を止められる cancellation-aware single-flight。
- 破損した保存済みアーティファクトを miss として扱い、再生成できる disposable cache 向けの失敗ポリシー。

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

判断基準はシンプルです。2 回の生成で違う bytes ができる可能性があるなら、`CacheKey` も違うべきです。key が正しければ、キャッシュ値は消えたり再生成されたりしても、要求と違う生成物が返ることはありません。

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

スクロール中のセル、サムネイル、MapKit snapshot、チャート snapshot のように、画面から消えた caller が待つ必要のない用途では、`cancelWhenNoWaiters` を指定します。

```swift
let options = YCache.Options(singleFlightPolicy: .cancelWhenNoWaiters)

let snapshot = try await cache.png(for: key, options: options) {
    try Task.checkCancellation()
    return try await renderSnapshot()
}
```

Yashima は waiter のキャンセルと producer のキャンセルを分けて扱います。1 つの waiter だけがキャンセルされ、他の waiter が残っている場合、producer は残りの caller のために継続します。すべての waiter がキャンセルされた場合、Yashima は producer をキャンセルし、in-flight entry を取り除き、キャンセルされた生成結果を保存しません。

ただし、生成処理の中身は generator 側の責任です。時間のかかる renderer は `Task.checkCancellation()` を確認し、必要であれば snapshotter など下層の処理もキャンセルしてください。

同じ key でも caller ごとに独立して生成させたい場合だけ、`.disabled` を使います。

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

`storageMaximumByteCount` を設定すると、ストレージ entry は least-recently-used の metadata に基づいて trim されます。storage hit は access time を更新します。Yashima は canonical `CacheKey` と codec identity を内部的にハッシュします。

既定の read failure policy では、破損したキャッシュファイルを miss として扱い、呼び出し側が再生成できます。厳密にエラーを扱いたい場合は `readFailurePolicy: .throwError` を指定できます。write では `writeFailurePolicy: .bestEffort` により、ストレージ永続化に失敗しても生成値を返し、メモリのみのキャッシュへフォールバックできます。

## サンプルアプリ

iOS サンプルアプリは [`Examples/YashimaPreviewLab`](Examples/YashimaPreviewLab) にあります。

このサンプルは、3 種類のアプリ内プレビューアーティファクトを生成し、生成された JPEG をキャッシュします。生成、メモリヒット、ストレージヒットの速度差を横並びで確認できます。

- 五色台から屋島までの 9,653 点の GPX 風サイクリングルートを使った MapKit ルートスナップショット。
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

## 採用アプリ

### Tracer

<p align="center">
  <img src="Documentation/Assets/tracer-yashima-scroll.gif" alt="Yashima がキャッシュした地図アーティファクトを Tracer でスクロールしている画面" width="360">
</p>

Yashima は、App Store の位置情報記録アプリ Tracer で、生成アーティファクトのキャッシュ基盤として使われています。Tracer は記録されたアクティビティデータから、多数の地図スナップショット、サマリー、グラフ用データ、一覧プレビューをローカルで生成します。これらはログ一覧のスクロールや、過去の記録を開き直す場面で繰り返し必要になります。

<p align="center">
  <a href="https://apps.apple.com/jp/app/tracer-%E3%81%8B%E3%82%93%E3%81%9F%E3%82%93%E4%BD%8D%E7%BD%AE%E8%A8%98%E9%8C%B2/id1136146951">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/ja-jp?size=250x83" alt="Download on the App Store" height="40">
  </a>
</p>

こうした生成物をスクロール、更新、画面遷移のたびに毎回作り直すと、体験は重くなってしまいます。Yashima は、生成済みの結果をメモリまたはストレージから再利用し、同じアーティファクトへの並行リクエストでは生成処理を共有し、UI 側で待ち手がいなくなった生成はキャンセルできるようにします。

このような実アプリのワークロードこそ、Yashima が想定している用途です。Yashima はデモ専用の画像キャッシュではありません。再生成はできるが、毎回作り直すには高コストなローカル生成物を扱うための、App Store 品質のキャッシュエンジンです。上の録画は、Yashima を組み込んだ Tracer のビルドで、デモデータを使っています。

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

Yashima は公開 Swift Package として準備されています。コントリビュートする前に [CONTRIBUTING.md](CONTRIBUTING.md) と [SECURITY.md](SECURITY.md) を確認してください。

## ライセンス

Yashima は MIT ライセンスで提供されます。詳しくは [LICENSE](LICENSE) を参照してください。
