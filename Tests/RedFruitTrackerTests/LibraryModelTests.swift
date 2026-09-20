import XCTest
@testable import RedFruitTracker

final class LibraryModelTests: XCTestCase {
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

    func testTitleNormalizerRemovesRedFruitBranding() {
        XCTAssertEqual(TitleNormalizer.normalize("红果漫剧：《仙途归来》 - 红果"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("《仙途归来》 | 红果短剧"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("免费看片《仙途归来》"), "仙途归来")
        XCTAssertEqual(TitleNormalizer.normalize("女主全都坏掉免费观看《仙途归来》"), "仙途归来")
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
}
