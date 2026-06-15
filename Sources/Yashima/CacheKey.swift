import Foundation

public struct CacheKey: Sendable, Hashable, Codable {
    public var namespace: String
    public var identity: String
    public var variants: [CacheKeyComponent]
    public var versions: [CacheKeyComponent]

    public init(
        namespace: String,
        identity: String,
        variants: [CacheKeyComponent] = [],
        versions: [CacheKeyComponent] = []
    ) {
        self.namespace = namespace
        self.identity = identity
        self.variants = variants
        self.versions = versions
    }

    public init(_ identity: String, namespace: String = "default") {
        self.init(namespace: namespace, identity: identity)
    }

    public func variant<Value: CustomStringConvertible & Sendable>(
        _ name: String,
        _ value: Value
    ) -> CacheKey {
        var key = self
        key.variants.append(CacheKeyComponent(name: name, value: String(describing: value)))
        return key
    }

    public func version<Value: CustomStringConvertible & Sendable>(
        _ name: String,
        _ value: Value
    ) -> CacheKey {
        var key = self
        key.versions.append(CacheKeyComponent(name: name, value: String(describing: value)))
        return key
    }
}

extension CacheKey {
    public static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
        lhs.canonicalRepresentation == rhs.canonicalRepresentation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stableHash.rawValue)
    }
}

public struct CacheKeyComponent: Sendable, Hashable, Codable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    public init(_ name: String, _ value: String) {
        self.init(name: name, value: value)
    }
}

extension CacheKey {
    var canonicalRepresentation: Data {
        var writer = CacheCanonicalWriter()
        writer.appendString("yashima.cache-key.v1")
        writer.appendString("namespace")
        writer.appendString(namespace)
        writer.appendString("identity")
        writer.appendString(identity)
        writer.appendString("variants")
        writer.appendString(String(variants.count))
        for component in variants.canonicalSorted() {
            writer.appendString("component")
            writer.appendString(component.name)
            writer.appendString(component.value)
        }
        writer.appendString("versions")
        writer.appendString(String(versions.count))
        for component in versions.canonicalSorted() {
            writer.appendString("component")
            writer.appendString(component.name)
            writer.appendString(component.value)
        }
        return writer.data
    }

    var stableHash: CacheKeyHash {
        CacheKeyHash(rawValue: StableDigest.sha256Hex(canonicalRepresentation))
    }
}

private extension Array where Element == CacheKeyComponent {
    func canonicalSorted() -> [CacheKeyComponent] {
        sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.value < rhs.value
        }
    }
}
