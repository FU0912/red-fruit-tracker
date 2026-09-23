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
        XCTAssertEqual(
            HTMLMetadata.selectedCoverURL(in: html, baseURL: baseURL, title: "红袖伴我，修清玄第一季"),
            "https://p6-novel.byteimg.com/novel-pic/current-series-cover.image"
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
