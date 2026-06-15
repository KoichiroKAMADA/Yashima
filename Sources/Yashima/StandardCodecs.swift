import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct DataCodec: CacheCodec, Equatable {
    public let identifier = "data-v1"

    public init() {}

    public func encode(_ value: Data) throws -> Data {
        value
    }

    public func decode(_ data: Data) throws -> Data {
        data
    }
}

public struct CodableCodec<Value: Codable & Sendable>: CacheCodec, Equatable {
    public let format: Format
    public let identifier: String

    public init(format: Format = .json) {
        self.format = format
        self.identifier = Self.identifier(for: format)
    }

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
    public enum Format: Sendable, Equatable {
        case json
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
public struct ImageCodec: CacheCodec, Equatable {
    #if canImport(UIKit)
    public typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    public typealias PlatformImage = NSImage
    #endif

    public static let defaultJPEGQuality = 0.85

    public let format: Format

    public var identifier: String {
        switch format {
        case .png:
            return "image-png-v1"
        case .jpeg(let quality):
            return "image-jpeg-q\(Self.qualityPercent(for: quality))-v1"
        }
    }

    public init(format: Format) {
        switch format {
        case .png:
            self.format = .png
        case .jpeg(let quality):
            self.format = .jpeg(quality: Self.normalizedQuality(for: quality))
        }
    }

    public static var png: ImageCodec {
        ImageCodec(format: .png)
    }

    public static func jpeg(quality: Double = defaultJPEGQuality) -> ImageCodec {
        ImageCodec(format: .jpeg(quality: quality))
    }

    public func encode(_ value: Value) throws -> Data {
        switch format {
        case .png:
            return try encodePNG(value.image)
        case .jpeg(let quality):
            return try encodeJPEG(value.image, quality: quality)
        }
    }

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
}

extension ImageCodec {
    public struct Value: @unchecked Sendable {
        public let image: PlatformImage

        public init(_ image: PlatformImage) {
            self.image = image
        }
    }

    public enum Format: Sendable, Equatable {
        case png
        case jpeg(quality: Double)
    }

    public enum Error: Swift.Error, Sendable, Equatable {
        case encodingFailed(format: String)
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
