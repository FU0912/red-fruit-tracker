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
}
