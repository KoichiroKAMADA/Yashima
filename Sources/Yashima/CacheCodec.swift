import Foundation

/// Encodes and decodes a generated artifact for storage.
///
/// The `identifier` is part of effective cache identity. Change it whenever a
/// codec's encoded representation is intentionally incompatible with older
/// stored entries.
public protocol CacheCodec: Sendable {
    /// The value type handled by this codec.
    associatedtype Value: Sendable

    /// A stable identifier for the codec and encoded representation.
    var identifier: String { get }

    /// Encodes a value into bytes for storage.
    func encode(_ value: Value) throws -> Data
    /// Decodes a value from stored bytes.
    func decode(_ data: Data) throws -> Value
}

protocol CacheMemoryCostEstimating: Sendable {
    func estimatedMemoryCost(for value: any Sendable, encodedData: Data) -> Int?
}
