import XCTest
import SwiftData
@testable import RedFruitTracker

final class LibraryModelTests: XCTestCase {
    func testTextDraftBufferDoesNotCommitEveryKeystroke() {
        var buffer = TextDraftBuffer("初始点评")

        for value in ["初始点评。", "初始点评。节", "初始点评。节奏", "初始点评。节奏很快"] {
            buffer.update(value)
        }

        XCTAssertEqual(buffer.committed, "初始点评")
        XCTAssertEqual(buffer.commit(), "初始点评。节奏很快")
        XCTAssertNil(buffer.commit())
    }

    func testBatchRefreshProgressTracksSuccessAndFailureWithoutExceedingTotal() {
        var progress = BatchRefreshProgress(total: 2)
        progress.record(success: true)
        progress.record(success: false)
        progress.record(success: true)

        XCTAssertEqual(progress.completed, 2)
        XCTAssertEqual(progress.succeeded, 1)
        XCTAssertEqual(progress.failed, 1)
    }

    func testSeriesKeepsExternalIdentifierAndMetadata() {
        let record = SeriesRecord(
            sourceSeriesID: "7680187265020070937",
            title: "测试漫剧",
            sourceURL: "https://example.com/series/7680187265020070937",
            coverURL: "https://example.com/cover.jpg",
            tagsText: "修仙,爽剧",
            officialRating: 9.0,
            officialHeatText: "6859万"
        )

        XCTAssertEqual(record.sourceSeriesID, "7680187265020070937")
        XCTAssertEqual(record.title, "测试漫剧")
        XCTAssertEqual(record.sourceURL, "https://example.com/series/7680187265020070937")
        XCTAssertEqual(record.coverURL, "https://example.com/cover.jpg")
        XCTAssertEqual(record.tagsText, "修仙,爽剧")
        XCTAssertEqual(record.officialRating, 9.0)
        XCTAssertEqual(record.officialHeatText, "6859万")
    }

    func testLegacyOfficialRatingTrendValuesCanBeClearedWithoutTouchingHeat() {
        let snapshot = OfficialSnapshot(sourceSeriesID: "series")
        snapshot.officialRating = 9.2
        snapshot.officialRatingCount = 1200
        snapshot.officialHeatScore = 36_000_000

        snapshot.clearLegacyRatingTrend()

        XCTAssertNil(snapshot.officialRating)
        XCTAssertNil(snapshot.officialRatingCount)
        XCTAssertEqual(snapshot.officialHeatScore, 36_000_000)
    }

    func testEpisodeProgressCanBeMarkedWatched() {
        let episode = EpisodeRecord(
            sourceVid: "vid-1",
            sourceSeriesID: "series-1",
            seasonNumber: 2,
            episodeNumber: 17
        )

        XCTAssertFalse(episode.isWatched)
        episode.isWatched = true
        episode.watchedAt = Date(timeIntervalSince1970: 123)

        XCTAssertTrue(episode.isWatched)
        XCTAssertEqual(episode.watchedAt, Date(timeIntervalSince1970: 123))
    }

    func testMixedShareTextExtractsURL() {
        let text = "我在红果漫剧看到一部不错的作品，分享给你：https://example.com/series/123?from=share。"

        XCTAssertEqual(
            URLExtractor.firstURL(in: text)?.absoluteString,
            "https://example.com/series/123?from=share"
        )
    }

    func testShareTextPreservesLoRoSSchemeParamsAndHTMLAmpersand() {
        let text = "https://kylin.hainanyuyue.com/LoRoS?schemeParams=%7B%22vid%22%3A%22123%22%7D&amp;from=share"

        XCTAssertEqual(
            URLExtractor.firstURL(in: text)?.absoluteString,
            "https://kylin.hainanyuyue.com/LoRoS?schemeParams=%7B%22vid%22%3A%22123%22%7D&from=share"
        )
    }

    func testTitleNormalizerRemovesRedFruitBranding() {
        XCTAssertEqual(TitleNormalizer.normalize("红果漫剧：《仙途归来》 - 红果"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("《仙途归来》 | 红果短剧"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("免费看片《仙途归来》"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("女主全都坏掉免费观看《仙途归来》"), "仙途归来")
    }

    func testSeriesIdentityMergesChineseSeasonSuffixes() {
        let titles = [
            "天幕直播：古人每周来我家",
            "天幕直播：古人每周来我家第二季",
            "天幕直播：古人每周来我家第三季"
        ]

        XCTAssertEqual(
            Set(titles.compactMap { TitleNormalizer.seriesKey($0) }).count,
            1
        )
        XCTAssertEqual(
            TitleNormalizer.seriesTitle("天幕直播：古人每周来我家第二季"),
            "天幕直播：古人每周来我家"
        )
        XCTAssertEqual(TitleNormalizer.seasonNumber("天幕直播：古人每周来我家第二季"), 2)
        XCTAssertEqual(TitleNormalizer.seasonNumber("天幕直播：古人每周来我家第三季"), 3)
    }

    func testSeriesImportMatcherFindsExistingWorkByBaseTitle() {
        let firstURL = URL(string: "https://kylin.hainanyuyue.com/s/GXf3C13NXeQ/")!
        let secondURL = URL(string: "https://kylin.hainanyuyue.com/s/vOnryac5EoE/")!
        let firstIdentity = SeriesImportIdentity(title: "天幕直播：古人每周来我家", fallbackURL: firstURL)
        let secondIdentity = SeriesImportIdentity(title: "天幕直播：古人每周来我家第二季", fallbackURL: secondURL)
        let existing = SeriesRecord(
            sourceSeriesID: firstIdentity.sourceID,
            title: firstIdentity.baseTitle,
            sourceURL: firstURL.absoluteString
        )

        XCTAssertEqual(firstIdentity.sourceID, secondIdentity.sourceID)
        XCTAssertTrue(SeriesImportMatcher.matches(existing, identity: secondIdentity))
    }

    @MainActor
    func testSeriesRecordLookupUsesCanonicalIDAndFallsBackToExactBaseTitle() throws {
        let schema = Schema([SeriesRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let firstURL = URL(string: "https://example.com/series/first")!
        let firstIdentity = SeriesImportIdentity(title: "第一部漫剧", fallbackURL: firstURL)
        let canonicalRecord = SeriesRecord(
            sourceSeriesID: firstIdentity.sourceID,
            title: "被改过的显示名称"
        )
        let secondURL = URL(string: "https://example.com/series/second")!
        let secondIdentity = SeriesImportIdentity(title: "第二部漫剧第二季", fallbackURL: secondURL)
        let legacyRecord = SeriesRecord(
            sourceSeriesID: "legacy-second-series-id",
            title: secondIdentity.baseTitle
        )
        context.insert(canonicalRecord)
        context.insert(legacyRecord)
        try context.save()

        XCTAssertTrue(try SeriesRecordLookup.existing(matching: firstIdentity, in: context) === canonicalRecord)
        XCTAssertTrue(try SeriesRecordLookup.existing(matching: secondIdentity, in: context) === legacyRecord)
    }

    func testThreeManjuSharePagesKeepTheirOwnSeasonMetadata() {
        let pages = [
            ("天幕直播：古人每周来我家", 148, "41878916", "脑洞,穿越,系统,都市", "GXf3C13NXeQ"),
            ("天幕直播：古人每周来我家第二季", 168, "51710454", "脑洞,穿越,系统,都市", "vOnryac5EoE"),
            ("天幕直播：古人每周来我家第三季", 176, "3339296", "快穿,历史脑洞,时空之旅", "r9o11qGv1Rc")
        ]

        for (title, episodeCount, popularity, tags, token) in pages {
            let html = manjuShareFixture(
                title: title,
                episodeCount: episodeCount,
                popularity: popularity,
                tags: tags
            )
            let baseURL = URL(string: "https://kylin.hainanyuyue.com/s/\(token)/")!
            let metadataTitle = HTMLMetadata.currentSeriesDetailValue(for: ["title"], in: html)
            let seasons = HTMLMetadata.seasons(in: html, baseURL: baseURL)

            XCTAssertEqual(metadataTitle, title)
            XCTAssertEqual(seasons.map(\.seasonNumber), [TitleNormalizer.seasonNumber(title) ?? 1])
            XCTAssertEqual(seasons.first?.episodeCount, episodeCount)
            XCTAssertEqual(
                HTMLMetadata.currentSeriesDetailValue(for: ["category_list"], in: html),
                tags
            )
            XCTAssertEqual(
                HTMLMetadata.currentSeriesDetailDecimalValue(for: ["popularity"], in: html),
                Double(popularity)
            )
        }
    }

    func testEpisodeProgressAcceptsOneCurrentEpisodeWithoutBuildingAGrid() {
        XCTAssertEqual(
            EpisodeProgressSupport.selectedEpisode(6, totalEpisodeCount: 79),
            6
        )
        XCTAssertEqual(
            EpisodeProgressSupport.selectedEpisode(999, totalEpisodeCount: 79),
            79
        )
        XCTAssertNil(EpisodeProgressSupport.selectedEpisode(0, totalEpisodeCount: 79))
        XCTAssertNil(EpisodeProgressSupport.selectedEpisode(6, totalEpisodeCount: 0))
    }

    func testEpisodeProgressSummaryOnlyShowsTheSeasonTotal() {
        XCTAssertEqual(
            EpisodeProgressSupport.summary(watchedCount: 4, totalEpisodeCount: 79),
            "已看 4 / 共79集"
        )
        XCTAssertEqual(
            EpisodeProgressSupport.summary(watchedCount: 0, totalEpisodeCount: 0),
            "集数待补"
        )
    }

    func testReportedSeasonEpisodeCountCanRecordDecreasesWithoutErasingMissingValues() {
        XCTAssertEqual(SeasonEpisodeCount.latest(existing: 152, reported: 125), 125)
        XCTAssertEqual(SeasonEpisodeCount.latest(existing: 125, reported: 0), 125)
        XCTAssertEqual(SeasonEpisodeCount.latest(existing: 125, reported: 0, observed: 9), 125)
        XCTAssertEqual(SeasonEpisodeCount.latest(existing: 0, reported: 0, observed: 9), 9)
    }

    func testRatingPresentationKeepsOfficialAndPersonalScoresSeparate() {
        XCTAssertEqual(RatingPresentation.officialText(8.8), "官方 8.8")
        XCTAssertEqual(RatingPresentation.officialText(nil), "官方暂无评分")
        XCTAssertEqual(RatingPresentation.personalText(4), "我的 4.0")
        XCTAssertNil(RatingPresentation.personalText(nil))
    }

    func testRatingScaleUsesTenPointTenthStepAndMigratesLegacyStars() {
        XCTAssertEqual(RatingScale.normalized(8.24), 8.2)
        XCTAssertEqual(RatingScale.normalized(8.26), 8.3)
        XCTAssertEqual(RatingScale.normalized(11), 10)
        XCTAssertEqual(RatingScale.normalized(-2), 0)
        XCTAssertEqual(RatingScale.normalized(.infinity), 0)
        XCTAssertEqual(RatingScale.fromLegacyFiveStar(4), 8)
        XCTAssertEqual(RatingScale.fromLegacyFiveStar(5), 10)
        XCTAssertEqual(RatingScale.fromLegacyFiveStar(8), 8)
    }

    func testLibrarySearchUsesHashPrefixForTagsOnly() {
        XCTAssertTrue(LibrarySearch.matches(
            title: "恋爱作品",
            tags: "修仙,恋爱",
            intro: "一段故事",
            query: "恋爱"
        ))
        XCTAssertFalse(LibrarySearch.matches(
            title: "无关作品",
            tags: "恋爱",
            intro: "没有关键词",
            query: "恋爱"
        ))
        XCTAssertTrue(LibrarySearch.matches(
            title: "无关作品",
            tags: "修仙,恋爱",
            intro: "没有关键词",
            query: "#恋爱"
        ))
        XCTAssertFalse(LibrarySearch.matches(
            title: "恋爱作品",
            tags: "修仙",
            intro: "没有关键词",
            query: "#恋爱"
        ))
        XCTAssertFalse(LibrarySearch.matches(
            title: "任何作品",
            tags: "任意标签",
            intro: "",
            query: "#  "
        ))
    }

    func testDroppedShelfStateIsAStableRawValue() {
        let personal = PersonalRecord(sourceSeriesID: "series-1")
        personal.localShelfState = "dropped"

        XCTAssertEqual(personal.localShelfState, "dropped")
        XCTAssertEqual(ShelfState.resolve(personal.localShelfState), .dropped)
        XCTAssertEqual(ShelfState.resolve(nil), .unstarted)
        XCTAssertEqual(ShelfState.watching.title, "观看中")
    }

    func testFollowUpdatesIsIndependentFromShelfState() {
        let personal = PersonalRecord(sourceSeriesID: "series-1")
        personal.localShelfState = "finished"
        personal.followsUpdates = true
        personal.followedAt = Date(timeIntervalSince1970: 123)

        XCTAssertEqual(ShelfState.resolve(personal.localShelfState), .finished)
        XCTAssertTrue(personal.followsUpdates)
        XCTAssertEqual(personal.followedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(LibraryFilter.followed.title, "追更/预约")
    }

    func testTagStatisticsCountsEachWatchedWorkOnceAndSplitsMultipleTags() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let thisMonth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!

        let first = SeriesRecord(sourceSeriesID: "first", title: "第一部", tagsText: "穿越,校园")
        let second = SeriesRecord(sourceSeriesID: "second", title: "第二部", tagsText: "穿越")
        let third = SeriesRecord(sourceSeriesID: "third", title: "第三部", tagsText: "校园")
        let untagged = SeriesRecord(sourceSeriesID: "untagged", title: "未分类作品")
        let old = SeriesRecord(sourceSeriesID: "old", title: "旧作品", tagsText: "都市")
        let episodes = [
            EpisodeRecord(sourceVid: "first-1", sourceSeriesID: "first", seasonNumber: 1, episodeNumber: 1, isWatched: true, watchedAt: thisMonth),
            EpisodeRecord(sourceVid: "first-2", sourceSeriesID: "first", seasonNumber: 1, episodeNumber: 2, isWatched: true, watchedAt: thisMonth.addingTimeInterval(86_400)),
            EpisodeRecord(sourceVid: "second-1", sourceSeriesID: "second", seasonNumber: 1, episodeNumber: 1, isWatched: true, watchedAt: thisMonth),
            EpisodeRecord(sourceVid: "third-1", sourceSeriesID: "third", seasonNumber: 1, episodeNumber: 1, isWatched: true, watchedAt: lastMonth),
            EpisodeRecord(sourceVid: "untagged-1", sourceSeriesID: "untagged", seasonNumber: 1, episodeNumber: 1, isWatched: true, watchedAt: thisMonth),
            EpisodeRecord(sourceVid: "old-1", sourceSeriesID: "old", seasonNumber: 1, episodeNumber: 1, isWatched: true, watchedAt: lastMonth.addingTimeInterval(-366 * 86_400)),
            EpisodeRecord(sourceVid: "unwatched-1", sourceSeriesID: "second", seasonNumber: 1, episodeNumber: 3, isWatched: false, watchedAt: thisMonth)
        ]

        let summary = TagStatistics.summary(
            series: [first, second, third, untagged, old],
            episodes: episodes,
            period: .month,
            now: now,
            calendar: calendar
        )
        let proportions = Dictionary(uniqueKeysWithValues: summary.slices.map { ($0.tag, $0.proportion) })

        XCTAssertEqual(summary.workCount, 3)
        XCTAssertEqual(proportions["穿越"] ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(proportions["校园"] ?? 0, 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(proportions["未分类"] ?? 0, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(summary.slices.reduce(0) { $0 + $1.proportion }, 1, accuracy: 0.0001)

        let year = TagStatistics.summary(
            series: [first, second, third, untagged, old],
            episodes: episodes,
            period: .year(2026),
            now: now,
            calendar: calendar
        )
        let all = TagStatistics.summary(
            series: [first, second, third, untagged, old],
            episodes: episodes,
            period: .all,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(year.workCount, 4)
        XCTAssertEqual(all.workCount, 5)
    }

    func testTagStatisticsIncludesShelfWorksWithoutEpisodeProgress() {
        let first = SeriesRecord(sourceSeriesID: "first", title: "第一部", tagsText: "穿越,校园")
        let second = SeriesRecord(sourceSeriesID: "second", title: "第二部", tagsText: "穿越")

        let summary = TagStatistics.summary(series: [first, second], episodes: [], period: .all)
        let proportions = Dictionary(uniqueKeysWithValues: summary.slices.map { ($0.tag, $0.proportion) })

        XCTAssertEqual(summary.workCount, 2)
        XCTAssertEqual(proportions["穿越"] ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(proportions["校园"] ?? 0, 0.25, accuracy: 0.0001)
    }

    func testTagStatisticsIncludesTwoHundredShelfWorksWithoutEpisodeProgress() {
        let records = (0..<200).map { index in
            SeriesRecord(
                sourceSeriesID: "series-\(index)",
                title: "作品 \(index)",
                tagsText: index.isMultiple(of: 2) ? "穿越,校园" : "都市,恋爱"
            )
        }
        let input = TagStatistics.input(series: records, episodes: [])
        let summary = TagStatistics.summary(input: input, period: .all)

        XCTAssertEqual(summary.workCount, 200)
        XCTAssertEqual(summary.slices.reduce(0) { $0 + $1.proportion }, 1, accuracy: 0.0001)
        XCTAssertEqual(Set(summary.slices.map(\.tag)), Set(["恋爱", "穿越", "都市", "校园"]))
    }

    func testYearlyTagStatisticsUsesSelectedCalendarYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let record = SeriesRecord(sourceSeriesID: "series-1", title: "测试作品", tagsText: "穿越")
        let episodes = [
            EpisodeRecord(
                sourceVid: "2025",
                sourceSeriesID: "series-1",
                seasonNumber: 1,
                episodeNumber: 1,
                isWatched: true,
                watchedAt: calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))
            ),
            EpisodeRecord(
                sourceVid: "2024",
                sourceSeriesID: "series-1",
                seasonNumber: 1,
                episodeNumber: 2,
                isWatched: true,
                watchedAt: calendar.date(from: DateComponents(year: 2024, month: 6, day: 1))
            )
        ]

        let summary = TagStatistics.summary(
            series: [record],
            episodes: episodes,
            period: .year(2025),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.workCount, 1)
    }

    func testMonthlyTagStatisticsUsesFollowDateInsteadOfReviewEditDateForLegacyWork() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let addedEarlier = calendar.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        let followedThisMonth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let series = SeriesRecord(
            sourceSeriesID: "series-1",
            title: "测试作品",
            tagsText: "校园",
            createdAt: addedEarlier,
            updatedAt: now
        )
        let personal = PersonalRecord(sourceSeriesID: "series-1")
        personal.followedAt = followedThisMonth
        personal.updatedAt = addedEarlier

        let summary = TagStatistics.summary(
            series: [series],
            episodes: [],
            personalRecords: [personal],
            period: .month,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.workCount, 1)
        XCTAssertEqual(summary.slices.map(\.tag), ["校园"])
    }

    @MainActor
    func testNextSeasonDatePersistsOnPersonalRecord() throws {
        let schema = Schema([PersonalRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let personal = PersonalRecord(sourceSeriesID: "series-1")
        personal.followsUpdates = true
        personal.nextSeasonDate = date
        context.insert(personal)
        try context.save()

        let loaded = try context.fetch(FetchDescriptor<PersonalRecord>()).first
        XCTAssertEqual(loaded?.nextSeasonDate, date)
    }

    func testCompletionStatusIsManualAndDefaultsToUnselected() {
        let record = SeriesRecord(sourceSeriesID: "series-1", title: "测试作品")

        XCTAssertEqual(
            SeriesCompletionStatus(rawValue: record.completionStatus ?? "") ?? .unknown,
            .unknown
        )

        record.completionStatus = SeriesCompletionStatus.completed.rawValue
        XCTAssertEqual(record.completionStatus, "completed")
        XCTAssertEqual(SeriesCompletionStatus.completed.title, "已完结")
    }

    func testSeasonChangeHistoryKeepsPreviousAndCurrentCounts() {
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let unchanged = OfficialSnapshot(sourceSeriesID: "unchanged", capturedAt: firstDate)
        unchanged.seasonCount = 1
        unchanged.episodeCount = 12

        let first = OfficialSnapshot(sourceSeriesID: "series-1", capturedAt: firstDate)
        first.seasonCount = 2
        first.episodeCount = 125
        let second = OfficialSnapshot(sourceSeriesID: "series-1", capturedAt: secondDate)
        second.seasonCount = 3
        second.episodeCount = 128

        let changes = SeasonChangeHistory.changes(from: [second, unchanged, first])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.sourceSeriesID, "series-1")
        XCTAssertEqual(changes.first?.previousSeasonCount, 2)
        XCTAssertEqual(changes.first?.currentSeasonCount, 3)
        XCTAssertEqual(changes.first?.previousEpisodeCount, 125)
        XCTAssertEqual(changes.first?.currentEpisodeCount, 128)
        XCTAssertEqual(changes.first?.capturedAt, secondDate)
    }

    func testSeasonKeepsIndependentRatingAndReview() {
        let season = SeasonRecord(
            sourceSeriesID: "series-1",
            seasonNumber: 2,
            myRating: 4,
            review: "这一季节奏更紧。"
        )

        XCTAssertEqual(season.myRating, 4)
        XCTAssertEqual(season.review, "这一季节奏更紧。")
    }

    func testCoverSelectorPrefersCharacterPosterOverBanner() {
        let candidates = [
            CoverImageCandidate(
                url: "https://example.com/images/series-hero-banner.jpg",
                context: "<img class=\"hero-banner\" src=\"series-hero-banner.jpg\">"
            ),
            CoverImageCandidate(
                url: "https://example.com/images/main-character-poster.jpg",
                context: "<img class=\"poster cover\" alt=\"作品封面 主角\" src=\"main-character-poster.jpg\">"
            )
        ]

        XCTAssertEqual(
            CoverURLSelector.ranked(candidates).first?.url,
            "https://example.com/images/main-character-poster.jpg"
        )
    }

    func testCoverSelectorPrefersOfficialDetailPosterOverUIImages() {
        let title = "糯糯下山，师兄们都慌了第三季"
        let officialPoster = "https://p3-novel.byteimg.com/novel-pic/6fe7b369dfa0b42b98e254fa1d1e8e23~tplv-shrink:640:0.webp"
        let candidates = [
            CoverImageCandidate(
                url: "https://lf-dy-sourcecdn-tos.bytegecko.com/obj/lock.png",
                context: "<img class=\"m-lock\" src=\"lock.png\">"
            ),
            CoverImageCandidate(
                url: "https://p6-novel.byteimg.com/novel-pic/related.webp",
                context: "<img class=\"related-card\" src=\"related.webp\">"
            ),
            CoverImageCandidate(
                url: officialPoster,
                context: "<link rel=\"preload\" as=\"image\" href=\"\(officialPoster)\">"
            ),
            CoverImageCandidate(
                url: officialPoster,
                context: "<img class=\"image-main\" alt=\"\(title)\" fetchpriority=\"high\" src=\"\(officialPoster)\">"
            )
        ]

        XCTAssertEqual(
            CoverURLSelector.preferred(candidates, title: title)?.url,
            officialPoster
        )
    }

    func testCurrentSeriesCoverIsSelectedDirectlyBeforeGenericImageRanking() {
        let html = """
        <script>
        _ROUTER_DATA = {"loaderData":{"detail_page":{"seriesDetail":{"series_name":"当前作品第三季","series_cover":"https:\\u002F\\u002Fp3-novel.byteimg.com\\u002Fnovel-pic\\u002Fofficial-cover.image"}}}};
        </script>
        """

        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailCover(
                in: html,
                baseURL: URL(string: "https://hongguoduanju.com/detail")!
            )?.url,
            "https://p3-novel.byteimg.com/novel-pic/official-cover.image"
        )
    }

    func testOfficialDetailHTMLExtractsPreloadedAndStructuredPoster() {
        let title = "糯糯下山，师兄们都慌了第三季"
        let poster = "https://p3-novel.byteimg.com/novel-pic/poster.webp"
        let html = """
        <link rel="preload" as="image" href="\(poster)" type="image/webp">
        <script type="application/ld+json">
        {"@type":"TVSeries","name":"\(title)","image":"\(poster)"}
        </script>
        <img class="image-main" src="\(poster)" alt="\(title)" fetchpriority="high">
        <img class="m-lock" src="https://example.com/lock.png" alt="">
        """

        let candidates = HTMLMetadata.coverCandidates(
            in: html,
            baseURL: URL(string: "https://hongguoduanju.com/detail")!
        )

        XCTAssertEqual(
            CoverURLSelector.preferred(candidates, title: title)?.url,
            poster
        )
    }

    func testOfficialSeriesDetailCoverBeatsHeroAndRelatedWorkCovers() {
        let title = "当前作品第三季"
        let officialPoster = "https://p3-novel.byteimg.com/novel-pic/zzz-current.image"
        let html = """
        <link rel="preload" as="image" href="https://example.com/hero-background.jpg">
        <meta property="og:image" content="https://example.com/share-banner.jpg">
        <script>
        _ROUTER_DATA = {
          "loaderData": {
            "detail_page": {
              "videoList": [
                {"series_name":"相关作品","series_cover":"https://p3-novel.byteimg.com/novel-pic/aaa-related.image"}
              ],
              "seriesDetail": {
                "series_id":"current-series",
                "series_name":"\(title)",
                "series_cover":"\(officialPoster)"
              }
            }
          }
        };
        function runWindowFn() {}
        </script>
        """

        let candidates = HTMLMetadata.coverCandidates(
            in: html,
            baseURL: URL(string: "https://hongguoduanju.com/detail?series_id=current-series")!
        )

        XCTAssertEqual(
            CoverURLSelector.preferred(candidates, title: title)?.url,
            officialPoster
        )
    }

    func testOfficialDetailFixtureUsesCurrentSeriesCover() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = projectRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("RedFruitTrackerTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("hongguoduanju-series-detail.html")
        let html = try String(contentsOf: sampleURL, encoding: .utf8)
        let expected = "https://p3-novel.byteimg.com/novel-pic/6fe7b369dfa0b42b98e254fa1d1e8e23~tplv-shrink:640:0.image"
        let title = "糯糯下山，师兄们都慌了第三季"

        let candidates = HTMLMetadata.coverCandidates(
            in: html,
            baseURL: URL(string: "https://hongguoduanju.com/detail?series_id=7685224734895655960")!
        )

        XCTAssertEqual(
            CoverURLSelector.preferred(candidates, title: title)?.url,
            expected
        )
    }

    func testSharePageVideoIDBuildsOfficialDetailURL() throws {
        let html = #"<script>window.__DATA__={"video_id":"7675745080522574910"}</script>"#

        XCTAssertEqual(
            HTMLMetadata.officialDetailURL(in: html)?.absoluteString,
            "https://hongguoduanju.com/detail?series_id=7675745080522574910"
        )
    }

    func testSharePageNumericVideoIDBuildsOfficialDetailURL() throws {
        let html = #"<script>window.__DATA__={"video_id":7675745080522574910}</script>"#

        XCTAssertEqual(
            HTMLMetadata.officialDetailURL(in: html)?.absoluteString,
            "https://hongguoduanju.com/detail?series_id=7675745080522574910"
        )
    }

    func testClipboardShareDetectorOnlyAcceptsRedFruitLinks() {
        XCTAssertEqual(
            ClipboardShareDetector.redFruitURL(in: "分享给你 https://hongguoduanju.com/detail?series_id=123")?.host,
            "hongguoduanju.com"
        )
        XCTAssertEqual(
            ClipboardShareDetector.redFruitURL(in: "https://kylin.hainanyuyue.com/s/GXf3C13NXeQ/")?.host,
            "kylin.hainanyuyue.com"
        )
        XCTAssertNil(ClipboardShareDetector.redFruitURL(in: "https://example.com/detail?id=123"))
        XCTAssertNil(ClipboardShareDetector.redFruitURL(in: "https://hongguoduanju.com.attacker.invalid/detail?id=123"))
    }

    func testOfficialDetailFixtureExtractsSocialFieldsAndSeasonEpisodeTotals() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = projectRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("RedFruitTrackerTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("hongguoduanju-series-detail.html")
        let html = try String(contentsOf: sampleURL, encoding: .utf8)

        XCTAssertEqual(HTMLMetadata.currentSeriesSocialInfoDecimalValue(for: ["rating"], in: html), 9)
        XCTAssertEqual(HTMLMetadata.currentSeriesSocialInfoIntValue(for: ["rating_count"], in: html), 5611)
        XCTAssertEqual(
            HTMLMetadata.currentSeriesSocialInfoValue(for: ["text"], nestedKeys: ["hot_score_data"], in: html),
            "10116万热度"
        )

        let seasons = HTMLMetadata.seasons(
            in: html,
            baseURL: URL(string: "https://hongguoduanju.com/detail?series_id=7685224734895655960")!
        )
        XCTAssertEqual(seasons.map(\.seasonNumber), [2, 3])
        XCTAssertEqual(seasons.first(where: { $0.seasonNumber == 3 })?.episodeCount, 152)
        XCTAssertEqual(seasons.first(where: { $0.seasonNumber == 3 })?.episodes.count, 3)
        XCTAssertEqual(seasons.first(where: { $0.seasonNumber == 2 })?.episodeCount, 128)
    }

    func testStructuredHeatAndRatingOutrankGenericOpenGraphValues() {
        let html = #"""
        <meta property="og:heat" content="4100万">
        <meta property="og:rating" content="6.0">
        <script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"popularity":41000000},"seriesSocialInfo":{"rating":"9.1","hot_score_data":{"text":"3600万热度","score":"3600万"}}}}};</script>
        """#

        XCTAssertEqual(HTMLMetadata.officialHeatText(in: html), "3600万热度")
        XCTAssertEqual(HTMLMetadata.officialHeatScore(in: html), 36_000_000)
        XCTAssertEqual(HTMLMetadata.officialRating(in: html), 9.1)

        let detailOnlyHeat = #"<script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"popularity":41000000}}}};</script>"#
        XCTAssertEqual(HTMLMetadata.officialHeatText(in: detailOnlyHeat), "4100万")
        XCTAssertEqual(HTMLMetadata.officialHeatScore(in: detailOnlyHeat), 41_000_000)
    }

    func testSharedManjuHeatOutranksDifferentDetailPlatformHeat() {
        let sharePage = #"<script>_ROUTER_DATA={"loaderData":{"video-animation-share_page":{"pageData":{"series_data":{"popularity":36000000}}}}};</script>"#
        let detailPage = #"<script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"popularity":41000000}}}};</script>"#

        XCTAssertEqual(HTMLMetadata.officialHeatText(in: sharePage, fallbackHTML: detailPage), "3600万")
        XCTAssertEqual(HTMLMetadata.officialHeatScore(in: sharePage, fallbackHTML: detailPage), 36_000_000)
    }

    func testSeasonParserReadsSnakeCaseSeasonListAndEpisodeIndexes() {
        let html = #"""
        <script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"series_name":"星海纪元第三季","episode_cnt":2,"video_data":{"video_list":[{"vid":"s3e2","vid_index":2,"title":"第2集"},{"vid":"s3e1","vid_index":1,"title":"第1集"}]}},"video_list":[{"series_name":"星海纪元第一季","series_id":"s1","episode_cnt":90},{"series_name":"星海纪元第二季","series_id":"s2","episode_cnt":80},{"series_name":"星海纪元第三季","series_id":"s3","episode_cnt":2}]}}};</script>
        """#
        let seasons = HTMLMetadata.seasons(
            in: html,
            baseURL: URL(string: "https://hongguoduanju.com/detail?series_id=s3")!
        )

        XCTAssertEqual(seasons.map(\.seasonNumber), [1, 2, 3])
        XCTAssertEqual(seasons.map(\.episodeCount), [90, 80, 2])
        XCTAssertEqual(seasons.last?.episodes.map(\.sourceVid), ["s3e1", "s3e2"])
        XCTAssertEqual(seasons.last?.episodes.map(\.episodeNumber), [1, 2])
    }

    func testSeasonMetadataMergeKeepsOtherSeasonsAndPrefersCurrentDetailCount() {
        let detail = [PublicSeasonMetadata(
            seasonNumber: 3,
            title: "第三季",
            episodeCount: 152,
            sourceURL: "https://example.com/detail?s=3",
            episodes: []
        )]
        let share = [
            PublicSeasonMetadata(seasonNumber: 2, title: "第二季", episodeCount: 128, sourceURL: nil, episodes: []),
            PublicSeasonMetadata(seasonNumber: 3, title: "第三季", episodeCount: 150, sourceURL: nil, episodes: [])
        ]

        let merged = PublicSeasonMetadataMerger.merge(primary: detail, supplement: share)

        XCTAssertEqual(merged.map(\.seasonNumber), [2, 3])
        XCTAssertEqual(merged.map(\.episodeCount), [128, 152])
        XCTAssertEqual(merged.last?.sourceURL, "https://example.com/detail?s=3")
    }

    func testRedFruitManjuShareFixtureUsesCurrentSeriesMetadataOnly() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = projectRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("RedFruitTrackerTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("redfruit-manju-share.html")
        let html = try String(contentsOf: sampleURL, encoding: .utf8)
        let baseURL = URL(string: "https://kylin.hainanyuyue.com/s/Km7WJeQrFIE/")!

        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailValue(for: ["title"], in: html),
            "红袖伴我，修清玄第一季"
        )
        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailCover(in: html, baseURL: baseURL)?.url,
            "https://p6-novel.byteimg.com/novel-pic/current-series-cover.image"
        )
        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailDecimalValue(for: ["popularity"], in: html),
            38_927_338
        )
        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailCompactCountText(for: ["popularity"], in: html),
            "3892.7万"
        )
        XCTAssertEqual(HTMLMetadata.officialHeatText(in: html), "3892.7万")
        XCTAssertEqual(HTMLMetadata.officialHeatScore(in: html), 38_927_338)
        XCTAssertNil(
            HTMLMetadata.selectedCoverURL(in: html, baseURL: baseURL, title: "红袖伴我，修清玄第一季")
        )
        XCTAssertEqual(
            HTMLMetadata.currentSeriesDetailValue(for: ["category_list"], in: html),
            "玄幻,穿越,系统,修真,异界"
        )
        XCTAssertNil(HTMLMetadata.currentSeriesSocialInfoDecimalValue(for: ["rating"], in: html))

        let seasons = HTMLMetadata.seasons(in: html, baseURL: baseURL)
        XCTAssertEqual(seasons.map(\.seasonNumber), [1])
        XCTAssertEqual(seasons.first?.episodeCount, 245)
        XCTAssertEqual(seasons.first?.episodes.count, 12)
        XCTAssertEqual(seasons.first?.episodes.last?.sourceVid, "chapter-12")
    }

    func testManjuSharePageDoesNotUseGenericImageWhenOfficialCoverIsMissing() {
        let html = #"""
        <meta property="og:image" content="https://example.com/video-first-frame.jpg">
        <script>
        _ROUTER_DATA = {"loaderData":{"video-animation-share_page":{"pageData":{"series_data":{"title":"测试作品"}}}}};
        </script>
        """#
        let baseURL = URL(string: "https://kylin.hainanyuyue.com/s/example/")!

        XCTAssertNil(HTMLMetadata.selectedCoverURL(in: html, baseURL: baseURL, title: "测试作品"))
        XCTAssertTrue(HTMLMetadata.coverCandidates(in: html, baseURL: baseURL).isEmpty)
    }

    func testManjuSharePageDoesNotUseLandscapeVideoFrameAsCover() {
        let html = #"""
        <script>
        window._ROUTER_DATA = {
          "loaderData": {
            "video-animation-share_page": {
              "pageData": {
                "series_data": {
                  "title": "横向视频作品",
                  "series_cover": "https:\u002F\u002Fexample.com\u002Fseries-cover.jpg",
                  "video_meta": {"width": 640, "height": 360}
                }
              }
            }
          }
        };
        </script>
        """#
        let baseURL = URL(string: "https://kylin.hainanyuyue.com/s/landscape/")!

        XCTAssertNil(
            HTMLMetadata.selectedCoverURL(
                in: html,
                baseURL: baseURL,
                title: "横向视频作品"
            )
        )
    }

    func testManjuSharePagePrefersDistinctFallbackPosterOverLandscapeVideoFrame() {
        let html = #"""
        <meta property="og:image" content="https://example.com/series-cover.jpg">
        <script>
        window._ROUTER_DATA = {
          "loaderData": {
            "video-animation-share_page": {
              "pageData": {
                "series_data": {
                  "title": "带备用海报的作品",
                  "series_cover": "https:\u002F\u002Fexample.com\u002Fseries-cover.jpg",
                  "series_cover_fallback": ["https:\u002F\u002Fexample.com\u002Fcharacter-poster.jpg"],
                  "video_meta": {"width": 640, "height": 360}
                }
              }
            }
          }
        };
        </script>
        """#
        let baseURL = URL(string: "https://kylin.hainanyuyue.com/s/fallback/")!

        XCTAssertEqual(
            HTMLMetadata.selectedCoverURL(
                in: html,
                baseURL: baseURL,
                title: "带备用海报的作品"
            ),
            "https://example.com/character-poster.jpg"
        )
    }

    func testSSRCurrentSeriesMetadataExposesOfficialFields() {
        let html = #"""
        <script>
        _ROUTER_DATA = {
          "loaderData": {
            "detail_page": {
              "seriesDetail": {
                "series_name": "测试作品",
                "series_intro": "这是公开简介。",
                "score": 8.8,
                "heat": "3930万",
                "tags": ["修仙", "爽剧"]
              }
            }
          }
        };
        </script>
        """#

        XCTAssertEqual(HTMLMetadata.currentSeriesDetailValue(for: ["series_intro"], in: html), "这是公开简介。")
        XCTAssertEqual(HTMLMetadata.currentSeriesDetailDecimalValue(for: ["score"], in: html), 8.8)
        XCTAssertEqual(HTMLMetadata.currentSeriesDetailValue(for: ["heat"], in: html), "3930万")
        XCTAssertEqual(HTMLMetadata.currentSeriesDetailValue(for: ["tags"], in: html), "修仙,爽剧")
    }

    func testCoverSelectorDoesNotAutoSelectLowConfidenceUIImage() {
        let candidates = [
            CoverImageCandidate(
                url: "https://example.com/lock.png",
                context: "<img class=\"m-lock\" src=\"lock.png\">"
            ),
            CoverImageCandidate(
                url: "https://example.com/loading.png",
                context: "<img class=\"loading\" src=\"loading.png\">"
            )
        ]

        XCTAssertNil(CoverURLSelector.preferred(candidates, title: "测试漫剧"))
    }

    func testCoverReplacementOnlyTargetsLikelyVideoFrames() {
        XCTAssertTrue(CoverURLSelector.shouldReplaceExisting(nil))
        XCTAssertTrue(CoverURLSelector.shouldReplaceExisting("https://example.com/video-first-frame.jpg"))
        XCTAssertTrue(CoverURLSelector.shouldReplaceExisting("https://example.com/share-cover.jpg"))
        XCTAssertFalse(CoverURLSelector.shouldReplaceExisting("https://example.com/character-poster.jpg"))
    }

    func testCoverSelectorDeduplicatesURLs() {
        let candidates = [
            CoverImageCandidate(
                url: "https://example.com/cover.jpg",
                context: "<meta property=\"og:image\" content=\"cover.jpg\">"
            ),
            CoverImageCandidate(
                url: "https://example.com/cover.jpg",
                context: "<img class=\"cover\" src=\"cover.jpg\">"
            )
        ]

        XCTAssertEqual(CoverURLSelector.ranked(candidates).map(\.url), ["https://example.com/cover.jpg"])
    }

    func testCoverSelectorDeduplicatesByteimgCDNAndResizeVariants() {
        let canonicalPoster = CoverImageCandidate(
            url: "https://p3-novel.byteimg.com/novel-pic/poster-123~tplv-shrink:640:0.image",
            context: "official-current-series-cover"
        )
        let resizedPoster = CoverImageCandidate(
            url: "https://p6-novel.byteimg.com/novel-pic/poster-123~tplv-shrink:1080:0.webp?token=cache",
            context: "og:image"
        )

        let ranked = CoverURLSelector.ranked([resizedPoster, canonicalPoster])

        XCTAssertEqual(ranked.map(\.url), [canonicalPoster.url])
    }

    func testCoverSelectorCanonicalizesCommonCDNResizeParameters() {
        let resized = CoverImageCandidate(
            url: "https://images.example/poster.jpg?width=320&quality=70&token=one",
            context: "poster"
        )
        let alternate = CoverImageCandidate(
            url: "http://images.example/poster.webp?height=640&fm=webp&token=two",
            context: "poster"
        )

        XCTAssertEqual(CoverURLSelector.ranked([resized, alternate]).count, 1)
    }

    func testCoverCandidateDeduplicatorDropsDifferentURLsWithMatchingImageFingerprints() {
        let first = VerifiedCoverCandidate(
            candidate: CoverImageCandidate(url: "https://cdn-a.example/poster.jpg", context: "official poster"),
            width: 400,
            height: 600,
            fingerprint: 0xAA55AA55AA55AA55
        )
        let resizedCopy = VerifiedCoverCandidate(
            candidate: CoverImageCandidate(url: "https://cdn-b.example/poster.webp", context: "image"),
            width: 240,
            height: 360,
            fingerprint: 0xAA55AA55AA55AA5D
        )
        let landscape = VerifiedCoverCandidate(
            candidate: CoverImageCandidate(url: "https://cdn-c.example/video.jpg", context: "video"),
            width: 600,
            height: 400,
            fingerprint: 0x1122334455667788
        )

        let unique = CoverCandidateDeduplicator.uniquePortraits([first, resizedCopy, landscape])

        XCTAssertEqual(unique.map(\.candidate.url), [first.candidate.url])
    }

    func testCoverImageFingerprintGroupsSimilarGrayscaleImages() throws {
        var original = (0..<64).map { index in UInt8((index % 8) * 28) }
        var resizedVariant = original
        resizedVariant[0] = min(255, resizedVariant[0] + 12)
        resizedVariant[1] = min(255, resizedVariant[1] + 12)

        let firstHash = try XCTUnwrap(CoverImageFingerprint.hash(grayscaleSamples: original))
        let resizedHash = try XCTUnwrap(CoverImageFingerprint.hash(grayscaleSamples: resizedVariant))

        XCTAssertTrue(CoverImageFingerprint.isDuplicate(firstHash, resizedHash))
        original[63] = 255
        XCTAssertNotNil(CoverImageFingerprint.hash(grayscaleSamples: original))
    }

    func testSeriesKeepsOriginalShareURLInsteadOfSeasonDetailURL() {
        let originalShareURL = "https://share.example.com/work/abc"
        let resolvedSeasonURL = "https://hongguoduanju.com/detail?series_id=season-1"

        XCTAssertEqual(
            SeriesLinkPolicy.primary(existing: originalShareURL, incoming: resolvedSeasonURL),
            originalShareURL
        )
        XCTAssertEqual(
            SeriesLinkPolicy.primary(existing: nil, incoming: originalShareURL),
            originalShareURL
        )
        XCTAssertEqual(
            SeriesLinkPolicy.primary(existing: resolvedSeasonURL, incoming: originalShareURL),
            originalShareURL
        )
    }

    func testSharePayloadParserAcceptsURLTextAndData() {
        let expected = URL(string: "https://example.com/series/123")!

        XCTAssertEqual(SharePayloadParser.url(from: expected), expected)
        XCTAssertEqual(SharePayloadParser.url(from: "分享链接：\(expected.absoluteString)"), expected)
        XCTAssertEqual(SharePayloadParser.url(from: Data(expected.absoluteString.utf8)), expected)
    }

    func testShareInboxQueuesSharedURLWithoutCopyingAndDeduplicatesRepeatedShares() throws {
        let suiteName = "ShareInboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sharedURL = URL(string: "https://example.com/series/123")!

        XCTAssertTrue(ShareInbox.enqueue(sharedURL, in: defaults))
        XCTAssertTrue(ShareInbox.enqueue(sharedURL, in: defaults))

        XCTAssertEqual(ShareInbox.pendingURLs(in: defaults), [sharedURL])
        ShareInbox.remove(sharedURL, in: defaults)
        XCTAssertTrue(ShareInbox.pendingURLs(in: defaults).isEmpty)
    }

    func testShareCallbackCarriesOriginalURLToHostApp() throws {
        let sharedURL = URL(string: "https://hongguoduanju.com/detail?series_id=123")!
        let callback = try XCTUnwrap(ShareRoute.callbackURL(for: sharedURL))
        XCTAssertEqual(ShareRoute.sharedURL(from: callback), sharedURL)
    }

    func testShareRouteCarriesAndRecoversTheSharedURL() throws {
        let sharedURL = URL(string: "https://example.com/series/123?from=share")!
        let callback = try XCTUnwrap(ShareRoute.callbackURL(for: sharedURL))

        XCTAssertEqual(ShareRoute.sharedURL(from: callback), sharedURL)
    }

    func testCompletionStatusRecognizesBooleanAndChineseText() {
        let completed = #"<script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"is_finished":true}}}};</script>"#
        let ongoing = #"<script>_ROUTER_DATA={"loaderData":{"detail_page":{"seriesDetail":{"status":"连载中"}}}};</script>"#

        XCTAssertEqual(HTMLMetadata.completionStatus(in: completed), SeriesCompletionStatus.completed.rawValue)
        XCTAssertEqual(HTMLMetadata.completionStatus(in: ongoing), SeriesCompletionStatus.ongoing.rawValue)
    }

    func testHeatTrendAggregationBuildsDailySamplesAndObservedRange() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 9)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 18)))
        let first = OfficialSnapshot(sourceSeriesID: "series", capturedAt: firstDate)
        first.officialHeatScore = 30
        let second = OfficialSnapshot(sourceSeriesID: "series", capturedAt: secondDate)
        second.officialHeatScore = 42

        let samples = HeatTrendAggregation.samples(
            from: [second, first],
            granularity: .day,
            value: { $0.officialHeatScore },
            calendar: calendar
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.value, 42)
        XCTAssertEqual(samples.first?.highestObserved, 42)
        XCTAssertEqual(samples.first?.lowestObserved, 30)
        XCTAssertEqual(samples.first?.observationCount, 2)
    }

    func testHeatTrendDateLabelsSharePointCoordinatesWithoutClippingAtEdges() throws {
        let size = CGSize(width: 320, height: 210)
        let rect = HeatTrendChartGeometry.plotRect(in: size)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let last = first.addingTimeInterval(6 * 86_400)

        let firstPointX = HeatTrendChartGeometry.xPosition(for: first, first: first, last: last, in: rect)
        let firstLabelX = HeatTrendChartGeometry.xPosition(for: first, first: first, last: last, in: rect)
        let lastPointX = HeatTrendChartGeometry.xPosition(for: last, first: first, last: last, in: rect)
        let lastLabelX = HeatTrendChartGeometry.xPosition(for: last, first: first, last: last, in: rect)

        XCTAssertEqual(firstLabelX, firstPointX)
        XCTAssertEqual(lastLabelX, lastPointX)
        XCTAssertGreaterThanOrEqual(firstLabelX - 36, 0)
        XCTAssertLessThanOrEqual(lastLabelX + 36, size.width)
    }

    func testOfficialRatingWithoutHeatDoesNotCreateAHeatTrendPoint() {
        let snapshot = OfficialSnapshot(sourceSeriesID: "series")
        snapshot.officialRating = 9.2

        let samples = HeatTrendAggregation.samples(
            from: [snapshot],
            granularity: .day,
            value: { $0.officialHeatScore }
        )

        XCTAssertTrue(samples.isEmpty)
    }

    private func manjuShareFixture(
        title: String,
        episodeCount: Int,
        popularity: String,
        tags: String
    ) -> String {
        let tagValues = tags.split(separator: ",").map { "\"\($0)\"" }.joined(separator: ",")
        return #"""
        <script>
        window._ROUTER_DATA = {"loaderData":{"video-animation-share_page":{"pageData":{"series_data":{"title":"\#(title)","series_cover":"https:\u002F\u002Fp3-novel.byteimg.com\u002Fnovel-pic\u002Fcover.image","popularity":\#(popularity),"serial_count":\#(episodeCount),"category_list":[\#(tagValues)]},"chapter_ids":["chapter-1","chapter-2"]}}}}};
        </script>
        """#
    }
}
