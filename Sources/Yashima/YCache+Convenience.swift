import Foundation

extension YCache {
    public func data(
        for key: CacheKey,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        try await value(
            for: key,
            codec: DataCodec(),
            options: options,
            generator
        )
    }

    public func codable<Value: Codable & Sendable>(
        for key: CacheKey,
        format: CodableCodec<Value>.Format = .json,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await value(
            for: key,
            codec: CodableCodec<Value>(format: format),
            options: options,
            generator
        )
    }
}

#if canImport(UIKit) || canImport(AppKit)
extension YCache {
    public func jpeg(
        for key: CacheKey,
        quality: Double = ImageCodec.defaultJPEGQuality,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.Value
    ) async throws -> ImageCodec.Value {
        try await value(
            for: key,
            codec: ImageCodec.jpeg(quality: quality),
            options: options,
            generator
        )
    }

    public func png(
        for key: CacheKey,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.Value
    ) async throws -> ImageCodec.Value {
        try await value(
            for: key,
            codec: ImageCodec.png,
            options: options,
            generator
        )
    }
}
#endif
