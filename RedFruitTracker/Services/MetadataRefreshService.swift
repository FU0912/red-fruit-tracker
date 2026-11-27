import Foundation
import SwiftData

enum MetadataRefreshOutcome {
    case updated
    case alreadyRunning
}

@MainActor
enum MetadataRefreshService {
    private static var activeSeriesIDs = Set<String>()

    static func refresh(_ series: SeriesRecord, in context: ModelContext) async throws -> MetadataRefreshOutcome {
        let sourceID = series.sourceSeriesID
        guard activeSeriesIDs.insert(sourceID).inserted else { return .alreadyRunning }
        defer { activeSeriesIDs.remove(sourceID) }

        guard let sourceURL = series.sourceURL,
              let url = URL(string: sourceURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw PublicMetadataError.unsupportedURL
        }

        let metadata = try await PublicMetadataService.shared.fetch(from: url)
        try Task.checkCancellation()

        let seasons: [SeasonRecord]
        let episodes: [EpisodeRecord]
        if metadata.seasons.isEmpty {
            seasons = []
            episodes = []
        } else {
            seasons = try context.fetch(FetchDescriptor<SeasonRecord>(
                predicate: #Predicate<SeasonRecord> { $0.sourceSeriesID == sourceID }
            ))
            episodes = try context.fetch(FetchDescriptor<EpisodeRecord>(
                predicate: #Predicate<EpisodeRecord> { $0.sourceSeriesID == sourceID }
            ))
        }
        let hasSnapshotData = metadata.officialHeatScore != nil
            || !(metadata.officialHeatText?.isEmpty ?? true)
            || !metadata.seasons.isEmpty
        let previousSnapshot = hasSnapshotData
            ? try context.fetch(FetchDescriptor<OfficialSnapshot>(
                predicate: #Predicate<OfficialSnapshot> { $0.sourceSeriesID == sourceID },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
            )).first
            : nil

        let existingCover = series.coverURL
        let shouldReplaceCover = existingCover == nil || CoverURLSelector.shouldReplaceExisting(existingCover)
        let existingCoverIsLandscape = if let existingCover, !shouldReplaceCover {
            await CoverImageProbe.orientation(urlString: existingCover) == .landscape
        } else {
            false
        }
        try Task.checkCancellation()

        if shouldReplaceCover {
            if let cover = metadata.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines), !cover.isEmpty {
                series.coverURL = cover
            }
        } else if existingCoverIsLandscape {
            series.coverURL = metadata.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlankForMetadata
        }

        if series.intro.isEmpty, let intro = metadata.intro, !intro.isEmpty { series.intro = intro }
        if series.tagsText.isEmpty, let tags = metadata.tagsText, !tags.isEmpty { series.tagsText = tags }
        if let rating = metadata.officialRating { series.officialRating = rating }
        if let count = metadata.officialRatingCount { series.officialRatingCount = count }
        if let heatScore = metadata.officialHeatScore { series.officialHeatScore = heatScore }
        if let heatText = metadata.officialHeatText, !heatText.isEmpty { series.officialHeatText = heatText }
        if let onlineDate = metadata.onlineDate { series.onlineDate = onlineDate }
        if let completionStatus = metadata.completionStatus {
            series.completionStatus = completionStatus
            if completionStatus == SeriesCompletionStatus.completed.rawValue {
                series.isSerializing = false
                let personalDescriptor = FetchDescriptor<PersonalRecord>(
                    predicate: #Predicate<PersonalRecord> { $0.sourceSeriesID == sourceID }
                )
                if let personal = try context.fetch(personalDescriptor).first {
                    personal.followsUpdates = false
                    personal.followedAt = nil
                    personal.nextSeasonDate = nil
                    personal.nextSeasonDateUnknown = false
                    personal.updatedAt = .now
                }
                let notificationDescriptor = FetchDescriptor<UpdateNotificationRecord>(
                    predicate: #Predicate<UpdateNotificationRecord> { $0.sourceSeriesID == sourceID }
                )
                for notification in try context.fetch(notificationDescriptor) {
                    context.delete(notification)
                }
                UpdateNotificationService.cancelAppointment(seriesID: sourceID)
            }
        }
        series.updatedAt = .now

        var seasonsByNumber: [Int: SeasonRecord] = [:]
        for season in seasons { seasonsByNumber[season.seasonNumber] = season }
        var episodesByNumber: [String: EpisodeRecord] = [:]
        for episode in episodes {
            let key = "\(episode.seasonNumber)#\(episode.episodeNumber)"
            if episodesByNumber[key] == nil { episodesByNumber[key] = episode }
        }

        for metadataSeason in metadata.seasons {
            let season = seasonsByNumber[metadataSeason.seasonNumber]
                ?? SeasonRecord(sourceSeriesID: sourceID, seasonNumber: metadataSeason.seasonNumber)
            if seasonsByNumber[metadataSeason.seasonNumber] == nil {
                context.insert(season)
                seasonsByNumber[metadataSeason.seasonNumber] = season
            }
            if season.title.isEmpty { season.title = metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季" }
            season.episodeCount = SeasonEpisodeCount.latest(
                existing: season.episodeCount,
                reported: metadataSeason.episodeCount,
                observed: metadataSeason.episodes.count
            )
            season.sourceURL = metadataSeason.sourceURL ?? season.sourceURL ?? series.sourceURL
            season.updatedAt = .now

            for metadataEpisode in metadataSeason.episodes {
                let key = "\(metadataSeason.seasonNumber)#\(metadataEpisode.episodeNumber)"
                let episode = episodesByNumber[key] ?? EpisodeRecord(
                    sourceVid: "\(sourceID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                    sourceSeriesID: sourceID,
                    seasonNumber: metadataSeason.seasonNumber,
                    episodeNumber: metadataEpisode.episodeNumber
                )
                if episodesByNumber[key] == nil {
                    context.insert(episode)
                    episodesByNumber[key] = episode
                }
                if let title = metadataEpisode.title, !title.isEmpty { episode.title = title }
                if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
            }
        }

        upsertSnapshot(for: sourceID, metadata: metadata, previous: previousSnapshot, in: context)
        try context.saveAndNotifyCloudBackup()
        return .updated
    }

    private static func upsertSnapshot(
        for sourceID: String,
        metadata: PublicSeriesMetadata,
        previous: OfficialSnapshot?,
        in context: ModelContext
    ) {
        let hasHeat = metadata.officialHeatScore != nil || !(metadata.officialHeatText?.isEmpty ?? true)
        let hasSeasonCounts = !metadata.seasons.isEmpty
        guard hasHeat || hasSeasonCounts else { return }

        let unchangedHeat = metadata.officialHeatScore == nil || previous?.officialHeatScore == metadata.officialHeatScore
        let unchangedHeatText = metadata.officialHeatText?.isEmpty != false
            || previous?.officialHeatText == metadata.officialHeatText
        let expectedSeasonCount = hasSeasonCounts ? metadata.seasons.count : nil
        let expectedEpisodeCount = hasSeasonCounts
            ? metadata.seasons.map(\.episodeCount).reduce(0, +)
            : nil
        let unchangedSeasonCounts = !hasSeasonCounts
            || (previous?.seasonCount == expectedSeasonCount && previous?.episodeCount == expectedEpisodeCount)
        if previous != nil, unchangedHeat, unchangedHeatText, unchangedSeasonCounts { return }

        let snapshot = OfficialSnapshot(sourceSeriesID: sourceID)
        snapshot.officialHeatScore = metadata.officialHeatScore
        snapshot.officialHeatText = metadata.officialHeatText
        snapshot.seasonCount = expectedSeasonCount
        snapshot.episodeCount = expectedEpisodeCount
        context.insert(snapshot)
    }
}

private extension String {
    var nilIfBlankForMetadata: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
