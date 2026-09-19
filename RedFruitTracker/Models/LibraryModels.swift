import Foundation
import SwiftData

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
