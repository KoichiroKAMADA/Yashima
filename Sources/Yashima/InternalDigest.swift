import CryptoKit
import Foundation

enum StableDigest {
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        var output: [UInt8] = []
        output.reserveCapacity(64)

        for byte in digest {
            output.append(hexDigits[Int(byte >> 4)])
            output.append(hexDigits[Int(byte & 0x0f)])
        }

        return String(decoding: output, as: UTF8.self)
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)
}

struct CacheCanonicalWriter {
    private var bytes: [UInt8] = []

    var data: Data {
        Data(bytes)
    }

    mutating func appendString(_ value: String) {
        appendData(Data(value.utf8))
    }

    mutating func appendData(_ data: Data) {
        let count = String(data.count)
        bytes.append(contentsOf: count.utf8)
        bytes.append(0)
        bytes.append(contentsOf: data)
        bytes.append(10)
    }
}
