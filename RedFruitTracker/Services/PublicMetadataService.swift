import Foundation

struct PublicSeriesMetadata {
    var title: String?
    var coverURL: String?
    var coverCandidates: [String]
    var intro: String?
    var tagsText: String?
    var officialRating: Double?
    var officialHeatText: String?
    var seasons: [PublicSeasonMetadata]
}

struct CoverImageCandidate: Hashable {
    let url: String
    let context: String
}

enum CoverURLSelector {
    static func ranked(
        _ candidates: [CoverImageCandidate],
        title: String? = nil
    ) -> [CoverImageCandidate] {
        var bestByURL: [String: CoverImageCandidate] = [:]

        for candidate in candidates {
            guard !candidate.url.isEmpty else { continue }
            if let existing = bestByURL[candidate.url], score(existing, title: title) >= score(candidate, title: title) {
                continue
            }
            bestByURL[candidate.url] = candidate
        }

        return bestByURL.values.sorted { lhs, rhs in
            let leftScore = score(lhs, title: title)
            let rightScore = score(rhs, title: title)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.url < rhs.url
        }
    }

    static func preferred(
        _ candidates: [CoverImageCandidate],
        title: String? = nil
    ) -> CoverImageCandidate? {
        ranked(candidates, title: title).first { score($0, title: title) >= 8 }
    }

    private static func score(_ candidate: CoverImageCandidate, title: String?) -> Int {
        let value = "\(candidate.url) \(candidate.context)".lowercased()
        var result = 0

        for token in ["封面", "海报", "主角", "女主", "男主", "人物", "poster", "portrait", "cover"] {
            if value.contains(token) { result += 10 }
        }

        for token in [
            "banner", "background", "bg", "share", "logo", "icon", "lock", "empty",
            "loading", "qr", "qrcode", "sprite", "placeholder", "avatar", "emoji", "badge",
            ".svg", "data:image"
        ] {
            if value.contains(token) { result -= 24 }
        }

        let context = candidate.context.lowercased()
        if context.contains("official-current-series-cover") {
            result += 160
        }
        if context.contains("<img") { result += 2 }
        if context.contains("fetchpriority=\"high\"") || context.contains("fetchpriority='high'") {
            result += 14
        }
        if context.contains("rel=\"preload\"") && context.contains("as=\"image\"") {
            result += 28
        }
        if context.contains("json-ld") || context.contains("\"@type\":\"tvseries\"") {
            result += 24
        }
        if context.contains("og:image") { result += 4 }
        if context.contains("novel-pic") { result += 6 }
        if context.contains("width=\"160\"") && context.contains("height=\"224\"") {
            result += 8
        }

        if let title {
            let normalizedTitle = normalizedText(title)
            let altText = attribute(named: "alt", in: context)
            if let altText, !normalizedTitle.isEmpty {
                let normalizedAlt = normalizedText(altText)
                if !normalizedAlt.isEmpty,
                   normalizedAlt.contains(normalizedTitle) || normalizedTitle.contains(normalizedAlt) {
                    result += 32
                } else if !normalizedAlt.isEmpty {
                    result += 3
                }
            }
        }

        if candidate.url.range(of: #"\.(?:jpe?g|png|webp)(?:\?|$)"#, options: .regularExpression) != nil {
            result += 1
        }
        return result
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

    private static func normalizedText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[\\s《》<>:：|丨_\\-]", with: "", options: .regularExpression)
    }
}

struct PublicSeasonMetadata {
    var seasonNumber: Int
    var title: String?
    var episodeCount: Int
    var sourceURL: String?
    var episodes: [PublicEpisodeMetadata]
}

struct PublicEpisodeMetadata {
    var sourceVid: String
    var episodeNumber: Int
    var title: String?
    var webURL: String?
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
        let rawTitle = HTMLMetadata.value(for: ["og:title", "twitter:title"], in: html)
            ?? HTMLMetadata.currentSeriesDetailValue(for: ["series_name", "title", "name"], in: html)
            ?? HTMLMetadata.title(in: html)
        let title = TitleNormalizer.normalize(rawTitle) ?? TitleNormalizer.fallback(from: url)
        let coverCandidates = HTMLMetadata.coverCandidates(in: html, baseURL: url)
        let rankedCoverCandidates = CoverURLSelector.ranked(coverCandidates, title: title)
        let metadata = PublicSeriesMetadata(
            title: title,
            coverURL: CoverURLSelector.preferred(coverCandidates, title: title)?.url,
            coverCandidates: rankedCoverCandidates.prefix(8).map(\.url),
            intro: HTMLMetadata.value(for: ["og:description", "description", "twitter:description"], in: html)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["series_intro", "intro", "description", "abstract", "desc"], in: html),
            tagsText: HTMLMetadata.value(for: ["keywords"], in: html)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["tags", "tag_list", "series_tags", "category", "category_name", "type", "type_name", "genre", "genres", "label", "labels"], in: html),
            officialRating: HTMLMetadata.decimalValue(for: ["rating", "og:rating"], in: html)
                ?? HTMLMetadata.currentSeriesDetailDecimalValue(for: ["rating", "score", "series_score", "official_score"], in: html),
            officialHeatText: HTMLMetadata.value(for: ["heat", "og:heat"], in: html)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["heat", "heat_score", "hot_value", "play_count", "total_play_count", "view_count"], in: html),
            seasons: HTMLMetadata.seasons(in: html, baseURL: url)
        )

        guard rawTitle != nil
            || metadata.coverURL != nil
            || metadata.intro != nil
            || metadata.tagsText != nil
            || !metadata.seasons.isEmpty else {
            throw PublicMetadataError.noMetadata
        }
        return metadata
    }
}

enum HTMLMetadata {
    static func currentSeriesDetailValue(for keys: [String], in html: String) -> String? {
        guard let detail = currentSeriesDetail(in: html) else { return nil }

        for key in keys {
            if let value = value(for: key, in: detail), let text = scalarText(value) {
                return text
            }
        }
        return nil
    }

    static func currentSeriesDetailDecimalValue(for keys: [String], in html: String) -> Double? {
        guard let value = currentSeriesDetailValue(for: keys, in: html),
              let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return Double(String(value[range]))
    }

    private static func currentSeriesDetail(in html: String) -> [String: Any]? {
        guard let routerData = routerData(in: html),
              let loaderData = routerData["loaderData"] as? [String: Any],
              let detailPage = loaderData["detail_page"] as? [String: Any],
              let seriesDetail = detailPage["seriesDetail"] as? [String: Any] else {
            return nil
        }
        return seriesDetail
    }

    private static func value(for key: String, in dictionary: [String: Any]) -> Any? {
        if let value = dictionary[key] { return value }
        if let match = dictionary.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            return match.value
        }
        for nestedKey in ["info", "data", "metadata", "series_info"] {
            guard let nested = dictionary[nestedKey] as? [String: Any] else { continue }
            if let value = value(for: key, in: nested) { return value }
        }
        return nil
    }

    private static func scalarText(_ rawValue: Any) -> String? {
        if let text = rawValue as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = rawValue as? NSNumber, !(rawValue is Bool) {
            return number.stringValue
        }
        if let values = rawValue as? [String] {
            let joined = values.joined(separator: ",")
            return joined.isEmpty ? nil : joined
        }
        if let values = rawValue as? [Any] {
            let texts = values.compactMap { scalarText($0) }
            return texts.isEmpty ? nil : texts.joined(separator: ",")
        }
        if let dictionary = rawValue as? [String: Any] {
            for key in ["value", "text", "name", "score", "count"] {
                if let nested = value(for: key, in: dictionary), let text = scalarText(nested) {
                    return text
                }
            }
        }
        return nil
    }

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

    static func decimalValue(for keys: [String], in html: String) -> Double? {
        guard let value = value(for: keys, in: html),
              let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return Double(String(value[range]))
    }

    static func coverCandidates(in html: String, baseURL: URL) -> [CoverImageCandidate] {
        var candidates: [CoverImageCandidate] = []

        guard let metaRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else {
            return candidates
        }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in metaRegex.matches(in: html, range: htmlRange) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let lowerTag = tag.lowercased()
            let isImageMeta = [
                "og:image",
                "og:image:url",
                "twitter:image",
                "twitter:image:src"
            ].contains { key in
                lowerTag.contains("property=\"\(key)\"")
                    || lowerTag.contains("name=\"\(key)\"")
                    || lowerTag.contains("property='\(key)'")
                    || lowerTag.contains("name='\(key)'")
            }
            let isCoverMeta = lowerTag.contains("cover")
                || lowerTag.contains("poster")
                || lowerTag.contains("\"image\"")
                || lowerTag.contains("'image'")
            guard isImageMeta || isCoverMeta,
                  let rawValue = attribute(named: "content", in: tag) else { continue }
            append(rawValue, context: tag, baseURL: baseURL, to: &candidates)
        }

        if let linkRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive]) {
            for match in linkRegex.matches(in: html, range: htmlRange) {
                guard let tagRange = Range(match.range, in: html) else { continue }
                let tag = String(html[tagRange])
                let lowerTag = tag.lowercased()
                let isPreloadedImage = lowerTag.contains("rel=\"preload\"")
                    && lowerTag.contains("as=\"image\"")
                guard isPreloadedImage
                    || lowerTag.contains("image_src")
                    || lowerTag.contains("cover")
                    || lowerTag.contains("poster"),
                      let rawValue = attribute(named: "href", in: tag) else { continue }
                append(rawValue, context: tag, baseURL: baseURL, to: &candidates)
            }
        }

        if let imageRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive]) {
            for match in imageRegex.matches(in: html, range: htmlRange) {
                guard let tagRange = Range(match.range, in: html) else { continue }
                let tag = String(html[tagRange])
                for attributeName in ["src", "data-src", "data-original", "data-lazy-src", "data-image"] {
                    if let rawValue = attribute(named: attributeName, in: tag) {
                        append(rawValue, context: tag, baseURL: baseURL, to: &candidates)
                    }
                }
                if let rawValue = attribute(named: "srcset", in: tag) {
                    append(firstSrcsetValue(rawValue), context: tag, baseURL: baseURL, to: &candidates)
                }
            }
        }

        if let jsonLDRegex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            for match in jsonLDRegex.matches(in: html, range: htmlRange) {
                guard let valueRange = Range(match.range(at: 1), in: html) else { continue }
                let json = unescape(String(html[valueRange]))
                appendJSONImages(from: json, baseURL: baseURL, to: &candidates)
            }
        }

        if let jsonImageRegex = try? NSRegularExpression(
            pattern: #"[\"'](?:cover|coverUrl|cover_url|poster|posterUrl|poster_url|image|imageUrl|image_url|thumbnailUrl|thumbnail_url|contentUrl|content_url)[\"']\s*:\s*[\"']([^\"']+)[\"']"#,
            options: [.caseInsensitive]
        ) {
            for match in jsonImageRegex.matches(in: html, range: htmlRange) {
                guard let valueRange = Range(match.range(at: 1), in: html),
                      let matchRange = Range(match.range, in: html) else { continue }
                append(String(html[valueRange]), context: String(html[matchRange]), baseURL: baseURL, to: &candidates)
            }
        }

        if let currentSeriesCover = currentSeriesDetailCover(in: html, baseURL: baseURL) {
            candidates.append(currentSeriesCover)
        }

        return candidates
    }

    // The SSR payload identifies the current work; videoList contains related works.
    private static func currentSeriesDetailCover(
        in html: String,
        baseURL: URL
    ) -> CoverImageCandidate? {
        guard let routerData = routerData(in: html),
              let loaderData = routerData["loaderData"] as? [String: Any],
              let detailPage = loaderData["detail_page"] as? [String: Any],
              let seriesDetail = detailPage["seriesDetail"] as? [String: Any] else {
            return nil
        }

        let coverKeys = ["series_cover", "small_series_cover", "series_cover_uri", "series_cover_info"]
        let rawCover = coverKeys.lazy.compactMap { key -> String? in
            if let value = seriesDetail[key] as? String { return value }
            if let info = seriesDetail[key] as? [String: Any] {
                return info["url"] as? String ?? info["uri"] as? String
            }
            return nil
        }.first

        guard let rawCover else { return nil }
        var value = unescape(rawCover)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:\(value)" }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        let seriesName = (seriesDetail["series_name"] as? String) ?? ""
        let context = "official-current-series-cover seriesDetail series_name=\(seriesName)"
        return CoverImageCandidate(url: url.absoluteString, context: context)
    }

    private static func routerData(in html: String) -> [String: Any]? {
        guard let markerRange = html.range(of: "_ROUTER_DATA"),
              let objectStart = html[markerRange.upperBound...].firstIndex(of: "{"),
              let objectEnd = endOfJSONObject(in: html, from: objectStart) else {
            return nil
        }

        let json = String(html[objectStart..<objectEnd])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func endOfJSONObject(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var insideString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
            } else if character == "\"" {
                insideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func appendJSONImages(
        from json: String,
        baseURL: URL,
        to candidates: inout [CoverImageCandidate]
    ) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return
        }
        appendJSONImages(from: object, context: "json-ld \(json)", baseURL: baseURL, to: &candidates)
    }

    private static func appendJSONImages(
        from value: Any,
        context: String,
        baseURL: URL,
        to candidates: inout [CoverImageCandidate]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lowerKey = key.lowercased()
                if ["image", "cover", "coverurl", "cover_url", "poster", "posterurl", "poster_url", "thumbnailurl", "thumbnail_url", "contenturl", "content_url"].contains(lowerKey) {
                    if let imageURL = child as? String {
                        append(imageURL, context: context + " \"\(key)\":\"image\"", baseURL: baseURL, to: &candidates)
                    } else if let imageDictionary = child as? [String: Any],
                              let imageURL = imageDictionary["url"] as? String {
                        append(imageURL, context: context + " \"\(key)\":\"image\"", baseURL: baseURL, to: &candidates)
                    }
                }
                appendJSONImages(from: child, context: context, baseURL: baseURL, to: &candidates)
            }
        } else if let array = value as? [Any] {
            for child in array {
                appendJSONImages(from: child, context: context, baseURL: baseURL, to: &candidates)
            }
        }
    }

    private static func append(
        _ rawValue: String,
        context: String,
        baseURL: URL,
        to candidates: inout [CoverImageCandidate]
    ) {
        var value = unescape(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:\(value)" }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        candidates.append(CoverImageCandidate(url: url.absoluteString, context: context))
    }

    private static func firstSrcsetValue(_ value: String) -> String {
        value
            .split(separator: ",", maxSplits: 1)
            .first?
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? value
    }

    static func seasons(in html: String, baseURL: URL) -> [PublicSeasonMetadata] {
        var seasonsByNumber: [Int: PublicSeasonMetadata] = [:]
        var unassignedEpisodes: [(number: Int, title: String?, url: String?, sourceVid: String)] = []

        guard let anchorRegex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*>.*?</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in anchorRegex.matches(in: html, range: htmlRange) {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let anchor = String(html[matchRange])
            guard let openingEnd = anchor.firstIndex(of: ">"),
                  let closingStart = anchor.range(of: "</a", options: [.caseInsensitive])?.lowerBound else {
                continue
            }

            let openingTag = String(anchor[...openingEnd])
            let rawText = String(anchor[anchor.index(after: openingEnd)..<closingStart])
            let text = unescape(stripTags(rawText))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let href = attribute(named: "href", in: openingTag)
            let resolvedURL = href.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            let resolvedString = resolvedURL?.absoluteString
            let seasonNumber = attribute(named: "data-season", in: openingTag).flatMap { Int($0) }
                ?? firstSeasonNumber(in: text)
                ?? resolvedURL.flatMap { queryInt(named: ["season", "s"], in: $0) }
                ?? firstSeasonNumber(in: resolvedString ?? "")
            let episodeNumber = attribute(named: "data-episode", in: openingTag).flatMap { Int($0) }
                ?? firstEpisodeNumber(in: text)
                ?? resolvedURL.flatMap { queryInt(named: ["episode", "ep", "e"], in: $0) }
                ?? firstEpisodeNumber(in: resolvedString ?? "")

            if let seasonNumber, (1...999).contains(seasonNumber) {
                var season = seasonsByNumber[seasonNumber] ?? PublicSeasonMetadata(
                    seasonNumber: seasonNumber,
                    title: "第\(seasonNumber)季",
                    episodeCount: 0,
                    sourceURL: resolvedString,
                    episodes: []
                )
                if season.sourceURL == nil { season.sourceURL = resolvedString }
                if !text.isEmpty, firstEpisodeNumber(in: text) == nil {
                    season.title = TitleNormalizer.normalize(text) ?? season.title
                }
                if let count = episodeCount(in: text) {
                    season.episodeCount = max(season.episodeCount, count)
                }
                if let episodeNumber, (1...99999).contains(episodeNumber) {
                    let episode = PublicEpisodeMetadata(
                        sourceVid: resolvedString ?? "s\(seasonNumber)-e\(episodeNumber)",
                        episodeNumber: episodeNumber,
                        title: episodeTitle(from: text, episodeNumber: episodeNumber),
                        webURL: resolvedString
                    )
                    if !season.episodes.contains(where: { $0.episodeNumber == episodeNumber }) {
                        season.episodes.append(episode)
                    }
                    season.episodeCount = max(season.episodeCount, episodeNumber)
                }
                seasonsByNumber[seasonNumber] = season
            } else if let episodeNumber, (1...99999).contains(episodeNumber) {
                unassignedEpisodes.append((
                    number: episodeNumber,
                    title: episodeTitle(from: text, episodeNumber: episodeNumber),
                    url: resolvedString,
                    sourceVid: resolvedString ?? "e\(episodeNumber)"
                ))
            }
        }

        let globalSeasonCount = firstNumber(in: html, patterns: [
            #"(?:共|total\s*)\s*([0-9]{1,3})\s*(?:季|seasons?)"#
        ])
        if seasonsByNumber.isEmpty, let globalSeasonCount, (1...99).contains(globalSeasonCount) {
            for number in 1...globalSeasonCount {
                seasonsByNumber[number] = PublicSeasonMetadata(
                    seasonNumber: number,
                    title: "第\(number)季",
                    episodeCount: 0,
                    sourceURL: nil,
                    episodes: []
                )
            }
        }

        if seasonsByNumber.isEmpty, !unassignedEpisodes.isEmpty {
            seasonsByNumber[1] = PublicSeasonMetadata(
                seasonNumber: 1,
                title: "第1季",
                episodeCount: 0,
                sourceURL: nil,
                episodes: []
            )
        }

        if seasonsByNumber.count == 1, !unassignedEpisodes.isEmpty,
           var season = seasonsByNumber.values.first {
            for item in unassignedEpisodes where !season.episodes.contains(where: { $0.episodeNumber == item.number }) {
                season.episodes.append(PublicEpisodeMetadata(
                    sourceVid: item.sourceVid,
                    episodeNumber: item.number,
                    title: item.title,
                    webURL: item.url
                ))
            }
            season.episodeCount = max(season.episodeCount, season.episodes.map(\.episodeNumber).max() ?? 0)
            seasonsByNumber[season.seasonNumber] = season
        }

        if seasonsByNumber.count == 1, let seasonNumber = seasonsByNumber.keys.first,
           let totalEpisodeCount = firstNumber(in: html, patterns: [
               #"(?:共|total\s*)\s*([0-9]{1,5})\s*(?:集|episodes?)"#
           ]) {
            var season = seasonsByNumber[seasonNumber]!
            season.episodeCount = max(season.episodeCount, totalEpisodeCount)
            seasonsByNumber[seasonNumber] = season
        }

        return seasonsByNumber.values
            .map { season in
                var copy = season
                copy.episodes.sort { $0.episodeNumber < $1.episodeNumber }
                return copy
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
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

    private static func stripTags(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else {
            return value
        }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: " "
        )
    }

    private static func firstSeasonNumber(in value: String) -> Int? {
        firstNumber(in: value, patterns: [
            #"(?:第\s*)?([0-9]{1,3})\s*季"#,
            #"\bseason\s*([0-9]{1,3})\b"#,
            #"\bs([0-9]{1,3})\b"#
        ])
    }

    private static func firstEpisodeNumber(in value: String) -> Int? {
        firstNumber(in: value, patterns: [
            #"(?:第\s*)?([0-9]{1,5})\s*集"#,
            #"\bepisode\s*([0-9]{1,5})\b"#,
            #"\bep\.?\s*([0-9]{1,5})\b"#
        ])
    }

    private static func episodeCount(in value: String) -> Int? {
        firstNumber(in: value, patterns: [
            #"(?:共|total\s*)\s*([0-9]{1,5})\s*(?:集|episodes?)"#
        ])
    }

    private static func firstNumber(in value: String, patterns: [String]) -> Int? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: value, range: range),
                  let numberRange = Range(match.range(at: 1), in: value),
                  let number = Int(String(value[numberRange])) else {
                continue
            }
            return number
        }
        return nil
    }

    private static func queryInt(named names: [String], in url: URL) -> Int? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems else {
            return nil
        }
        for name in names {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value,
               let number = Int(value) {
                return number
            }
        }
        return nil
    }

    private static func episodeTitle(from text: String, episodeNumber: Int) -> String? {
        let value = text
            .replacingOccurrences(of: "第\(episodeNumber)集", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_|丨·:：")))
        return value.isEmpty ? nil : value
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
