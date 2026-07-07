<p align="right">
  <a href="AdoptionMeasurement.md">English</a> | <strong>日本語</strong>
</p>

# 導入効果の測定

Yashima の性能価値は、スクロール、画面遷移、起動、再表示のたびに繰り返されていたローカル生成を止めることです。

このガイドは、開発者やコーディングエージェントが、Yashima の導入前後で何が変わったかを測るためのものです。

## 測る対象

測るべき対象は、アプリがこれまで繰り返していた作業です。

- 同じ論理アーティファクトに対して producer が何回走ったか。
- 同じ key に対する同時 request がどれだけ発生したか。
- 最初の生成にどれだけ時間がかかったか。
- 画面再表示やアプリ再起動後に、memory hit と storage hit がどれだけ速く返るか。
- 元データ、size、scale、appearance、locale、renderer version が変わったときに、cache key が正しく変わるか。
- 実際の操作後に cache がどれだけ disk を使ったか。

有用な結果は、タイミング値ではなく回数で表せることがあります。
たとえば、スクロール中の grid が同じ thumbnail を 40 回生成していた状況で、導入後に 1 回だけ生成するようになったなら、そのアプリから重複作業が消えたと言えます。
この説明は、一般的な性能主張を必要としません。

## 一時的なアプリ側計測

短い計測用ブランチでは、アプリ側の generator と Yashima 呼び出し箇所の周囲に counter を置きます。
アプリに診断基盤がすでにある場合を除き、これらの counter は release build に残さないでください。

```swift
let resolved = try await cache.resolve(
    for: key,
    codec: ImageCodec.jpeg(quality: 0.85),
    options: .uiLifecycle
) {
    metrics.thumbnailGeneratorRuns += 1
    return try await renderThumbnail()
}

metrics.recordCacheSource(resolved.source)
```

役に立つ counter は次のとおりです。

- `generatorRuns`：producer の実行回数。
- `memoryHits`：現在の cache instance から返った値。
- `storageHits`：file-backed storage から復元された値。
- `generated`：cache entry がなく、新しく生成された値。
- `sharedFromInFlight`：生成中の work を共有した caller。
- `cancelledUIWork`：待ち手がいなくなり cancel された UI-bound request。
- `storageBytes`：`storageUsage()` が報告した bytes。

## 導入前後の確認

導入前には、ひとつの狭い workload を選びます。
たとえば thumbnail grid、document preview、map snapshot、生成済み metadata payload などです。

その workload で、実際の操作中に producer が何回走るかを数えます。
スクロール、同じ画面への再入場、アプリ再起動で、同じ作業が重複していないかも確認します。

導入後には、最初の request が正しく artifact を生成することを確認します。
同じ key の再 request で producer が再実行されないことを確認します。
アプリ再起動や新しい cache instance で storage hit が出ることを確認します。
key が変わるべき入力を変えたときに、正しい entry が invalidation されることも確認します。
最後に、disk 使用量が意図した budget に収まることを確認します。

## 結果の書き方

よい報告は、取り除かれた作業を説明します。

```text
120 items を表示および prefetch する thumbnail grid で、Yashima 導入前は app-side counter が 120 回の generator run を示した。
CacheKey(asset, size, scale, crop, rendererVersion) と JPEG storage を使った導入後は、最初の interaction では 120 件が生成され、直後の再表示では generator run が 0 回になった。
アプリ再起動後は storage hit として復元された。
その session の disk usage は 128 MB budget に対して 18 MB だった。
```

避けるべき報告は、測定で支えていない広すぎる主張をします。

```text
Yashima を入れたのでアプリ全体が速くなった。
```

前者は、アプリから消えた重複作業を説明しています。
後者は、検証できる範囲を広げすぎています。

## 将来のパッケージ性能レビュー

Yashima パッケージ自体の性能は、導入効果の測定とは別にレビューできます。
その作業では、profiling evidence を出発点にし、source code の読みやすさと保守性を制約として扱います。

専用セッションで確認する価値がある問いは次のとおりです。

- storage hit では、metadata read、data read、decode、actor hop、file-system call のどこに時間があるか。
- generated write では、encode、metadata write、atomic replacement、trim check、cache bookkeeping のどこに時間があるか。
- single-flight の overhead は、100 waiter の synthetic case だけの話か、実際のスクロールや起動時 workload にも出るか。
- cache identity、corruption handling、storage trimming の理解しやすさを損なわずに改善できるか。

小さな timing 変化のために、source code の保守性を犠牲にするべきではありません。
実アプリの workload がそのコストを正当化するときだけ、パッケージ本体の最適化を検討します。
