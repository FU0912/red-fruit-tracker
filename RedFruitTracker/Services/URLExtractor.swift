import Foundation

enum URLExtractor {
    private static let urlPattern = #"https?://[^\s<>\"“”‘’]+"#

    static func firstURL(in text: String) -> URL? {
        allURLs(in: text).first
    }

    static func allURLs(in text: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let candidate = trimPunctuation(from: String(text[matchRange]))
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#x26;", with: "&")
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else {
                return nil
            }
            return url
        }
    }

    private static func trimPunctuation(from value: String) -> String {
        let punctuation = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",，。;；:：!！?？、)]}》〉】»’\"'"))
        return value.trimmingCharacters(in: punctuation)
    }
}

enum ClipboardShareDetector {
    static func redFruitURL(in text: String) -> URL? {
        URLExtractor.allURLs(in: text).first { url in
            let host = url.host?.lowercased() ?? ""
            return host == "hongguoduanju.com" || host.hasSuffix(".hongguoduanju.com")
                || host == "hongguo.com" || host.hasSuffix(".hongguo.com")
                || host == "kylin.hainanyuyue.com"
        }
    }
}
