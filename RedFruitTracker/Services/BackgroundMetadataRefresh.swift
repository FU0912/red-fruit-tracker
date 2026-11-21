import BackgroundTasks
import Foundation
import SwiftData

enum BackgroundMetadataRefresh {
    static let taskIdentifier = "com.f.redfruittracker.metadata-refresh"
    private static let cursorKey = "redFruitTracker.backgroundRefreshCursor"
    private static let progressKey = "redFruitTracker.backgroundRefreshProgress"
    private static let totalKey = "redFruitTracker.backgroundRefreshTotal"
    private static let completedKey = "redFruitTracker.backgroundRefreshCompleted"
    private static let failuresKey = "redFruitTracker.backgroundRefreshFailures"
    private static let inProgressKey = "redFruitTracker.backgroundRefreshInProgress"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(processingTask, container: container)
        }
        scheduleNextRun()
    }

    static func nextRun(after now: Date, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.hour = 4
        components.minute = 0
        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    static func scheduleNextRun(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextRun(after: now, calendar: calendar)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run(_ task: BGProcessingTask, container: ModelContainer) {
        scheduleNextRun()
        let operation = Task { @MainActor in
            do {
                try await refresh(container: container)
                task.setTaskCompleted(success: true)
            } catch is CancellationError {
                task.setTaskCompleted(success: false)
            } catch {
                task.setTaskCompleted(success: false)
            }
            scheduleNextRun()
        }
        task.expirationHandler = { operation.cancel() }
    }

    @MainActor
    private static func refresh(container: ModelContainer) async throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SeriesRecord>(
            sortBy: [
                SortDescriptor(\SeriesRecord.createdAt),
                SortDescriptor(\SeriesRecord.sourceSeriesID)
            ]
        )
        let series = try context.fetch(descriptor)
        let candidates = series.filter { item in
            guard let rawURL = item.sourceURL,
                  let url = URL(string: rawURL) else { return false }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        }
        guard !candidates.isEmpty else {
            UserDefaults.standard.set(false, forKey: inProgressKey)
            UserDefaults.standard.set("没有带网页链接的作品可更新", forKey: progressKey)
            UserDefaults.standard.set(0, forKey: totalKey)
            UserDefaults.standard.set(0, forKey: completedKey)
            UserDefaults.standard.set(0, forKey: failuresKey)
            return
        }

        let cursor = UserDefaults.standard.string(forKey: cursorKey)
        let previousIndex = cursor.flatMap { value in
            candidates.firstIndex(where: { $0.sourceSeriesID == value })
        }
        let startIndex = previousIndex.map { ($0 + 1) % candidates.count } ?? 0
        let ordered = Array(candidates.dropFirst(startIndex)) + Array(candidates.prefix(startIndex))
        var completed = 0
        var failures = 0
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: inProgressKey)
        defaults.set(candidates.count, forKey: totalKey)
        defaults.set(completed, forKey: completedKey)
        defaults.set(failures, forKey: failuresKey)
        defaults.set("后台更新中 0/\(candidates.count) 部", forKey: progressKey)

        for item in ordered {
            try Task.checkCancellation()
            guard let rawURL = item.sourceURL, let url = URL(string: rawURL) else { continue }

            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                try Task.checkCancellation()
                apply(metadata, to: item, context: context)
                try context.save()
                defaults.set(item.sourceSeriesID, forKey: cursorKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
            }
            completed += 1
            defaults.set(completed, forKey: completedKey)
            defaults.set(failures, forKey: failuresKey)
            defaults.set("后台更新中 \(completed)/\(candidates.count) 部 · 失败 \(failures) 部", forKey: progressKey)
        }

        defaults.removeObject(forKey: cursorKey)
        defaults.set(false, forKey: inProgressKey)
        defaults.set(
            "后台更新完成：已处理 \(completed) 部，失败 \(failures) 部",
            forKey: progressKey
        )
        RecentSeriesWidgetSnapshot.refresh(series: series)
    }

    @MainActor
    private static func apply(_ metadata: PublicSeriesMetadata, to item: SeriesRecord, context: ModelContext) {
        if let cover = metadata.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cover.isEmpty,
           item.coverURL == nil || CoverURLSelector.shouldReplaceExisting(item.coverURL) {
            item.coverURL = cover
        }
        if item.intro.isEmpty, let intro = metadata.intro, !intro.isEmpty { item.intro = intro }
        if item.tagsText.isEmpty, let tags = metadata.tagsText, !tags.isEmpty { item.tagsText = tags }
        if let rating = metadata.officialRating { item.officialRating = rating }
        if let count = metadata.officialRatingCount { item.officialRatingCount = count }
        if let heatScore = metadata.officialHeatScore { item.officialHeatScore = heatScore }
        if let heatText = metadata.officialHeatText, !heatText.isEmpty { item.officialHeatText = heatText }
        item.updatedAt = .now

        guard !metadata.seasons.isEmpty else {
            if metadata.officialHeatScore != nil || metadata.officialHeatText != nil {
                let snapshot = OfficialSnapshot(sourceSeriesID: item.sourceSeriesID)
                snapshot.officialHeatScore = metadata.officialHeatScore
                snapshot.officialHeatText = metadata.officialHeatText
                context.insert(snapshot)
            }
            return
        }

        let sourceID = item.sourceSeriesID
        let seasonDescriptor = FetchDescriptor<SeasonRecord>(
            predicate: #Predicate<SeasonRecord> { $0.sourceSeriesID == sourceID }
        )
        let episodeDescriptor = FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate<EpisodeRecord> { $0.sourceSeriesID == sourceID }
        )
        let existingSeasons = (try? context.fetch(seasonDescriptor)) ?? []
        let existingEpisodes = (try? context.fetch(episodeDescriptor)) ?? []

        for metadataSeason in metadata.seasons {
            let season = existingSeasons.first(where: { $0.seasonNumber == metadataSeason.seasonNumber })
                ?? SeasonRecord(sourceSeriesID: sourceID, seasonNumber: metadataSeason.seasonNumber)
            if !existingSeasons.contains(where: { $0 === season }) { context.insert(season) }
            if season.title.isEmpty { season.title = metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季" }
            season.episodeCount = SeasonEpisodeCount.latest(
                existing: season.episodeCount,
                reported: metadataSeason.episodeCount,
                observed: metadataSeason.episodes.count
            )
            season.sourceURL = metadataSeason.sourceURL ?? season.sourceURL ?? item.sourceURL
            season.updatedAt = .now

            for metadataEpisode in metadataSeason.episodes {
                let episode = existingEpisodes.first {
                    $0.seasonNumber == metadataSeason.seasonNumber
                        && $0.episodeNumber == metadataEpisode.episodeNumber
                } ?? EpisodeRecord(
                    sourceVid: "\(sourceID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                    sourceSeriesID: sourceID,
                    seasonNumber: metadataSeason.seasonNumber,
                    episodeNumber: metadataEpisode.episodeNumber
                )
                if !existingEpisodes.contains(where: { $0 === episode }) { context.insert(episode) }
                if let title = metadataEpisode.title, !title.isEmpty { episode.title = title }
                if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
            }
        }

        let snapshot = OfficialSnapshot(sourceSeriesID: sourceID)
        snapshot.officialHeatScore = metadata.officialHeatScore
        snapshot.officialHeatText = metadata.officialHeatText
        snapshot.seasonCount = metadata.seasons.count
        snapshot.episodeCount = metadata.seasons.map(\.episodeCount).reduce(0, +)
        context.insert(snapshot)
    }
}
