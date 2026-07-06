# Cancellation and UI Lifecycle

Yashima separates waiter cancellation from producer cancellation.

The default single-flight behavior is conservative: concurrent requests for the
same key and codec share one producer, and cancelling one waiter does not cancel
the producer while other waiters remain.

For UI lifecycle work such as scrolling cells, thumbnails, MapKit snapshots, or
chart snapshots, use ``YCache/Options/uiLifecycle``:

```swift
let image = try await cache.optionalJPEG(for: key, options: .uiLifecycle) {
    try await renderThumbnailIfAvailable()
}
```

The preset combines ``CacheSingleFlightPolicy/cancelWhenNoWaiters`` with
``CacheWriteFailurePolicy/bestEffort``. When every waiter disappears, Yashima
cancels the producer task, removes the in-flight entry, and does not store a
cancelled generation result.

## Generator Responsibility

Yashima can cancel the task that runs the generator. The generator still owns any
producer-specific cancellation, such as checking `Task.checkCancellation()` or
calling cancellation APIs on image generators, snapshotters, or asset managers.

Use the default shared behavior for background work, detail screens, exports, or
any generation where finishing the producer still has value after the original
caller disappears.

Use ``CacheSingleFlightPolicy/disabled`` only when each caller should perform an
independent lookup and generation path for the same key and codec.
