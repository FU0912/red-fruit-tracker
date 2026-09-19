import Foundation

struct PublicSeriesMetadata {
    var title: String?
    var coverURL: String?
    var intro: String?
    var tagsText: String?
    var officialRating: Double?
    var officialHeatText: String?
}

enum PublicMetadataError: LocalizedError {
    case unsupportedURL
    case invalidResponse
    case noMetadata

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "这个链接不是可读取的网页链接。"
        case .invalidResponse:
            return "公开页面暂时无法读取。"
        case .noMetadata:
            return "页面没有提供可识别的公开资料。"
        }
    }
}

actor PublicMetadataService {
    static let shared = PublicMetadataService()

    func fetch(from url: URL) async throws -> PublicSeriesMetadata {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PublicMetadataError.unsupportedURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<400 ~= httpResponse.statusCode else {
            throw PublicMetadataError.invalidResponse
        }

        let html = String(decoding: data, as: UTF8.self)
        let metadata = PublicSeriesMetadata(
            title: HTMLMetadata.value(for: ["og:title", "twitter:title"], in: html)
                ?? HTMLMetadata.title(in: html),
            coverURL: HTMLMetadata.value(for: ["og:image", "twitter:image"], in: html),
            intro: HTMLMetadata.value(for: ["og:description", "description", "twitter:description"], in: html),
            tagsText: HTMLMetadata.value(for: ["keywords"], in: html),
            officialRating: Double(HTMLMetadata.value(for: ["rating", "og:rating"], in: html) ?? ""),
            officialHeatText: HTMLMetadata.value(for: ["heat", "og:heat"], in: html)
        )

        guard metadata.title != nil || metadata.coverURL != nil || metadata.intro != nil else {
            throw PublicMetadataError.noMetadata
        }
        return metadata
    }
}

private enum HTMLMetadata {
    static func value(for keys: [String], in html: String) -> String? {
        let metaPattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: fullRange) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let lowerTag = tag.lowercased()
            guard keys.contains(where: { key in
                let lowerKey = key.lowercased()
                return lowerTag.contains("name=\"\(lowerKey)\"")
                    || lowerTag.contains("property=\"\(lowerKey)\"")
                    || lowerTag.contains("name='\(lowerKey)'")
                    || lowerTag.contains("property='\(lowerKey)'")
            }) else {
                continue
            }

            if let content = attribute(named: "content", in: tag) {
                return unescape(content)
            }
        }
        return nil
    }

    static func title(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let valueRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let value = unescape(String(html[valueRange]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func attribute(named name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*([\\\"'])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              let valueRange = Range(match.range(at: 2), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
