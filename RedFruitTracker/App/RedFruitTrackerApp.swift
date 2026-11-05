import Foundation
import SwiftData
import SwiftUI

@main
struct RedFruitTrackerApp: App {
    private let modelContainer: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let schema = Schema([
            SeriesRecord.self,
            SeasonRecord.self,
            EpisodeRecord.self,
            PersonalRecord.self,
            OfficialSnapshot.self,
            ImportInboxItem.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: arguments.contains("--ui-testing")
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            if !arguments.contains("--ui-testing") {
                Self.migrateLegacyRatings(in: container.mainContext)
            }
            if arguments.contains("--ui-testing-fixture") {
                Self.insertUITestFixture(into: container.mainContext)
            }
            if arguments.contains("--ui-testing-order") {
                let older = SeriesRecord(
                    sourceSeriesID: "order-older", title: "先添加后更新",
                    createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 300)
                )
                let newer = SeriesRecord(
                    sourceSeriesID: "order-newer", title: "后添加的作品",
                    createdAt: Date(timeIntervalSince1970: 200),
                    updatedAt: Date(timeIntervalSince1970: 200)
                )
                container.mainContext.insert(older)
                container.mainContext.insert(newer)
                try? container.mainContext.save()
            }
        } catch {
            fatalError("Unable to create the local model container: \(error)")
        }
    }

    private static func migrateLegacyRatings(in context: ModelContext) {
        let key = "redFruitTracker.ratingScaleMigratedToTen.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        do {
            let personalRecords = try context.fetch(FetchDescriptor<PersonalRecord>())
            let seasons = try context.fetch(FetchDescriptor<SeasonRecord>())
            for record in personalRecords {
                if let rating = record.myRating {
                    record.myRating = RatingScale.fromLegacyFiveStar(rating)
                }
            }
            for season in seasons {
                if let rating = season.myRating {
                    season.myRating = RatingScale.fromLegacyFiveStar(rating)
                }
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Retry on the next launch if the store is temporarily unavailable.
        }
    }

    private static func insertUITestFixture(into context: ModelContext) {
        let sourceID = "ui-fixture-series"
        let series = SeriesRecord(
            sourceSeriesID: sourceID,
            title: "反派二代目，女主全都坏掉了",
            sourceURL: "https://example.com/red-fruit-fixture",
            intro: "苏沐穿进修仙世界，一世扮演恶毒反派，拼尽全力推动剧情，只求被女主一剑斩杀完成任务重返现实。可濒死之际，他却意外发现所有命运都已经改变。",
            tagsText: "修仙,爽剧,穿越,系统,异界",
            officialRating: 8.8,
            officialHeatText: "3930万",
            completionStatus: SeriesCompletionStatus.ongoing.rawValue
        )
        context.insert(series)

        let season = SeasonRecord(
            sourceSeriesID: sourceID,
            seasonNumber: 1,
            title: "第1季",
            episodeCount: 189,
            sourceURL: "https://example.com/red-fruit-fixture/season-1"
        )
        context.insert(season)

        for number in 1...7 {
            context.insert(EpisodeRecord(
                sourceVid: "\(sourceID)#s1#e\(number)",
                sourceSeriesID: sourceID,
                seasonNumber: 1,
                episodeNumber: number,
                webURL: "https://example.com/red-fruit-fixture/season-1/episode-\(number)",
                isWatched: number == 1,
                watchedAt: number == 1 ? .now : nil
            ))
        }

        let personal = PersonalRecord(sourceSeriesID: sourceID)
        personal.currentSeasonNumber = 1
        personal.currentEpisodeNumber = 1
        personal.localShelfState = "watching"
        personal.followsUpdates = true
        personal.followedAt = .now
        personal.myRating = 8
        personal.review = "节奏明快，设定很有趣。"
        context.insert(personal)

        for index in 2...5 {
            let extraID = "ui-fixture-series-\(index)"
            let date = Date(timeIntervalSinceNow: TimeInterval(-index * 60))
            context.insert(SeriesRecord(
                sourceSeriesID: extraID,
                title: "UI 测试作品 \(index)",
                tagsText: "测试,漫剧",
                officialHeatText: "\(index * 100)万",
                createdAt: date,
                updatedAt: date
            ))
            context.insert(SeasonRecord(
                sourceSeriesID: extraID,
                seasonNumber: 1,
                title: "第1季",
                episodeCount: index * 10
            ))
        }

        try? context.save()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
