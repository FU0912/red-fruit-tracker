import Foundation
import SwiftData

enum RatingScale {
    static let maximum = 10.0

    static func normalized(_ value: Double) -> Double {
        let stepped = (value * 2).rounded() / 2
        return min(max(stepped, 0), maximum)
    }

    static func fromLegacyFiveStar(_ value: Double) -> Double {
        guard value >= 0, value <= 5 else { return normalized(value) }
        return normalized(value * 2)
    }
}

enum RatingPresentation: Equatable {
    case official(Double)
    case personal(Double)
    case unavailable

    static func resolve(officialRating: Double?, personalRating: Double?) -> Self {
        if let officialRating {
            return .official(officialRating)
        }
        if let personalRating {
            return .personal(personalRating)
        }
        return .unavailable
    }

    var text: String {
        switch self {
        case .official(let rating):
            return "官方 \(Self.formatted(rating))"
        case .personal(let rating):
            return "我的 \(Self.formattedTenPoint(rating))"
        case .unavailable:
            return "暂无评分"
        }
    }

    private static func formatted(_ rating: Double) -> String {
        String(format: "%.1f分", rating)
    }

    private static func formattedTenPoint(_ rating: Double) -> String {
        String(format: "%.1f / 10", rating)
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
    var updatedAt: Date

    init(sourceSeriesID: String) {
        self.sourceSeriesID = sourceSeriesID
        self.review = ""
        self.localShelfState = "unstarted"
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
    var episodeCount: Int?

    init(sourceSeriesID: String, capturedAt: Date = .now) {
        self.sourceSeriesID = sourceSeriesID
        self.capturedAt = capturedAt
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
