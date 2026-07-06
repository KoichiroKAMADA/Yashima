import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A pass-through codec for `Data` values.
public struct DataCodec: CacheCodec, Equatable {
    /// The stable codec identifier for raw data entries.
    public let identifier = "data-v1"

    /// Creates a data codec.
    public init() {}

    /// Returns the data unchanged.
    public func encode(_ value: Data) throws -> Data {
        value
    }

    /// Returns the stored data unchanged.
    public func decode(_ data: Data) throws -> Data {
        data
    }
}

/// A codec that stores `Data` compressed with LZFSE.
public struct CompressedDataCodec: CacheCodec, CacheMemoryCostEstimating, Equatable {
    /// The stable codec identifier for LZFSE-compressed data entries.
    public let identifier = "compressed-data-lzfse-v1"

    /// Creates a compressed data codec.
    public init() {}

    /// Compresses data with LZFSE before storage.
    public func encode(_ value: Data) throws -> Data {
        try (value as NSData).compressed(using: .lzfse) as Data
    }

    /// Decompresses LZFSE data from storage.
    public func decode(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .lzfse) as Data
    }

    func estimatedMemoryCost(for value: any Sendable, encodedData: Data) -> Int? {
        (value as? Data)?.count ?? encodedData.count
    }
}

/// A codec for `Codable` generated artifacts.
public struct CodableCodec<Value: Codable & Sendable>: CacheCodec, Equatable {
    /// The serialization format used by this codec.
    public let format: Format
    /// The stable codec identifier, including format and value type.
    public let identifier: String

    /// Creates a Codable codec in the selected format.
    public init(format: Format = .json) {
        self.format = format
        self.identifier = Self.identifier(for: format)
    }

    /// Encodes the value using the selected format.
    public func encode(_ value: Value) throws -> Data {
        switch format {
        case .json:
            return try JSONEncoder().encode(value)
        case .propertyList:
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return try encoder.encode(value)
        }
    }

    /// Decodes the value using the selected format.
    public func decode(_ data: Data) throws -> Value {
        switch format {
        case .json:
            return try JSONDecoder().decode(Value.self, from: data)
        case .propertyList:
            return try PropertyListDecoder().decode(Value.self, from: data)
        }
    }
}

extension CodableCodec {
    /// Serialization formats supported by `CodableCodec`.
    public enum Format: Sendable, Equatable {
        /// JSON encoding.
        case json
        /// Binary property list encoding.
        case propertyList
    }
}

private extension CodableCodec {
    static func identifier(for format: Format) -> String {
        "codable-\(format.identifierComponent)-v1:\(String(reflecting: Value.self))"
    }
}

private extension CodableCodec.Format {
    var identifierComponent: String {
        switch self {
        case .json:
            return "json"
        case .propertyList:
            return "property-list-binary"
        }
    }
}

#if canImport(UIKit) || canImport(AppKit)
/// A codec for explicit PNG and JPEG platform images.
public struct ImageCodec: CacheCodec, CacheMemoryCostEstimating, Equatable {
    #if canImport(UIKit)
    /// The platform image type used on UIKit platforms.
    public typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    /// The platform image type used on AppKit platforms.
    public typealias PlatformImage = NSImage
    #endif

    /// The default JPEG quality used by JPEG convenience APIs.
    public static let defaultJPEGQuality = 0.85

    /// The image format used by this codec.
    public let format: Format

    /// The stable codec identifier for the selected image format.
    public var identifier: String {
        switch format {
        case .png:
            return "image-png-v1"
        case .jpeg(let quality):
            return "image-jpeg-q\(Self.qualityPercent(for: quality))-v1"
        }
    }

    /// Creates an image codec for an explicit format.
    public init(format: Format) {
        switch format {
        case .png:
            self.format = .png
        case .jpeg(let quality):
            self.format = .jpeg(quality: Self.normalizedQuality(for: quality))
        }
    }

    /// A PNG image codec.
    public static var png: ImageCodec {
        ImageCodec(format: .png)
    }

    /// Creates a JPEG image codec with normalized quality.
    public static func jpeg(quality: Double = defaultJPEGQuality) -> ImageCodec {
        ImageCodec(format: .jpeg(quality: quality))
    }

    /// Encodes a platform image as PNG or JPEG bytes.
    public func encode(_ value: Value) throws -> Data {
        switch format {
        case .png:
            return try encodePNG(value.image)
        case .jpeg(let quality):
            return try encodeJPEG(value.image, quality: quality)
        }
    }

    /// Decodes PNG or JPEG bytes into a platform image wrapper.
    public func decode(_ data: Data) throws -> Value {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw Error.decodingFailed(format: format.name)
        }
        return Value(image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            throw Error.decodingFailed(format: format.name)
        }
        return Value(image)
        #endif
    }

    func estimatedMemoryCost(for value: any Sendable, encodedData: Data) -> Int? {
        guard let imageValue = value as? Value else {
            return nil
        }

        return Self.estimatedBitmapByteCount(for: imageValue.image) ?? encodedData.count
    }
}

extension ImageCodec {
    /// A Sendable wrapper around the platform image type.
    public struct Value: @unchecked Sendable {
        /// The wrapped platform image.
        public let image: PlatformImage

        /// Creates an image value wrapper.
        public init(_ image: PlatformImage) {
            self.image = image
        }
    }

    /// Image storage formats supported by `ImageCodec`.
    public enum Format: Sendable, Equatable {
        /// PNG storage.
        case png
        /// JPEG storage with normalized quality.
        case jpeg(quality: Double)
    }

    /// Image codec failures.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The platform image could not be encoded.
        case encodingFailed(format: String)
        /// Stored bytes could not be decoded as an image.
        case decodingFailed(format: String)
    }
}

private extension ImageCodec {
    static func normalizedQuality(for quality: Double) -> Double {
        Double(qualityPercent(for: quality)) / 100
    }

    static func qualityPercent(for quality: Double) -> Int {
        guard quality.isFinite else {
            return qualityPercent(for: defaultJPEGQuality)
        }

        let clamped = min(1, max(0, quality))
        return min(100, max(0, Int((clamped * 100).rounded())))
    }

    #if canImport(UIKit)
    static func estimatedBitmapByteCount(for image: UIImage) -> Int? {
        if let cgImage = image.cgImage {
            return max(0, cgImage.bytesPerRow * cgImage.height)
        }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        return estimatedBitmapByteCount(width: pixelWidth, height: pixelHeight)
    }
    #elseif canImport(AppKit)
    static func estimatedBitmapByteCount(for image: NSImage) -> Int? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return max(0, cgImage.bytesPerRow * cgImage.height)
        }

        return estimatedBitmapByteCount(width: image.size.width, height: image.size.height)
    }
    #endif

    static func estimatedBitmapByteCount(width: CGFloat, height: CGFloat) -> Int? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return nil
        }

        let bytes = (width.rounded(.up) * height.rounded(.up) * 4).rounded(.up)
        guard bytes <= CGFloat(Int.max) else {
            return Int.max
        }
        return max(0, Int(bytes))
    }

    #if canImport(UIKit)
    func encodePNG(_ image: UIImage) throws -> Data {
        guard let data = image.pngData() else {
            throw Error.encodingFailed(format: format.name)
        }
        return data
    }

    func encodeJPEG(_ image: UIImage, quality: Double) throws -> Data {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw Error.encodingFailed(format: format.name)
        }
        return data
    }
    #elseif canImport(AppKit)
    func encodePNG(_ image: NSImage) throws -> Data {
        try bitmapRepresentation(for: image)
            .representation(using: .png, properties: [:])
            .orThrowEncodingError(format: format.name)
    }

    func encodeJPEG(_ image: NSImage, quality: Double) throws -> Data {
        try bitmapRepresentation(for: image)
            .representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            )
            .orThrowEncodingError(format: format.name)
    }

    func bitmapRepresentation(for image: NSImage) throws -> NSBitmapImageRep {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            throw Error.encodingFailed(format: format.name)
        }

        return NSBitmapImageRep(cgImage: cgImage)
    }
    #endif
}

private extension ImageCodec.Format {
    var name: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpeg"
        }
    }
}

#if canImport(AppKit) && !canImport(UIKit)
private extension Optional where Wrapped == Data {
    func orThrowEncodingError(format: String) throws -> Data {
        guard let data = self else {
            throw ImageCodec.Error.encodingFailed(format: format)
        }
        return data
    }
}
#endif
#endif
