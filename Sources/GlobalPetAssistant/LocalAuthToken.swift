import Foundation

enum LocalAuthToken {
    static let byteCount = 32

    static func generate() -> String {
        if let handle = FileHandle(forReadingAtPath: "/dev/urandom") {
            let data = handle.readData(ofLength: byteCount)
            try? handle.close()
            if data.count == byteCount {
                return data.map { String(format: "%02x", $0) }.joined()
            }
        }

        return (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    static func bearerToken(from authorizationHeader: String?) -> String? {
        guard let authorizationHeader else {
            return nil
        }

        let parts = authorizationHeader.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else {
            return nil
        }

        let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let count = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }

        return difference == 0
    }
}
