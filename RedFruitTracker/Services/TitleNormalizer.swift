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
            #"^\s*红果(?:漫剧|短剧|视频)?\s*[:：\-|丨_]*\s*"#,
            #"^\s*(?:免费观看|免费看片|免费在线观看|免费(?:观看|看剧|看)?|在线(?:观看|看)?)\s*[:：\-|丨_]*\s*"#
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

        if let bookTitle = extractBookTitle(from: value),
           (value.localizedCaseInsensitiveContains("免费")
                || value.localizedCaseInsensitiveContains("红果")
                || value.localizedCaseInsensitiveContains("观看")) {
            value = bookTitle
        }

        return value.isEmpty ? nil : value
    }

    static func fallback(from url: URL) -> String? {
        let pathTitle = url.lastPathComponent
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ")
        return normalize(pathTitle)
    }

    static func seriesTitle(_ rawValue: String?) -> String? {
        guard var value = normalize(rawValue) else { return nil }

        value = removingSeasonSuffix(from: value)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "-_|丨·:：")
            ))

        return value.isEmpty ? nil : value
    }

    static func seriesKey(_ rawValue: String?) -> String? {
        guard let title = seriesTitle(rawValue) else { return nil }

        let key = title.unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            }
            .map(String.init)
            .joined()
            .lowercased()

        return key.isEmpty ? nil : key
    }

    static func seasonNumber(_ rawValue: String?) -> Int? {
        guard let value = normalize(rawValue) else { return nil }

        if let number = firstNumber(
            in: value,
            pattern: #"(?:第\s*)?([0-9]{1,3})\s*季"#
        ) {
            return number
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?:第\s*)?([一二三四五六七八九十百零〇两]+)\s*季"#,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ),
        let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return chineseNumeralValue(String(value[range]))
    }

    private static func replacing(_ pattern: String, in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }

    private static func extractBookTitle(from value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"《([^《》]{1,120})》"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let titleRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingSeasonSuffix(from value: String) -> String {
        let patterns = [
            #"\s*(?:第\s*)?(?:[0-9]{1,3}|[一二三四五六七八九十百零〇两]+)\s*季\s*$"#,
            #"\s*season\s*[0-9]{1,3}\s*$"#,
            #"\s*s[0-9]{1,3}\s*$"#
        ]

        return patterns.reduce(value) { current, pattern in
            replacing(pattern, in: current)
        }
    }

    private static func firstNumber(in value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return Int(String(value[range]))
    }

    private static func chineseNumeralValue(_ value: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        var total = 0
        var current = 0

        for character in value {
            if character == "十" {
                total += (current == 0 ? 1 : current) * 10
                current = 0
            } else if character == "百" {
                total += (current == 0 ? 1 : current) * 100
                current = 0
            } else if let digit = digits[character] {
                current = digit
            } else {
                return nil
            }
        }

        let result = total + current
        return result > 0 ? result : nil
    }
}
