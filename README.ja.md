<p align="right">
  <a href="README.md">English</a> | <strong>日本語</strong>
</p>

# Yashima

<p align="center">
  <img src="Documentation/Assets/yashima-hero.png" alt="Yashima" width="840">
</p>

Swift Concurrency を前提にした、ローカル生成アーティファクト向けの get-or-generate キャッシュです。

画像ダウンローダーではありません。データベースでもありません。

Yashima は、再生成可能だが生成コストの高いローカル結果のために設計されています。たとえば、サムネイル、プレビュー、レンダリング済みチャート、波形、サマリー、その他の派生アーティファクトを扱います。

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

公開 API はシンプルに保ちます。内部的には、標準の convenience API も codec ベース API の薄いラッパーです。

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

## サンプルアプリ

iOS サンプルアプリは [`Examples/YashimaPreviewLab`](Examples/YashimaPreviewLab) にあります。

このサンプルは、3 種類のアプリ内プレビューアーティファクトを生成し、生成された JPEG をキャッシュします。生成、メモリヒット、ストレージヒットの速度差を横並びで確認できます。

- 五色台・屋島周辺の 9,426 点のサニタイズ済み座標ルートを使った MapKit ルートスナップショット。
- Swift Charts によるパフォーマンススナップショット。
- `ImageRenderer` でレンダリングした SwiftUI のチケット風マニフェスト。

このサンプルは、Yashima が重いアプリ内生成物をキャッシュするためのライブラリであることを示すためのものです。地図専用エンジンでも、Web 画像ダウンローダーでもありません。

## 状態

キャッシュ ID、メモリストア、ストレージストア、コアエンジン、codec ベースの `YCache` 公開 API、標準 codec、README で紹介している convenience helper は実装済みで、Swift Testing によるテストも用意されています。

## 設計メモ

- Swift Concurrency-first の公開 API。
- L1 メモリキャッシュ + L2 ストレージキャッシュ。
- get-or-generate を主な利用モデルにする。
- typed codec による data-first な保存。
- 実効的なキャッシュエントリ ID は `CacheKey` + codec identifier。
- キャッシュの意味論: 値は消えることがあります。ただし、キャッシュから返る値は、必ず key、codec、metadata と一致している必要があります。

## 要件

- Swift 6.1 以降
- iOS 16+
- macOS 13+

## コントリビュート

Yashima は公開 Swift Package として準備されています。コントリビュートする前に [CONTRIBUTING.md](CONTRIBUTING.md) と [SECURITY.md](SECURITY.md) を確認してください。

## ライセンス

Yashima は MIT ライセンスで提供されます。詳しくは [LICENSE](LICENSE) を参照してください。
