import Testing
@testable import Yashima

@Test func memoryStoreReturnsHitForStoredValue() async {
    let store = MemoryCacheStore()
    let identity = memoryIdentity("hit")

    await store.put("cached", for: identity, cost: 4)

    let value = await store.peek(for: identity, as: String.self)
    let snapshot = await store.snapshot()

    #expect(value == "cached")
    #expect(snapshot.entryCount == 1)
    #expect(snapshot.totalCost == 4)
}

@Test func memoryStoreReturnsNilForMiss() async {
    let store = MemoryCacheStore()
    let value = await store.peek(for: memoryIdentity("missing"), as: String.self)

    #expect(value == nil)
}

@Test func memoryStoreOverwritesExistingIdentityAndCost() async {
    let store = MemoryCacheStore()
    let identity = memoryIdentity("overwrite")

    await store.put("old", for: identity, cost: 3)
    let evicted = await store.put("new", for: identity, cost: 7)

    let value = await store.peek(for: identity, as: String.self)
    let snapshot = await store.snapshot()

    #expect(evicted.isEmpty)
    #expect(value == "new")
    #expect(snapshot.entryCount == 1)
    #expect(snapshot.totalCost == 7)
}

@Test func memoryStoreEvictsLeastRecentlyUsedEntryWhenCostLimitIsExceeded() async {
    let store = MemoryCacheStore(limits: .init(maximumCost: 10))
    let first = memoryIdentity("first")
    let second = memoryIdentity("second")
    let third = memoryIdentity("third")

    await store.put("first", for: first, cost: 4)
    await store.put("second", for: second, cost: 4)
    _ = await store.peek(for: first, as: String.self)
    let evicted = await store.put("third", for: third, cost: 4)

    let firstValue = await store.peek(for: first, as: String.self)
    let secondValue = await store.peek(for: second, as: String.self)
    let thirdValue = await store.peek(for: third, as: String.self)
    let snapshot = await store.snapshot()

    #expect(evicted == [second])
    #expect(firstValue == "first")
    #expect(secondValue == nil)
    #expect(thirdValue == "third")
    #expect(snapshot.entryCount == 2)
    #expect(snapshot.totalCost == 8)
}

@Test func memoryStoreEvictsLeastRecentlyUsedEntryWhenEntryCountLimitIsExceeded() async {
    let store = MemoryCacheStore(limits: .init(maximumEntryCount: 2))
    let first = memoryIdentity("first")
    let second = memoryIdentity("second")
    let third = memoryIdentity("third")

    await store.put(1, for: first)
    await store.put(2, for: second)
    _ = await store.peek(for: first, as: Int.self)
    let evicted = await store.put(3, for: third)

    let firstValue = await store.peek(for: first, as: Int.self)
    let secondValue = await store.peek(for: second, as: Int.self)
    let thirdValue = await store.peek(for: third, as: Int.self)

    #expect(evicted == [second])
    #expect(firstValue == 1)
    #expect(secondValue == nil)
    #expect(thirdValue == 3)
}

@Test func memoryStoreDoesNotRetainEntryLargerThanCostLimit() async {
    let store = MemoryCacheStore(limits: .init(maximumCost: 5))
    let identity = memoryIdentity("oversized")

    let evicted = await store.put("large", for: identity, cost: 6)
    let value = await store.peek(for: identity, as: String.self)
    let snapshot = await store.snapshot()

    #expect(evicted == [identity])
    #expect(value == nil)
    #expect(snapshot.entryCount == 0)
    #expect(snapshot.totalCost == 0)
}

@Test func memoryStoreRemoveValueUpdatesState() async {
    let store = MemoryCacheStore()
    let identity = memoryIdentity("remove")

    await store.put("cached", for: identity, cost: 5)

    let firstRemoval = await store.removeValue(for: identity)
    let secondRemoval = await store.removeValue(for: identity)
    let value = await store.peek(for: identity, as: String.self)
    let snapshot = await store.snapshot()

    #expect(firstRemoval)
    #expect(!secondRemoval)
    #expect(value == nil)
    #expect(snapshot.entryCount == 0)
    #expect(snapshot.totalCost == 0)
}

@Test func memoryStoreTreatsTypeMismatchAsMiss() async {
    let store = MemoryCacheStore()
    let identity = memoryIdentity("typed")

    await store.put(42, for: identity)

    let mismatched = await store.peek(for: identity, as: String.self)
    let matched = await store.peek(for: identity, as: Int.self)

    #expect(mismatched == nil)
    #expect(matched == 42)
}

@Test func memoryStoreSerializesConcurrentAccess() async {
    let store = MemoryCacheStore(limits: .init(maximumCost: 200, maximumEntryCount: 200))

    let allTasksSucceeded = await withTaskGroup(of: Bool.self) { group in
        for index in 0..<100 {
            group.addTask {
                let identity = memoryIdentity("concurrent-\(index)")
                await store.put(index, for: identity, cost: 1)
                let value = await store.peek(for: identity, as: Int.self)
                return value == index
            }
        }

        var result = true
        for await succeeded in group {
            result = result && succeeded
        }
        return result
    }

    let snapshot = await store.snapshot()

    #expect(allTasksSucceeded)
    #expect(snapshot.entryCount == 100)
    #expect(snapshot.totalCost == 100)
}

private func memoryIdentity(_ name: String) -> CacheEntryIdentity {
    CacheEntryIdentity(
        key: CacheKey(namespace: "memory-tests", identity: name),
        codecIdentifier: "test-codec-v1"
    )
}
