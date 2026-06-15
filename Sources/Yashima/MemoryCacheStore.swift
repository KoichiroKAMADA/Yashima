actor MemoryCacheStore {
    private var entries: [CacheEntryIdentity: Entry] = [:]
    private var totalCost = 0
    private var accessOrder: UInt64 = 0
    private var limits: Limits

    init(limits: Limits = .unbounded) {
        self.limits = limits
    }

    func peek<Value: Sendable>(
        for identity: CacheEntryIdentity,
        as type: Value.Type = Value.self
    ) -> Value? {
        guard var entry = entries[identity] else {
            return nil
        }

        guard let value = entry.value as? Value else {
            return nil
        }

        entry.lastAccessOrder = nextAccessOrder()
        entries[identity] = entry
        return value
    }

    func containsValue(for identity: CacheEntryIdentity) -> Bool {
        entries[identity] != nil
    }

    @discardableResult
    func put<Value: Sendable>(
        _ value: Value,
        for identity: CacheEntryIdentity,
        cost proposedCost: Int = 1
    ) -> [CacheEntryIdentity] {
        let cost = max(0, proposedCost)

        if let existing = entries[identity] {
            totalCost -= existing.cost
        }

        entries[identity] = Entry(
            value: value,
            cost: cost,
            lastAccessOrder: nextAccessOrder()
        )
        totalCost += cost

        return trimToLimits()
    }

    @discardableResult
    func removeValue(for identity: CacheEntryIdentity) -> Bool {
        guard let removed = entries.removeValue(forKey: identity) else {
            return false
        }

        totalCost -= removed.cost
        return true
    }

    func removeAll(keepingCapacity keepCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepCapacity)
        totalCost = 0
    }

    @discardableResult
    func updateLimits(_ newLimits: Limits) -> [CacheEntryIdentity] {
        limits = newLimits
        return trimToLimits()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            entryCount: entries.count,
            totalCost: totalCost,
            maximumCost: limits.maximumCost,
            maximumEntryCount: limits.maximumEntryCount,
            identitiesByLeastRecentUse: entries
                .sorted { lhs, rhs in lhs.value.lastAccessOrder < rhs.value.lastAccessOrder }
                .map(\.key)
        )
    }
}

extension MemoryCacheStore {
    struct Limits: Sendable, Equatable {
        var maximumCost: Int?
        var maximumEntryCount: Int?

        init(maximumCost: Int? = nil, maximumEntryCount: Int? = nil) {
            self.maximumCost = maximumCost.map { max(0, $0) }
            self.maximumEntryCount = maximumEntryCount.map { max(0, $0) }
        }

        static let unbounded = Limits()
    }

    struct Snapshot: Sendable, Equatable {
        var entryCount: Int
        var totalCost: Int
        var maximumCost: Int?
        var maximumEntryCount: Int?
        var identitiesByLeastRecentUse: [CacheEntryIdentity]
    }
}

private extension MemoryCacheStore {
    struct Entry: Sendable {
        var value: any Sendable
        var cost: Int
        var lastAccessOrder: UInt64
    }

    func nextAccessOrder() -> UInt64 {
        accessOrder += 1
        return accessOrder
    }

    func trimToLimits() -> [CacheEntryIdentity] {
        var removedIdentities: [CacheEntryIdentity] = []

        while isOverLimits {
            guard let identity = leastRecentlyUsedIdentity(),
                  let removed = entries.removeValue(forKey: identity)
            else {
                break
            }

            totalCost -= removed.cost
            removedIdentities.append(identity)
        }

        return removedIdentities
    }

    var isOverLimits: Bool {
        if let maximumEntryCount = limits.maximumEntryCount, entries.count > maximumEntryCount {
            return true
        }

        if let maximumCost = limits.maximumCost, totalCost > maximumCost {
            return true
        }

        return false
    }

    func leastRecentlyUsedIdentity() -> CacheEntryIdentity? {
        entries.min { lhs, rhs in
            lhs.value.lastAccessOrder < rhs.value.lastAccessOrder
        }?.key
    }
}
