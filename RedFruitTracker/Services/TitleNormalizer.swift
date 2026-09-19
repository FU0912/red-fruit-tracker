import Foundation

enum TitleNormalizer {
    static func normalize(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        value = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        let prefixPatterns = [
            #"^\s*(?:分享|推荐|给你分享|我在红果(?:漫剧|短剧)?看到的?)\s*[:：\-|丨_]*\s*"#,
            #"^\s*红果(?:漫剧|短剧|视频)?\s*[:：\-|丨_]*\s*"#
        ]
        for pattern in prefixPatterns {
            value = replacing(pattern, in: value)
        }

        let suffixPattern = #"\s*[-_|丨·:：]*\s*(?:红果(?:漫剧|短剧|视频)?|红果)\s*(?:官方)?\s*$"#
        value = replacing(suffixPattern, in: value)

        value = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "-_|丨·:：")
        ))

        if value.hasPrefix("《"), value.hasSuffix("》"), value.count > 2 {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("【"), value.hasSuffix("】"), value.count > 2 {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func fallback(from url: URL) -> String? {
        let pathTitle = url.lastPathComponent
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ")
        return normalize(pathTitle)
    }

    private static func replacing(_ pattern: String, in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }
}
