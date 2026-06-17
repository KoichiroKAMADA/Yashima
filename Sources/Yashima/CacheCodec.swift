import Foundation

public protocol CacheCodec: Sendable {
    associatedtype Value: Sendable

    var identifier: String { get }

    func encode(_ value: Value) throws -> Data
    func decode(_ data: Data) throws -> Value
}

protocol CacheMemoryCostEstimating: Sendable {
    func estimatedMemoryCost(for value: any Sendable, encodedData: Data) -> Int?
}
