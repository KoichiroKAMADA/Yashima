import Foundation
import Yashima

#if canImport(UIKit)
import CoreGraphics
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreGraphics
#endif

public enum DeterministicPayload {
    public static func byteCount(
        seed: Int,
        index: Int,
        profile: StressProfile
    ) -> Int {
        let lower = profile.minimumPayloadByteCount
        let upper = profile.maximumPayloadByteCount
        guard upper > lower else {
            return lower
        }

        let span = upper - lower + 1
        let offset = positiveMix(seed: seed, index: index) % span
        return lower + offset
    }

    public static func data(
        seed: Int,
        index: Int,
        byteCount: Int
    ) -> Data {
        var value = UInt64(bitPattern: Int64(seed))
        value ^= UInt64(index &* 0x9E37)
        value ^= 0xA0761D6478BD642F

        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for position in 0..<byteCount {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let shifted = value >> UInt64((position % 8) * 8)
            bytes.append(UInt8(truncatingIfNeeded: shifted))
        }
        return Data(bytes)
    }

    public static func data(
        seed: Int,
        index: Int,
        profile: StressProfile
    ) -> Data {
        data(
            seed: seed,
            index: index,
            byteCount: byteCount(seed: seed, index: index, profile: profile)
        )
    }

    public static func codableArtifact(
        seed: Int,
        index: Int,
        profile: StressProfile
    ) -> StressCodableArtifact {
        let data = data(seed: seed, index: index, profile: profile)
        return StressCodableArtifact(
            identifier: "artifact-\(index)",
            seed: seed,
            index: index,
            byteCount: data.count,
            checksum: checksum(data)
        )
    }

    public static func checksum(_ data: Data) -> UInt64 {
        data.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private static func positiveMix(seed: Int, index: Int) -> Int {
        var value = UInt64(bitPattern: Int64(seed))
        value ^= UInt64(index &+ 0x7F4A7C15)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Int(value % UInt64(Int.max))
    }
}

public struct StressCodableArtifact: Codable, Equatable, Sendable {
    public let identifier: String
    public let seed: Int
    public let index: Int
    public let byteCount: Int
    public let checksum: UInt64
}

#if canImport(UIKit) || canImport(AppKit)
public enum DeterministicImage {
    public static func make(
        width: Int,
        height: Int,
        seed: Int,
        index: Int
    ) -> ImageCodec.PlatformImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixelCount = width * height
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pixelCount * bytesPerPixel)

        for pixelIndex in 0..<pixelCount {
            let mixed = UInt64(seed &+ index &* 31 &+ pixelIndex &* 17)
            bytes.append(UInt8((mixed &* 53) % 255))
            bytes.append(UInt8((mixed &* 97) % 255))
            bytes.append(UInt8((mixed &* 193) % 255))
            bytes.append(255)
        }

        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        #endif
    }

    public static func size(_ image: ImageCodec.PlatformImage) -> StressImageSize {
        StressImageSize(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }

    public static func size(_ value: ImageCodec.Value) -> StressImageSize {
        size(value.image)
    }
}

public struct StressImageSize: Equatable, Sendable {
    public let width: Int
    public let height: Int
}
#endif
