<p align="right">
  <a href="README.md">English</a> | <strong>日本語</strong>
</p>

# Yashima

<p align="center">
  <img src="Documentation/Assets/yashima-hero.png" alt="Yashima" width="840">
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

`storageMaximumByteCount` を設定すると、ストレージ entry は least-recently-used の metadata に基づいて trim されます。storage hit は access time を更新します。生成物の同一性を決める入力は `CacheKey.variant(_:_:)` と `CacheKey.version(_:_:)` で表現し、Yashima は canonical key と codec identity を内部的にハッシュします。

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
- 破損からの回復と、キャンセルが混ざる状況での安定性。

```sh
swift run --package-path StressTests YashimaStressRunner --profile smoke
```

大きな挙動変更では、より広いローカル profile も実行できます。

```sh
swift run --package-path StressTests YashimaStressRunner --profile standard
```

stress runner はベンチマーク結果を主張するためのものではありません。小さな unit test だけでは覆いにくい、並行性、ディスク保存、trim、破損回復、再生成の正しさを退行検出するための仕組みです。

## 状態

キャッシュ ID、メモリストア、ストレージストア、コアエンジン、codec ベースの `YCache` 公開 API、標準 codec、README で紹介している convenience helper は実装済みで、Swift Testing によるテストも用意されています。さらに、並行性とストレージ境界を合成ワークロードで検証する stress runner も用意しています。

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
