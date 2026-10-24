import Foundation
import CoreFoundation
import CoreGraphics
import ImageIO

struct PublicSeriesMetadata {
    var title: String?
    var coverURL: String?
    var coverCandidates: [String]
    var intro: String?
    var tagsText: String?
    var officialRating: Double?
    var officialRatingCount: Int?
    var officialHeatScore: Double?
    var officialHeatText: String?
    var completionStatus: String?
    var seasons: [PublicSeasonMetadata]
}

struct CoverImageCandidate: Hashable, Sendable {
    let url: String
    let context: String
}

enum CoverURLSelector {
    static func shouldReplaceExisting(_ url: String?) -> Bool {
        guard let url = url?.lowercased(), !url.isEmpty else { return true }
        return [
            "first-frame", "first_frame", "video-frame", "video_frame",
            "snapshot", "screenshot", "video-still", "video_still", "still",
            "share-cover", "share_cover", "thumbnail", "thumb"
        ].contains { url.contains($0) }
    }

    static func ranked(
        _ candidates: [CoverImageCandidate],
        title: String? = nil
    ) -> [CoverImageCandidate] {
        var bestByURL: [String: CoverImageCandidate] = [:]

        for candidate in candidates {
            guard !candidate.url.isEmpty else { continue }
            let key = deduplicationKey(for: candidate.url)
            if let existing = bestByURL[key], score(existing, title: title) >= score(candidate, title: title) {
                continue
            }
            bestByURL[key] = candidate
        }

        return bestByURL.values.sorted { lhs, rhs in
            let leftScore = score(lhs, title: title)
            let rightScore = score(rhs, title: title)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.url < rhs.url
        }
    }

    private static func deduplicationKey(for rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else { return rawURL }
        let host = components.host?.lowercased() ?? ""
        var path = components.percentEncodedPath
        if host.hasSuffix(".byteimg.com"),
           host.range(of: #"^p\d+-novel\.byteimg\.com$"#, options: .regularExpression) != nil {
            components.host = "novel.byteimg.com"
            path = replacing(#"\.(?:jpe?g|png|webp|image)$"#, in: path, with: "")
            path = replacing(#"~tplv[^/]*$"#, in: path, with: "")
        }
        path = replacing(#"\.(?:jpe?g|png|webp|image)$"#, in: path, with: "")
        components.percentEncodedPath = path
        components.fragment = nil
        components.scheme = "https"
        let transformKeys: Set<String> = [
            "w", "width", "h", "height", "q", "quality", "fm", "format", "fit", "crop",
            "resize", "token", "expires", "signature", "x-oss-process", "imageMogr2"
        ]
        components.queryItems = components.queryItems?.filter {
            !transformKeys.contains($0.name.lowercased())
        }
        return components.string ?? rawURL
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
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
            "related", "recommend", "recommendation", "猜你喜欢", "相关推荐", "相关作品", "推荐作品",
            "first-frame", "first_frame", "video-frame", "video_frame", "snapshot", "screenshot",
            "still", "frame", ".svg", "data:image"
        ] {
            if value.contains(token) { result -= 24 }
        }

        let context = candidate.context.lowercased()
        if context.contains("share-video-cover") {
            result -= 240
        }

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

enum PublicSeasonMetadataMerger {
    static func merge(primary: [PublicSeasonMetadata], supplement: [PublicSeasonMetadata]) -> [PublicSeasonMetadata] {
        var seasonsByNumber = [Int: PublicSeasonMetadata]()
        for season in supplement { seasonsByNumber[season.seasonNumber] = season }

        for preferred in primary {
            guard let fallback = seasonsByNumber[preferred.seasonNumber] else {
                seasonsByNumber[preferred.seasonNumber] = preferred
                continue
            }

            var episodesByNumber = [Int: PublicEpisodeMetadata]()
            for episode in fallback.episodes { episodesByNumber[episode.episodeNumber] = episode }
            for episode in preferred.episodes { episodesByNumber[episode.episodeNumber] = episode }

            var merged = preferred
            if merged.episodeCount <= 0 { merged.episodeCount = fallback.episodeCount }
            if merged.title?.isEmpty ?? true { merged.title = fallback.title }
            if merged.sourceURL == nil { merged.sourceURL = fallback.sourceURL }
            merged.episodes = episodesByNumber.values.sorted { $0.episodeNumber < $1.episodeNumber }
            seasonsByNumber[preferred.seasonNumber] = merged
        }

        return seasonsByNumber.values.sorted { $0.seasonNumber < $1.seasonNumber }
    }
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

        let html = try await requestHTML(from: url)
        let detailURL = HTMLMetadata.officialDetailURL(in: html)
        let detailHTML: String
        let detailBaseURL: URL
        if let detailURL, let fetchedDetailHTML = try? await requestHTML(from: detailURL) {
            detailHTML = fetchedDetailHTML
            detailBaseURL = detailURL
        } else {
            detailHTML = html
            detailBaseURL = url
        }

        let metadataHTML = detailHTML
        let rawTitle = HTMLMetadata.currentSeriesDetailValue(for: ["series_name", "title", "name"], in: metadataHTML)
            ?? HTMLMetadata.currentSeriesDetailValue(for: ["series_name", "title", "name"], in: html)
            ?? HTMLMetadata.value(for: ["og:title", "twitter:title"], in: metadataHTML)
            ?? HTMLMetadata.value(for: ["og:title", "twitter:title"], in: html)
            ?? HTMLMetadata.title(in: metadataHTML)
            ?? HTMLMetadata.title(in: html)
        let title = TitleNormalizer.normalize(rawTitle) ?? TitleNormalizer.fallback(from: url)
        var coverCandidates = HTMLMetadata.coverCandidates(in: metadataHTML, baseURL: detailBaseURL)
        if detailURL != nil {
            coverCandidates.append(contentsOf: HTMLMetadata.coverCandidates(in: html, baseURL: url))
        }
        let rankedCoverCandidates = CoverURLSelector.ranked(coverCandidates, title: title)
        let verifiedCoverCandidates = await PortraitCoverProbe.distinctPortraits(from: rankedCoverCandidates)
        let coverURL = verifiedCoverCandidates.first?.candidate.url
        let detailSeasons = HTMLMetadata.seasons(in: metadataHTML, baseURL: detailBaseURL)
        let shareSeasons = detailURL == nil ? [] : HTMLMetadata.seasons(in: html, baseURL: url)
        let metadata = PublicSeriesMetadata(
            title: title,
            coverURL: coverURL,
            coverCandidates: verifiedCoverCandidates.prefix(8).map(\.candidate.url),
            intro: HTMLMetadata.value(for: ["og:description", "description", "twitter:description"], in: metadataHTML)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["series_intro", "intro", "description", "abstract", "desc"], in: metadataHTML)
                ?? HTMLMetadata.value(for: ["og:description", "description", "twitter:description"], in: html)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["series_intro", "intro", "description", "abstract", "desc"], in: html),
            tagsText: HTMLMetadata.currentSeriesDetailValue(for: ["tags", "tag_list", "series_tags", "category_list", "category", "category_name", "type", "type_name", "genre", "genres", "label", "labels"], in: metadataHTML)
                ?? HTMLMetadata.value(for: ["keywords"], in: metadataHTML)
                ?? HTMLMetadata.currentSeriesDetailValue(for: ["tags", "tag_list", "series_tags", "category_list", "category", "category_name", "type", "type_name", "genre", "genres", "label", "labels"], in: html)
                ?? HTMLMetadata.value(for: ["keywords"], in: html),
            officialRating: HTMLMetadata.officialRating(in: metadataHTML)
                ?? HTMLMetadata.officialRating(in: html),
            officialRatingCount: HTMLMetadata.currentSeriesSocialInfoIntValue(for: ["rating_count", "ratingCount"], in: metadataHTML)
                ?? HTMLMetadata.currentSeriesSocialInfoIntValue(for: ["rating_count", "ratingCount"], in: html),
            officialHeatScore: HTMLMetadata.officialHeatScore(in: html, fallbackHTML: metadataHTML),
            officialHeatText: HTMLMetadata.officialHeatText(in: html, fallbackHTML: metadataHTML),
            completionStatus: HTMLMetadata.completionStatus(in: metadataHTML) ?? HTMLMetadata.completionStatus(in: html),
            seasons: PublicSeasonMetadataMerger.merge(primary: detailSeasons, supplement: shareSeasons)
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

    private func requestHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<400 ~= httpResponse.statusCode else {
            throw PublicMetadataError.invalidResponse
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private enum PortraitCoverProbe {
    static func distinctPortraits(from candidates: [CoverImageCandidate]) async -> [VerifiedCoverCandidate] {
        let candidatesToInspect = Array(candidates.prefix(24))
        let inspected = await withTaskGroup(of: (Int, VerifiedCoverCandidate?).self) { group in
            for (index, candidate) in candidatesToInspect.enumerated() {
                group.addTask {
                    (index, await inspect(candidate))
                }
            }

            var values: [(Int, VerifiedCoverCandidate)] = []
            for await (index, result) in group {
                if let result { values.append((index, result)) }
            }
            return values.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return CoverCandidateDeduplicator.uniquePortraits(inspected, limit: 8)
    }

    private static func inspect(_ candidate: CoverImageCandidate) async -> VerifiedCoverCandidate? {
        guard let url = URL(string: candidate.url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png,image/webp,image/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              data.count <= 12_000_000,
              let httpResponse = response as? HTTPURLResponse,
              200..<400 ~= httpResponse.statusCode,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32
                ] as CFDictionary
              ),
              Double(image.height) > Double(image.width) * 1.05,
              let fingerprint = CoverImageFingerprint.hash(image: image) else {
            return nil
        }
        return VerifiedCoverCandidate(candidate: candidate, width: image.width, height: image.height, fingerprint: fingerprint)
    }
}

struct VerifiedCoverCandidate: Sendable {
    let candidate: CoverImageCandidate
    let width: Int
    let height: Int
    let fingerprint: UInt64
}

enum CoverCandidateDeduplicator {
    static func uniquePortraits(_ candidates: [VerifiedCoverCandidate], limit: Int = 8) -> [VerifiedCoverCandidate] {
        var fingerprints: [UInt64] = []
        var result: [VerifiedCoverCandidate] = []
        for candidate in candidates where candidate.height > candidate.width {
            guard !fingerprints.contains(where: { CoverImageFingerprint.isDuplicate($0, candidate.fingerprint) }) else {
                continue
            }
            fingerprints.append(candidate.fingerprint)
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}

enum CoverImageFingerprint {
    static func hash(image: CGImage) -> UInt64? {
        var grayscale = [UInt8](repeating: 0, count: 64)
        let rendered = grayscale.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard rendered else { return nil }
        return hash(grayscaleSamples: grayscale)
    }

    static func hash(grayscaleSamples: [UInt8]) -> UInt64? {
        guard grayscaleSamples.count == 64 else { return nil }
        let threshold = grayscaleSamples.sorted()[32]
        return grayscaleSamples.reduce(UInt64(0)) { result, value in
            (result << 1) | (value >= threshold ? 1 : 0)
        }
    }

    static func isDuplicate(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        (lhs ^ rhs).nonzeroBitCount <= 5
    }
}

enum CoverImageOrientation: Sendable, Equatable {
    case portrait
    case landscape
    case unknown
}

enum CoverImageProbe {
    static func orientation(urlString: String) async -> CoverImageOrientation {
        guard let url = URL(string: urlString) else { return .unknown }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200..<400 ~= httpResponse.statusCode,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return .unknown
        }
        if height.doubleValue > width.doubleValue * 1.05 { return .portrait }
        if width.doubleValue > height.doubleValue * 1.05 { return .landscape }
        return .unknown
    }

    static func isPortrait(urlString: String) async -> Bool {
        await orientation(urlString: urlString) == .portrait
    }
}

enum HTMLMetadata {
    static func officialDetailURL(in html: String) -> URL? {
        let patterns = [
            #"[\"']video_id[\"']\s*:\s*[\"']?(\d{10,})[\"']?"#,
            #"video_id%22%3A%22(\d{10,})%22"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let valueRange = Range(match.range(at: 1), in: html),
                  var components = URLComponents(string: "https://hongguoduanju.com/detail") else {
                continue
            }
            components.queryItems = [URLQueryItem(name: "series_id", value: String(html[valueRange]))]
            return components.url
        }
        return nil
    }

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
        currentSeriesDetailValue(for: keys, in: html).flatMap(numberValue)
    }

    static func currentSeriesDetailCompactCountText(for keys: [String], in html: String) -> String? {
        guard let detail = currentSeriesDetail(in: html),
              let count = intValue(for: keys, in: detail), count >= 0 else {
            return nil
        }

        if count >= 100_000_000 { return compactCount(Double(count) / 100_000_000, unit: "亿") }
        if count >= 10_000 { return compactCount(Double(count) / 10_000, unit: "万") }
        return String(count)
    }

    static func selectedCoverURL(in html: String, baseURL: URL, title: String?) -> String? {
        let candidates = coverCandidates(in: html, baseURL: baseURL)
        return CoverURLSelector.preferred(candidates, title: title)?.url
    }

    static func currentSeriesSocialInfoValue(
        for keys: [String],
        nestedKeys: [String] = [],
        in html: String
    ) -> String? {
        guard let socialInfo = currentSeriesSocialInfo(in: html) else { return nil }
        for nestedKey in nestedKeys {
            guard let nested = value(for: nestedKey, in: socialInfo) as? [String: Any] else { continue }
            if let text = firstScalarText(for: keys, in: nested) { return text }
        }
        return firstScalarText(for: keys, in: socialInfo)
    }

    static func currentSeriesSocialInfoDecimalValue(
        for keys: [String],
        nestedKeys: [String] = [],
        in html: String
    ) -> Double? {
        currentSeriesSocialInfoValue(for: keys, nestedKeys: nestedKeys, in: html).flatMap(numberValue)
    }

    static func currentSeriesSocialInfoIntValue(for keys: [String], in html: String) -> Int? {
        guard let value = currentSeriesSocialInfoValue(for: keys, in: html),
              let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return number
    }

    static func officialRating(in html: String) -> Double? {
        currentSeriesSocialInfoDecimalValue(
            for: ["rating", "score", "series_score", "official_score"],
            in: html
        ) ?? currentSeriesDetailDecimalValue(
            for: ["rating", "score", "series_score", "official_score"],
            in: html
        ) ?? decimalValue(for: ["rating", "og:rating"], in: html)
    }

    static func officialHeatText(in html: String) -> String? {
        currentSeriesSocialInfoValue(
            for: ["text", "heat", "hot_text", "hot_value", "play_count", "total_play_count", "view_count"],
            nestedKeys: ["hot_score_data"],
            in: html
        ) ?? currentSeriesDetailValue(
            for: ["heat", "heat_score", "hot_value", "play_count", "total_play_count", "view_count"],
            in: html
        ) ?? currentSeriesDetailCompactCountText(for: ["popularity"], in: html)
            ?? currentSeriesDetailValue(for: ["popularity"], in: html)
            ?? value(for: ["heat", "og:heat"], in: html)
    }

    static func officialHeatText(in html: String, fallbackHTML: String) -> String? {
        officialHeatText(in: html) ?? officialHeatText(in: fallbackHTML)
    }

    static func officialHeatScore(in html: String) -> Double? {
        if let text = currentSeriesSocialInfoValue(
            for: ["text", "heat", "hot_text", "hot_value", "play_count", "total_play_count", "view_count"],
            nestedKeys: ["hot_score_data"],
            in: html
        ), let number = numberValue(text) {
            return number
        }

        if let score = currentSeriesSocialInfoDecimalValue(
            for: ["value", "score", "hot_score", "hot_value"],
            nestedKeys: ["hot_score_data"],
            in: html
        ) {
            return score
        }

        if let detailHeat = currentSeriesDetailValue(
            for: ["heat", "heat_score", "hot_value", "play_count", "total_play_count", "view_count", "popularity"],
            in: html
        ), let number = numberValue(detailHeat) {
            return number
        }

        return value(for: ["heat", "og:heat"], in: html).flatMap(numberValue)
    }

    static func officialHeatScore(in html: String, fallbackHTML: String) -> Double? {
        officialHeatScore(in: html) ?? officialHeatScore(in: fallbackHTML)
    }

    private static func currentSeriesDetail(in html: String) -> [String: Any]? {
        guard let routerData = routerData(in: html),
              let loaderData = routerData["loaderData"] as? [String: Any] else {
            return nil
        }

        if let detailPage = loaderData["detail_page"] as? [String: Any],
           let seriesDetail = detailPage["seriesDetail"] as? [String: Any] {
            return seriesDetail
        }

        return currentVideoAnimationSharePage(in: routerData)?["series_data"] as? [String: Any]
    }

    private static func currentVideoAnimationSharePage(in html: String) -> [String: Any]? {
        guard let routerData = routerData(in: html) else { return nil }
        return currentVideoAnimationSharePage(in: routerData)
    }

    private static func currentVideoAnimationSharePage(in routerData: [String: Any]) -> [String: Any]? {
        guard let loaderData = routerData["loaderData"] as? [String: Any],
              let sharePage = loaderData["video-animation-share_page"] as? [String: Any] else {
            return nil
        }
        return sharePage["pageData"] as? [String: Any]
    }

    private static func isVideoAnimationSharePage(in html: String) -> Bool {
        currentVideoAnimationSharePage(in: html)?["series_data"] is [String: Any]
    }

    private static func currentSeriesSocialInfo(in html: String) -> [String: Any]? {
        guard let routerData = routerData(in: html),
              let loaderData = routerData["loaderData"] as? [String: Any],
              let detailPage = loaderData["detail_page"] as? [String: Any],
              let socialInfo = detailPage["seriesSocialInfo"] as? [String: Any] else {
            return nil
        }
        return socialInfo
    }

    static func completionStatus(in html: String) -> String? {
        let keys = [
            "is_finished", "is_finish", "is_end", "is_complete", "completed",
            "finish_status", "serial_status", "status"
        ]

        if let detail = currentSeriesDetail(in: html) {
            for key in keys {
                if let rawValue = value(for: key, in: detail),
                   let status = normalizedCompletionStatus(rawValue) {
                    return status
                }
            }
        }

        if let text = value(for: ["completion_status", "serial_status", "status"], in: html) {
            return normalizedCompletionStatus(text)
        }
        return nil
    }

    private static func normalizedCompletionStatus(_ rawValue: Any) -> String? {
        if let value = rawValue as? Bool {
            return value ? SeriesCompletionStatus.completed.rawValue : SeriesCompletionStatus.ongoing.rawValue
        }
        if let number = rawValue as? NSNumber, !isBooleanNSNumber(number) {
            return number.intValue == 0
                ? SeriesCompletionStatus.ongoing.rawValue
                : SeriesCompletionStatus.completed.rawValue
        }

        guard let text = scalarText(rawValue)?.lowercased() else { return nil }
        if text.contains("完结") || text.contains("已完") || text.contains("finished")
            || text.contains("complete") || text == "end" || text == "ended" {
            return SeriesCompletionStatus.completed.rawValue
        }
        if text.contains("未完") || text.contains("连载") || text.contains("更新")
            || text.contains("ongoing") || text.contains("serial") || text.contains("uncomplete") {
            return SeriesCompletionStatus.ongoing.rawValue
        }
        return nil
    }

    private static func firstScalarText(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let rawValue = value(for: key, in: dictionary), let text = scalarText(rawValue) {
                return text
            }
        }
        return nil
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
        if let number = rawValue as? NSNumber, !isBooleanNSNumber(number) {
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
        guard let value = value(for: keys, in: html) else {
            return nil
        }
        return numberValue(value)
    }

    private static func numberValue(_ rawValue: String) -> Double? {
        let value = rawValue.replacingOccurrences(of: ",", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range, in: value),
              let number = Double(String(value[range])) else {
            return nil
        }

        if value.contains("亿") { return number * 100_000_000 }
        if value.contains("万") { return number * 10_000 }
        return number
    }

    private static func compactCount(_ value: Double, unit: String) -> String {
        let rounded = value.rounded()
        let number = abs(value - rounded) < 0.000_001
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number)\(unit)"
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

        let currentCovers = currentSeriesDetailCovers(in: html, baseURL: baseURL)
        let rejectedVideoCoverURLs = Set(
            currentCovers
                .filter { $0.context.lowercased().contains("share-video-cover") }
                .map(\.url)
        )
        if !rejectedVideoCoverURLs.isEmpty {
            candidates = candidates.map { candidate in
                guard rejectedVideoCoverURLs.contains(candidate.url) else { return candidate }
                return CoverImageCandidate(
                    url: candidate.url,
                    context: candidate.context + " share-video-cover"
                )
            }
        }

        candidates.append(contentsOf: currentCovers.map { candidate in
            guard rejectedVideoCoverURLs.contains(candidate.url),
                  !candidate.context.lowercased().contains("share-video-cover") else {
                return candidate
            }
            return CoverImageCandidate(
                url: candidate.url,
                context: candidate.context + " share-video-cover"
            )
        })

        return candidates.filter { !isVideoFrameCandidate($0) }
    }

    // The SSR payload identifies the current work; videoList contains related works.
    static func currentSeriesDetailCover(
        in html: String,
        baseURL: URL
    ) -> CoverImageCandidate? {
        guard currentSeriesDetail(in: html) != nil else { return nil }

        return currentSeriesDetailCovers(in: html, baseURL: baseURL).first
    }

    private static func currentSeriesDetailCovers(
        in html: String,
        baseURL: URL
    ) -> [CoverImageCandidate] {
        guard let seriesDetail = currentSeriesDetail(in: html) else { return [] }

        let coverKeys = [
            "series_cover_fallback", "vertical_cover", "portrait_cover", "poster", "poster_url",
            "series_cover", "small_series_cover", "series_cover_uri", "series_cover_info",
            "cover", "cover_url"
        ]
        let isLandscapeShare = isVideoAnimationSharePage(in: html) && landscapeVideo(in: seriesDetail)
        var candidates: [CoverImageCandidate] = []

        for key in coverKeys {
            guard let rawValue = value(for: key, in: seriesDetail) else { continue }
            for rawCover in imageStrings(from: rawValue) {
                var value = unescape(rawCover)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("//") { value = "https:\(value)" }
                guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                    continue
                }

                let seriesName = (seriesDetail["series_name"] as? String) ?? (seriesDetail["title"] as? String) ?? ""
                let videoLikeKey = [
                    "series_cover", "small_series_cover", "series_cover_uri", "series_cover_info"
                ].contains(key.lowercased())
                let videoMarker = isLandscapeShare && videoLikeKey ? " share-video-cover" : ""
                let context = "official-current-series-cover key=\(key)\(videoMarker) seriesDetail series_name=\(seriesName)"
                candidates.append(CoverImageCandidate(url: url.absoluteString, context: context))
            }
        }

        return candidates
    }

    private static func imageStrings(from value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let dictionary = value as? [String: Any] {
            return ["url", "uri", "src", "image", "cover"]
                .compactMap { dictionary[$0] as? String }
        }
        if let array = value as? [Any] {
            return array.flatMap { imageStrings(from: $0) }
        }
        return []
    }

    private static func isVideoFrameCandidate(_ candidate: CoverImageCandidate) -> Bool {
        let value = "\(candidate.url) \(candidate.context)".lowercased()
        return [
            "first-frame", "first_frame", "video-frame", "video_frame",
            "snapshot", "screenshot", "video-still", "video_still",
            "share-video-cover", "episode-cover", "episode_cover", "horiz-cover", "horiz_cover",
            "play_url", "play-url"
        ].contains { value.contains($0) }
    }

    private static func landscapeVideo(in seriesDetail: [String: Any]) -> Bool {
        guard let videoMeta = value(for: "video_meta", in: seriesDetail) as? [String: Any],
              let width = intValue(for: ["width"], in: videoMeta),
              let height = intValue(for: ["height"], in: videoMeta) else {
            return false
        }
        return width > height
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
        let currentSeasons = currentSeriesSeason(in: html, baseURL: baseURL).map { [$0] } ?? []
        let structuredSeasons = PublicSeasonMetadataMerger.merge(
            primary: currentSeasons,
            supplement: relatedSeasons(in: html, baseURL: baseURL)
        )
        var unassignedEpisodes: [(number: Int, title: String?, url: String?, sourceVid: String)] = []

        // The SSR payload is authoritative for the current work. Avoid letting
        // unrelated navigation links create phantom seasons or episodes.
        if !structuredSeasons.isEmpty {
            return structuredSeasons
                .map { season in
                    var copy = season
                    copy.episodes.sort { $0.episodeNumber < $1.episodeNumber }
                    return copy
                }
                .sorted { $0.seasonNumber < $1.seasonNumber }
        }

        var seasonsByNumber: [Int: PublicSeasonMetadata] = [:]

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

    private static func currentSeriesSeason(in html: String, baseURL: URL) -> PublicSeasonMetadata? {
        guard let detail = currentSeriesDetail(in: html),
              let name = value(for: "series_name", in: detail).flatMap({ scalarText($0) })
                ?? value(for: "title", in: detail).flatMap({ scalarText($0) }) else {
            return nil
        }

        let seasonNumber = firstSeasonNumber(in: name) ?? 1
        let episodeCount = intValue(for: ["episode_cnt", "episode_count", "serial_count"], in: detail)
            ?? nestedIntValue(
                for: ["episode_cnt", "episode_total_cnt"],
                nestedKeys: ["series_episode_info"],
                in: detail
            )
            ?? 0
        let sourceURL = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)?.url?.absoluteString
        let routerData = routerData(in: html)
        let sharePage = routerData.flatMap { currentVideoAnimationSharePage(in: $0) }
        let listedVids = value(for: "vid_list", in: detail) as? [Any] ?? []
        let videoData = value(for: "video_data", in: detail) as? [String: Any] ?? [:]
        let indexedEpisodes = (value(for: "video_list", in: videoData) as? [[String: Any]] ?? [])
            .enumerated()
            .compactMap { index, item -> PublicEpisodeMetadata? in
                guard let sourceVid = firstScalarText(for: ["vid", "video_id", "source_vid"], in: item) else {
                    return nil
                }
                let episodeNumber = intValue(for: ["vid_index", "episode_number", "episode_num"], in: item)
                    ?? index + 1
                guard episodeNumber > 0 else { return nil }
                return PublicEpisodeMetadata(
                    sourceVid: sourceVid,
                    episodeNumber: episodeNumber,
                    title: firstScalarText(for: ["title", "video_name", "name"], in: item),
                    webURL: firstScalarText(for: ["web_url", "url", "share_url"], in: item)
                )
            }
            .sorted { $0.episodeNumber < $1.episodeNumber }
        let rawIDs = listedVids.isEmpty
            ? (sharePage.flatMap { value(for: "chapter_ids", in: $0) as? [Any] } ?? [])
            : listedVids
        let listedEpisodes = rawIDs.compactMap { scalarText($0) }.enumerated().map { index, sourceVid in
            PublicEpisodeMetadata(sourceVid: sourceVid, episodeNumber: index + 1, title: nil, webURL: nil)
        }
        let episodes = indexedEpisodes.isEmpty ? listedEpisodes : indexedEpisodes

        guard episodeCount > 0 || !episodes.isEmpty else { return nil }
        return PublicSeasonMetadata(
            seasonNumber: seasonNumber,
            title: "第\(seasonNumber)季",
            episodeCount: max(episodeCount, episodes.count),
            sourceURL: sourceURL,
            episodes: episodes
        )
    }

    private static func relatedSeasons(in html: String, baseURL: URL) -> [PublicSeasonMetadata] {
        guard let routerData = routerData(in: html),
              let loaderData = routerData["loaderData"] as? [String: Any],
              let detailPage = loaderData["detail_page"] as? [String: Any],
              let currentDetail = detailPage["seriesDetail"] as? [String: Any],
              let currentName = firstScalarText(for: ["series_name", "title", "name"], in: currentDetail) else {
            return []
        }

        let nestedVideoData = value(for: "video_data", in: detailPage) as? [String: Any]
        let videoList = detailPage["videoList"] as? [[String: Any]]
            ?? detailPage["video_list"] as? [[String: Any]]
            ?? nestedVideoData?["video_list"] as? [[String: Any]]
            ?? []

        let currentBase = seasonBaseName(currentName)
        return videoList.compactMap { item in
            guard let name = firstScalarText(for: ["series_name", "title", "name"], in: item),
                  seasonBaseName(name) == currentBase,
                  let seasonNumber = firstSeasonNumber(in: name),
                  let seriesID = firstScalarText(for: ["series_id", "book_id", "id"], in: item) else {
                return nil
            }

            let episodeCount = intValue(for: ["episode_cnt", "episode_count", "serial_count"], in: item)
                ?? nestedIntValue(for: ["episode_cnt", "episode_total_cnt"], nestedKeys: ["series_episode_info"], in: item)
                ?? 0
            let vidValues = (value(for: "vid_list", in: item) as? [Any] ?? [])
                .compactMap { scalarText($0) }
            let episodes = vidValues.enumerated().map { index, sourceVid in
                PublicEpisodeMetadata(sourceVid: sourceVid, episodeNumber: index + 1, title: nil, webURL: nil)
            }
            guard episodeCount > 0 || !episodes.isEmpty else { return nil }

            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
            components?.queryItems = [URLQueryItem(name: "series_id", value: seriesID)]
            return PublicSeasonMetadata(
                seasonNumber: seasonNumber,
                title: TitleNormalizer.normalize(name) ?? "第\(seasonNumber)季",
                episodeCount: max(episodeCount, episodes.count),
                sourceURL: components?.url?.absoluteString,
                episodes: episodes
            )
        }
    }

    private static func seasonBaseName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"第\s*[0-9一二三四五六七八九十百零〇两]+\s*季"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\bseason\s*[0-9]+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let number = firstNumber(in: value, patterns: [
            #"(?:第\s*)?([0-9]{1,3})\s*季"#,
            #"\bseason\s*([0-9]{1,3})\b"#,
            #"\bs([0-9]{1,3})\b"#
        ]) {
            return number
        }
        return TitleNormalizer.seasonNumber(value)
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

    private static func intValue(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            guard let rawValue = value(for: key, in: dictionary) else { continue }
            if let number = rawValue as? NSNumber, !isBooleanNSNumber(number) {
                return number.intValue
            }
            if let text = scalarText(rawValue), let number = Int(text) {
                return number
            }
        }
        return nil
    }

    private static func isBooleanNSNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func nestedIntValue(
        for keys: [String],
        nestedKeys: [String],
        in dictionary: [String: Any]
    ) -> Int? {
        for nestedKey in nestedKeys {
            guard let nested = value(for: nestedKey, in: dictionary) as? [String: Any] else { continue }
            if let number = intValue(for: keys, in: nested) { return number }
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
