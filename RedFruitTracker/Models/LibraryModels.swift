import Foundation
import SwiftData

enum RatingScale {
    static let maximum = 10.0

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let rounded = (value * 10).rounded() / 10
        return min(max(rounded, 0), maximum)
    }

    static func fromLegacyFiveStar(_ value: Double) -> Double {
        guard value >= 0, value <= 5 else { return normalized(value) }
        return normalized(value * 2)
    }
}

enum LibrarySearch {
    static func matches(title: String, tags: String, intro: String, query: String) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return true }

        if keyword.hasPrefix("#") {
            let tag = String(keyword.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && tags.localizedCaseInsensitiveContains(tag)
        }

        return title.localizedCaseInsensitiveContains(keyword)
            || intro.localizedCaseInsensitiveContains(keyword)
    }
}

func tagValues(_ value: String) -> [String] {
    value
        .components(separatedBy: CharacterSet(charactersIn: ",，、|丨·/"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

enum SeriesCompletionStatus: String, CaseIterable, Identifiable {
    case completed
    case ongoing
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completed: return "已完结"
        case .ongoing: return "未完结"
        case .unknown: return "未选择"
        }
    }
}

enum ShelfState: String, CaseIterable, Identifiable {
    case unstarted
    case watching
    case finished
    case paused
    case dropped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unstarted: return "未开始"
        case .watching: return "观看中"
        case .finished: return "已看完"
        case .paused: return "暂时搁置"
        case .dropped: return "弃剧"
        }
    }

    var systemImage: String {
        switch self {
        case .unstarted: return "bookmark"
        case .watching: return "play.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .dropped: return "minus.circle.fill"
        }
    }

    static func resolve(_ rawValue: String?) -> Self {
        guard let rawValue, let state = Self(rawValue: rawValue) else {
            return .unstarted
        }
        return state
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case ongoing
    case unknown
    case followed
    case unstarted
    case watching
    case finished
    case paused
    case dropped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部作品"
        case .completed: return "已完结"
        case .ongoing: return "未完结"
        case .unknown: return "未选择"
        case .followed: return "追更/预约"
        case .unstarted: return "未开始"
        case .watching: return "观看中"
        case .finished: return "已看完"
        case .paused: return "暂时搁置"
        case .dropped: return "弃剧"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "books.vertical"
        case .completed: return "checkmark.seal"
        case .ongoing: return "clock"
        case .unknown: return "questionmark.circle"
        case .followed: return "bell.badge"
        case .unstarted: return "bookmark"
        case .watching: return "play.circle"
        case .finished: return "checkmark.circle"
        case .paused: return "pause.circle"
        case .dropped: return "minus.circle"
        }
    }
}

enum TagStatisticsPeriod: Hashable, Identifiable {
    case all
    case month
    case year(Int)

    var id: String {
        switch self {
        case .all: return "all"
        case .month: return "month"
        case .year(let year): return "year-\(year)"
        }
    }

    var title: String {
        switch self {
        case .all: return "全部"
        case .month: return "本月"
        case .year(_): return "按年"
        }
    }

    func includes(_ date: Date?, now: Date, calendar: Calendar) -> Bool {
        guard self != .all else { return true }
        guard let date else { return false }

        switch self {
        case .all:
            return true
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.contains(date) == true
        case .year(let selectedYear):
            return calendar.component(.year, from: date) == selectedYear
        }
    }
}

struct TagStatisticsSlice: Identifiable, Equatable {
    let tag: String
    let proportion: Double

    var id: String { tag }
}

struct TagStatisticsSummary: Equatable {
    let workCount: Int
    let slices: [TagStatisticsSlice]
}

enum TagStatistics {
    static func summary(
        series: [SeriesRecord],
        episodes: [EpisodeRecord],
        personalRecords: [PersonalRecord] = [],
        period: TagStatisticsPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TagStatisticsSummary {
        let watchedDatesBySeries = Dictionary(grouping: episodes.filter { $0.isWatched }, by: \.sourceSeriesID)
            .mapValues { $0.compactMap(\.watchedAt) }
        let personalBySeries = Dictionary(
            personalRecords.map { ($0.sourceSeriesID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let includedSeries = series.filter { record in
            guard period != .all else { return true }
            if let watchedDates = watchedDatesBySeries[record.sourceSeriesID], !watchedDates.isEmpty {
                return watchedDates.contains { period.includes($0, now: now, calendar: calendar) }
            }
            let fallbackDate = personalBySeries[record.sourceSeriesID]?.followedAt ?? record.createdAt
            return period.includes(fallbackDate, now: now, calendar: calendar)
        }

        guard !includedSeries.isEmpty else {
            return TagStatisticsSummary(workCount: 0, slices: [])
        }

        var contributions: [String: Double] = [:]
        for record in includedSeries {
            let tags = Array(Set(tagValues(record.tagsText))).sorted()
            let categories = tags.isEmpty ? ["未分类"] : tags
            let contribution = 1 / Double(categories.count)
            for tag in categories {
                contributions[tag, default: 0] += contribution
            }
        }

        let totalContribution = contributions.values.reduce(0, +)
        let slices = contributions
            .map { TagStatisticsSlice(tag: $0.key, proportion: $0.value / totalContribution) }
            .sorted {
                if $0.proportion == $1.proportion { return $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
                return $0.proportion > $1.proportion
            }
        return TagStatisticsSummary(workCount: includedSeries.count, slices: slices)
    }
}

enum HeatTrendGranularity {
    case day
    case week
    case month

    func bucketStart(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day: return calendar.startOfDay(for: date)
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .month: return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }
}

struct BatchRefreshProgress: Equatable {
    let total: Int
    private(set) var succeeded = 0
    private(set) var failed = 0
    var completed: Int { succeeded + failed }

    mutating func record(success: Bool) {
        guard completed < total else { return }
        if success { succeeded += 1 } else { failed += 1 }
    }
}

struct HeatTrendSample: Identifiable, Equatable {
    let date: Date
    let value: Double
    let highestObserved: Double
    let lowestObserved: Double
    let observationCount: Int

    var id: Date { date }
}

enum HeatTrendAggregation {
    static func samples(
        from snapshots: [OfficialSnapshot],
        granularity: HeatTrendGranularity,
        value: (OfficialSnapshot) -> Double?,
        calendar: Calendar = .current
    ) -> [HeatTrendSample] {
        let values = snapshots.compactMap { snapshot -> (Date, Double)? in
            guard let number = value(snapshot), number.isFinite, number >= 0 else { return nil }
            return (snapshot.capturedAt, number)
        }
        let groups = Dictionary(grouping: values) { item in
            granularity.bucketStart(for: item.0, calendar: calendar)
        }

        return groups.keys.sorted().compactMap { bucket in
            guard let points = groups[bucket]?.sorted(by: { $0.0 < $1.0 }),
                  let first = points.first,
                  let last = points.last else {
                return nil
            }
            let numbers = points.map(\.1)
            return HeatTrendSample(
                date: bucket,
                value: last.1,
                highestObserved: numbers.max() ?? last.1,
                lowestObserved: numbers.min() ?? last.1,
                observationCount: points.count
            )
        }
    }
}

enum RatingPresentation {
    static func officialText(_ rating: Double?) -> String {
        guard let rating else { return "官方暂无评分" }
        return "官方 \(formatted(rating))"
    }

    static func personalText(_ rating: Double?) -> String? {
        guard let rating else { return nil }
        return "我的 \(formatted(rating))"
    }

    private static func formatted(_ rating: Double) -> String {
        String(format: "%.1f", rating)
    }
}

struct SeasonCountChange: Identifiable, Equatable {
    let sourceSeriesID: String
    let capturedAt: Date
    let previousSeasonCount: Int?
    let currentSeasonCount: Int?
    let previousEpisodeCount: Int?
    let currentEpisodeCount: Int?

    var id: String {
        "\(sourceSeriesID)-\(capturedAt.timeIntervalSinceReferenceDate)"
    }
}

enum SeasonChangeHistory {
    static func changes(from snapshots: [OfficialSnapshot]) -> [SeasonCountChange] {
        Dictionary(grouping: snapshots, by: \.sourceSeriesID)
            .flatMap { sourceSeriesID, values -> [SeasonCountChange] in
                let ordered = values.sorted { $0.capturedAt < $1.capturedAt }
                guard let first = ordered.first else { return [SeasonCountChange]() }

                var previous = first
                var changes: [SeasonCountChange] = []
                for current in ordered.dropFirst() {
                    let seasonChanged = previous.seasonCount != nil
                        && current.seasonCount != nil
                        && previous.seasonCount != current.seasonCount
                    let episodeChanged = previous.episodeCount != nil
                        && current.episodeCount != nil
                        && previous.episodeCount != current.episodeCount
                    if seasonChanged || episodeChanged {
                        changes.append(SeasonCountChange(
                            sourceSeriesID: sourceSeriesID,
                            capturedAt: current.capturedAt,
                            previousSeasonCount: previous.seasonCount,
                            currentSeasonCount: current.seasonCount,
                            previousEpisodeCount: previous.episodeCount,
                            currentEpisodeCount: current.episodeCount
                        ))
                    }
                    previous = current
                }
                return changes
            }
            .sorted { $0.capturedAt > $1.capturedAt }
    }
}

enum EpisodeProgressSupport {
    static func selectedEpisode(_ value: Int, totalEpisodeCount: Int) -> Int? {
        guard value > 0, totalEpisodeCount > 0 else { return nil }
        return min(value, totalEpisodeCount)
    }

    static func summary(watchedCount: Int, totalEpisodeCount: Int) -> String {
        guard totalEpisodeCount > 0 else { return "集数待补" }
        return "已看 \(max(0, watchedCount)) / 共\(totalEpisodeCount)集"
    }
}

enum SeasonEpisodeCount {
    static func latest(existing: Int, reported: Int, observed: Int = 0) -> Int {
        if reported > 0 { return max(reported, observed) }
        return existing > 0 ? existing : observed
    }
}

enum SeriesLinkPolicy {
    static func primary(existing: String?, incoming: String?) -> String? {
        let current = existing?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let proposed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if isDetailPage(current), let proposed, !isDetailPage(proposed) {
            return proposed
        }
        return current ?? proposed
    }

    private static func isDetailPage(_ value: String?) -> Bool {
        guard let value,
              let components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              ["hongguoduanju.com", "www.hongguoduanju.com"].contains(host),
              components.path == "/detail" else {
            return false
        }
        return components.queryItems?.contains { $0.name.lowercased() == "series_id" } == true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@Model
final class SeriesRecord {
    @Attribute(.unique) var sourceSeriesID: String
    var title: String
    var sourceURL: String?
    var coverURL: String?
    var intro: String
    var tagsText: String
    var officialRating: Double?
    var officialRatingCount: Int?
    var officialHeatScore: Double?
    var officialHeatText: String?
    var completionStatus: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        sourceSeriesID: String,
        title: String,
        sourceURL: String? = nil,
        coverURL: String? = nil,
        intro: String = "",
        tagsText: String = "",
        officialRating: Double? = nil,
        officialRatingCount: Int? = nil,
        officialHeatScore: Double? = nil,
        officialHeatText: String? = nil,
        completionStatus: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.sourceSeriesID = sourceSeriesID
        self.title = title
        self.sourceURL = sourceURL
        self.coverURL = coverURL
        self.intro = intro
        self.tagsText = tagsText
        self.officialRating = officialRating
        self.officialRatingCount = officialRatingCount
        self.officialHeatScore = officialHeatScore
        self.officialHeatText = officialHeatText
        self.completionStatus = completionStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SeasonRecord {
    @Attribute(.unique) var sourceSeasonKey: String
    var sourceSeriesID: String
    var seasonNumber: Int
    var title: String
    var episodeCount: Int
    var sourceURL: String?
    var myRating: Double?
    var review: String = ""
    var updatedAt: Date

    init(
        sourceSeriesID: String,
        seasonNumber: Int,
        title: String = "",
        episodeCount: Int = 0,
        sourceURL: String? = nil,
        myRating: Double? = nil,
        review: String = ""
    ) {
        self.sourceSeasonKey = "\(sourceSeriesID)#\(seasonNumber)"
        self.sourceSeriesID = sourceSeriesID
        self.seasonNumber = seasonNumber
        self.title = title
        self.episodeCount = episodeCount
        self.sourceURL = sourceURL
        self.myRating = myRating
        self.review = review
        self.updatedAt = .now
    }
}

@Model
final class EpisodeRecord {
    @Attribute(.unique) var sourceVid: String
    var sourceSeriesID: String
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String
    var webURL: String?
    var isWatched: Bool
    var watchedAt: Date?

    init(
        sourceVid: String,
        sourceSeriesID: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String = "",
        webURL: String? = nil,
        isWatched: Bool = false,
        watchedAt: Date? = nil
    ) {
        self.sourceVid = sourceVid
        self.sourceSeriesID = sourceSeriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.webURL = webURL
        self.isWatched = isWatched
        self.watchedAt = watchedAt
    }
}

@Model
final class PersonalRecord {
    @Attribute(.unique) var sourceSeriesID: String
    var currentSeasonNumber: Int?
    var currentEpisodeNumber: Int?
    var myRating: Double?
    var review: String
    var localShelfState: String
    /// User intent is separate from the viewing state. A work can be paused or
    /// finished while still being followed for a future season or update.
    var followsUpdates: Bool = false
    var followedAt: Date?
    var nextSeasonDate: Date?
    var updatedAt: Date

    init(sourceSeriesID: String) {
        self.sourceSeriesID = sourceSeriesID
        self.review = ""
        self.localShelfState = "unstarted"
        self.followsUpdates = false
        self.followedAt = nil
        self.nextSeasonDate = nil
        self.updatedAt = .now
    }
}

@Model
final class OfficialSnapshot {
    var sourceSeriesID: String
    var capturedAt: Date
    var officialRating: Double?
    var officialRatingCount: Int?
    var officialHeatScore: Double?
    var officialHeatText: String?
    var likeCount: Int?
    var favoriteCount: Int?
    var reviewCount: Int?
    var seasonCount: Int?
    var episodeCount: Int?

    init(sourceSeriesID: String, capturedAt: Date = .now) {
        self.sourceSeriesID = sourceSeriesID
        self.capturedAt = capturedAt
    }

    func clearLegacyRatingTrend() {
        officialRating = nil
        officialRatingCount = nil
    }
}

@Model
final class ImportInboxItem {
    @Attribute(.unique) var originalURL: String
    var importedAt: Date
    var status: String
    var failureMessage: String?

    init(originalURL: String, status: String = "pending") {
        self.originalURL = originalURL
        self.importedAt = .now
        self.status = status
    }
}
