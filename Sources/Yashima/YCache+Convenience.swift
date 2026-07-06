import Foundation

extension YCache {
    /// Returns cached `Data` or generates and stores it with `DataCodec`.
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

    /// Returns a cached `Codable` value or generates and stores it.
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
    /// Returns a cached JPEG platform image or generates and stores it.
    public func jpeg(
        for key: CacheKey,
        quality: Double = ImageCodec.defaultJPEGQuality,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.PlatformImage
    ) async throws -> ImageCodec.PlatformImage {
        let value = try await value(
            for: key,
            codec: ImageCodec.jpeg(quality: quality),
            options: options,
            {
                ImageCodec.Value(try await generator())
            }
        )
        return value.image
    }

    /// Returns an optional cached JPEG platform image without storing `nil`.
    public func optionalJPEG(
        for key: CacheKey,
        quality: Double = ImageCodec.defaultJPEGQuality,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.PlatformImage?
    ) async throws -> ImageCodec.PlatformImage? {
        let value = try await optionalValue(
            for: key,
            codec: ImageCodec.jpeg(quality: quality),
            options: options,
            {
                guard let image = try await generator() else {
                    return nil
                }
                return ImageCodec.Value(image)
            }
        )
        return value?.image
    }

    /// Returns a cached PNG platform image or generates and stores it.
    public func png(
        for key: CacheKey,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.PlatformImage
    ) async throws -> ImageCodec.PlatformImage {
        let value = try await value(
            for: key,
            codec: ImageCodec.png,
            options: options,
            {
                ImageCodec.Value(try await generator())
            }
        )
        return value.image
    }

    /// Returns an optional cached PNG platform image without storing `nil`.
    public func optionalPNG(
        for key: CacheKey,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> ImageCodec.PlatformImage?
    ) async throws -> ImageCodec.PlatformImage? {
        let value = try await optionalValue(
            for: key,
            codec: ImageCodec.png,
            options: options,
            {
                guard let image = try await generator() else {
                    return nil
                }
                return ImageCodec.Value(image)
            }
        )
        return value?.image
    }
}
#endif
