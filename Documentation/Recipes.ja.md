<p align="right">
  <a href="Recipes.md">English</a> | <strong>日本語</strong>
</p>

# レシピ

このページでは、Swift アプリがローカル生成アーティファクトを繰り返し作る場面で使える Yashima の実用パターンを示します。

例はすべて合成コードです。
実アプリのワークロードを踏まえていますが、アプリ固有のモデル、private path、log、user data は含めていません。

## レシピの選び方

| ワークロード | Codec | Options | Key に含める入力 |
|---|---|---|---|
| スクロール中のサムネイルとプレビュー | `ImageCodec.jpeg` または `ImageCodec.png` | `.uiLifecycle` | source identity、source revision、size、scale、crop、renderer version |
| 小さな派生メタデータ | `CodableCodec` | `.default` | source identity、source revision、metadata schema または reader version |
| レンダリング済みドキュメント | `CompressedDataCodec` または独自の圧縮 codec | 実測した cost つきの `.default` | document identity、content revision、renderer version、locale、appearance |
| 検索用アーティファクト | 独自 codec または `CodableCodec` | cache-only read と明示的な store | candidate identity、source revision、normalizer version、artifact schema |
| フィルタや派生バリアントのプレビュー | `ImageCodec.jpeg` または `ImageCodec.png` | `.uiLifecycle` | source identity、base transform、candidate transform、output size、renderer version |

## 共有キャッシュを持つ

多くのアプリでは、生成済みアーティファクト用の長寿命な `YCache` を 1 つ持つところから始めるのが自然です。
成果物の種類は、その cache の中で namespace によって分けます。

```swift
import Foundation
import Yashima

enum AppArtifactCache {
    static let shared = YCache(
        storageDirectory: FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("GeneratedArtifacts", isDirectory: true),
        memoryMaximumCost: 96 * 1024 * 1024,
        memoryMaximumEntryCount: nil,
        storageMaximumByteCount: 512 * 1024 * 1024
    )
}
```

別々の `YCache` を作るのは、保存先ディレクトリ、容量、ライフサイクル、セキュリティ境界を意図的に分けたい場合です。
namespace が違うという理由だけで、同じディレクトリを指す cache instance を複数作る設計は避けてください。

## スクロール中のサムネイル

このパターンは、`List`、`LazyVGrid`、collection 形式の UI で、セルがローカルサムネイルを要求してすぐ消える場面に向いています。

```swift
import UIKit
import Yashima

func thumbnail(
    assetID: String,
    sourceRevision: String,
    pointSize: CGSize,
    scale: CGFloat
) async throws -> UIImage? {
    let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

    let key = CacheKey(namespace: "media-thumbnails", identity: assetID)
        .variant("sourceRevision", sourceRevision)
        .variant("pixels", "\(Int(pixelSize.width))x\(Int(pixelSize.height))")
        .variant("scale", scale)
        .variant("crop", "center-square")
        .version("renderer", 1)

    return try await AppArtifactCache.shared.optionalJPEG(
        for: key,
        quality: 0.85,
        options: .uiLifecycle
    ) {
        try Task.checkCancellation()
        return try await renderThumbnail(assetID: assetID, pointSize: pointSize, scale: scale)
    }
}
```

SwiftUI では、`.task(id:)` で request を view lifecycle に結びつけます。
結果を state に反映する直前に、その cell がまだ同じ identity を表しているか確認します。

```swift
.task(id: assetID) {
    let requestID = assetID
    let image = try? await thumbnail(
        assetID: assetID,
        sourceRevision: sourceRevision,
        pointSize: CGSize(width: 96, height: 96),
        scale: displayScale
    )

    guard !Task.isCancelled, requestID == assetID else { return }
    thumbnailImage = image
}
```

この用途では、多くの場合 `.uiLifecycle` が合います。
表示中の caller がすべて消えたら、Yashima は共有 producer をキャンセルできます。
画面から消えた cell のために生成を最後まで走らせる必要がないからです。

## 動画の長さや小さなメタデータ

小さな派生メタデータには `CodableCodec` を使えます。
画像用 namespace とは分けておくと、あとから確認、削除、容量調整をしやすくなります。

```swift
import AVFoundation
import Yashima

func videoDuration(
    videoID: String,
    fileSize: Int,
    modifiedAt: Date
) async throws -> TimeInterval {
    let key = CacheKey(namespace: "video-durations", identity: videoID)
        .variant("fileSize", fileSize)
        .variant("modifiedAt", Int64(modifiedAt.timeIntervalSince1970 * 1_000_000))
        .version("reader", 1)

    return try await AppArtifactCache.shared.codable(for: key) {
        try await loadDurationFromAsset(videoID: videoID)
    }
}
```

このパターンは、ローカルメディアやアプリ内ファイルから派生する duration、dimensions、page count、抽出済み title、小さな manifest に向いています。
ただし、その値が正本になるわけではありません。
cache clear 後も必ず残す必要がある値は、アプリ側の永続化層に保存してください。

## レンダリング済みドキュメント

レンダリング済みドキュメントは、サムネイルより大きく、bytes として扱うほうが自然なことがあります。
HTML、JSON、manifest のようなテキスト系出力では、まず `CompressedDataCodec` を検討します。

```swift
import Foundation
import Yashima

func renderedHTML(
    documentID: String,
    contentRevision: String,
    appearance: String,
    localeIdentifier: String
) async throws -> Data {
    let key = CacheKey(namespace: "rendered-documents", identity: documentID)
        .variant("contentRevision", contentRevision)
        .variant("appearance", appearance)
        .variant("locale", localeIdentifier)
        .version("renderer", 4)

    return try await AppArtifactCache.shared.value(
        for: key,
        codec: CompressedDataCodec(),
        options: YCache.Options(
            cost: .bytes(256 * 1024),
            writeFailurePolicy: .bestEffort
        )
    ) {
        let html = try await renderDocumentHTML(documentID: documentID)
        return Data(html.utf8)
    }
}
```

複数の構造化データをまとめて保存したい場合は、version つき identifier を持つ独自 codec を定義します。
codec identifier は保存済み entry の identity に含まれるため、format を変えても古い bytes と衝突しません。

```swift
import Foundation
import Yashima

struct FirstPaintArtifact: Codable, Sendable {
    var html: Data
    var title: String
    var headings: [String]
}

struct FirstPaintArtifactCodec: CacheCodec {
    let identifier = "first-paint-artifact-plist-lzfse-v1"

    func encode(_ value: FirstPaintArtifact) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let propertyList = try encoder.encode(value)
        return try (propertyList as NSData).compressed(using: .lzfse) as Data
    }

    func decode(_ data: Data) throws -> FirstPaintArtifact {
        let propertyList = try (data as NSData).decompressed(using: .lzfse) as Data
        return try PropertyListDecoder().decode(FirstPaintArtifact.self, from: propertyList)
    }
}
```

この形は、first-paint payload、レンダリング済み preview、正規化済み document summary などの派生成果物に使えます。
ユーザーが作成したドキュメントそのものの唯一のコピーを Yashima に置いてはいけません。

## 検索用アーティファクト

検索では、index 全体を 1 つの cache entry にするより、candidate document ごとの派生成果物を cache するほうが扱いやすいことが多いです。
現在の candidate 集合をどう組み合わせるかは、検索エンジン側が判断します。

```swift
import Yashima

struct SearchArtifact: Codable, Sendable {
    var normalizedLines: [String]
    var tokenCount: Int
    static let schemaVersion = 1
}

struct SearchCandidate: Sendable {
    var documentID: String
    var sourceRevision: String
}

func searchArtifactKey(
    candidate: SearchCandidate,
    normalizerVersion: String
) -> CacheKey {
    CacheKey(namespace: "search-artifacts", identity: candidate.documentID)
        .variant("sourceRevision", candidate.sourceRevision)
        .version("normalizer", normalizerVersion)
        .version("schema", SearchArtifact.schemaVersion)
}
```

既に準備済みのアーティファクトがあるかだけを知りたい場合は、`cacheOnly` で読みます。
検索 pipeline が有効なアーティファクトを作った後で、明示的に store します。

```swift
let lookupOptions = YCache.Options(
    lookupPolicy: .cacheOnly,
    readFailurePolicy: .throwError,
    writeFailurePolicy: .throwError,
    singleFlightPolicy: .disabled
)

let storeOptions = YCache.Options(
    cost: .bytes(estimatedMemoryCost),
    writeFailurePolicy: .throwError,
    singleFlightPolicy: .disabled
)

let key = searchArtifactKey(candidate: candidate, normalizerVersion: "v3")
let codec = CodableCodec<SearchArtifact>(format: .propertyList)

let cached = try? await AppArtifactCache.shared.value(
    for: key,
    codec: codec,
    options: lookupOptions
) {
    throw YCache.Error.cacheMiss
}

if cached == nil {
    let artifact = try await buildSearchArtifact(candidate)
    try await AppArtifactCache.shared.store(
        artifact,
        for: key,
        codec: codec,
        options: storeOptions
    )
}
```

この設計では、Yashima は disposable artifact cache の役割に留まります。
現在の document list、permission、query state、正本の document content は、アプリ側の責務です。

## フィルタや派生バリアントのプレビュー

画像の複数バリアントを UI 上でプレビューする場合、元画像と候補 transform の両方を key に入れます。

```swift
func filterPreviewKey(
    imageID: String,
    sourceDigest: String,
    pixelSize: String,
    baseFilter: String?,
    candidateFilter: String
) -> CacheKey {
    CacheKey(namespace: "filter-previews", identity: imageID)
        .variant("sourceDigest", sourceDigest)
        .variant("pixels", pixelSize)
        .variant("baseFilter", baseFilter ?? "none")
        .variant("candidateFilter", candidateFilter)
        .variant("resize", "aspect-fill")
        .version("filterRenderer", 1)
}
```

同じ source image が grid、detail view、一時的な preview control に出る場合、このパターンが合います。
アプリが別々の削除や容量調整を必要とするなら、thumbnail、full-size derived image、filter preview の namespace を分けてください。

## 運用チェックリスト

- 生成される bytes を変える入力は、すべて `CacheKey` に含める。
- schema、renderer、normalizer、reader の変更は `version(_:_:)` に入れる。
- absolute path、raw file URL、private user content を public log や公開 example に出さない。
- スクロールやタイル型 UI の処理では `.uiLifecycle` を優先する。
- background 処理、detail 画面、export、最初の caller が消えた後も完了する価値がある生成では、既定の `.share` を使う。
- 大きなテキスト系 `Data` には `CompressedDataCodec` を使う。JPEG、PNG、video data には、実測で効果がある場合を除き使わない。
- `nil` は「今は生成物がない」という意味で扱う。永続化された negative cache state として扱わない。
- thumbnail、preview、search artifact のようにまとめて消せる領域には `removeAll(in:)` を使う。
- 正本データは別の場所に保存する。
