import XCTest
@testable import RedFruitTracker

final class LibraryModelTests: XCTestCase {
    func testSeriesKeepsExternalIdentifierAndMetadata() {
        let record = SeriesRecord(
            sourceSeriesID: "7680187265020070937",
            title: "测试漫剧",
            tagsText: "修仙,爽剧",
            officialRating: 9.0,
            officialHeatText: "6859万"
        )

        XCTAssertEqual(record.sourceSeriesID, "7680187265020070937")
        XCTAssertEqual(record.title, "测试漫剧")
        XCTAssertEqual(record.tagsText, "修仙,爽剧")
        XCTAssertEqual(record.officialRating, 9.0)
        XCTAssertEqual(record.officialHeatText, "6859万")
    }
}
