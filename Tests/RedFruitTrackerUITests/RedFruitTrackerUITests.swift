import XCTest

final class RedFruitTrackerUITests: XCTestCase {
    func testLibraryKeepsAdditionOrderAfterOlderWorkWasUpdated() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-order"]
        app.launch()

        let newer = app.buttons["series-card-order-newer"]
        let older = app.buttons["series-card-order-older"]
        XCTAssertTrue(newer.waitForExistence(timeout: 5))
        XCTAssertTrue(older.exists)
        XCTAssertFalse(app.staticTexts["series-added-at"].exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY,
                          "Refreshing an older work must never move it ahead of a newly added work.")
    }

    func testLibraryEmptyStateScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["漫剧记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["搜索作品名、简介或 #标签"].exists)
        XCTAssertTrue(app.staticTexts["还没有记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["添加作品"].firstMatch.exists)

        app.buttons["添加作品"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["添加作品"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["红果分享链接"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["作品名称"].exists)
        XCTAssertTrue(app.buttons["保存"].exists)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "library-empty-state"
        attachment.lifetime = .keepAlways
        add(attachment)

        let personalRating = app.textFields["add-personal-rating"]
        for _ in 0..<3 where !personalRating.exists {
            app.swipeUp()
        }
        XCTAssertTrue(personalRating.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["add-personal-review"].exists)
    }

    func testOnlyRefreshButtonStartsLibraryRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture", "--ui-testing-refresh"]
        app.launch()

        let searchField = app.textFields["搜索作品名、简介或 #标签"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        let title = app.staticTexts["漫剧记录"]
        title.tap()
        let progress = app.descendants(matching: .any)["library-refresh-progress"]
        XCTAssertFalse(progress.exists)

        searchField.tap()
        XCTAssertFalse(progress.exists)

        let refreshButton = app.buttons["更新全部公开资料"]
        XCTAssertTrue(refreshButton.exists)
        refreshButton.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        app.buttons["停止"].tap()
    }

    func testSeriesCardAndDetailLayoutScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["漫剧记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["搜索作品名、简介或 #标签"].exists)
        XCTAssertFalse(app.navigationBars["漫剧记录"].exists)

        let title = app.staticTexts["反派二代目，女主全都坏掉了"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let cardButton = app.buttons["series-card-ui-fixture-series"].firstMatch
        XCTAssertTrue(cardButton.exists)

        let floatingAdd = app.buttons["add-series-button"].firstMatch
        XCTAssertTrue(floatingAdd.exists)
        XCTAssertGreaterThanOrEqual(floatingAdd.frame.width, 52)
        XCTAssertGreaterThanOrEqual(floatingAdd.frame.height, 52)
        XCTAssertGreaterThan(floatingAdd.frame.minX, app.windows.firstMatch.frame.midX)

        let libraryList = app.descendants(matching: .any)["library-list"].firstMatch
        XCTAssertTrue(libraryList.exists)
        libraryList.swipeUp()
        XCTAssertFalse(app.staticTexts["漫剧记录"].isHittable)
        XCTAssertFalse(app.textFields["搜索作品名、简介或 #标签"].isHittable)
        libraryList.swipeDown()
        XCTAssertTrue(app.staticTexts["漫剧记录"].waitForExistence(timeout: 5))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(floatingAdd.frame.maxY, tabBar.frame.minY + 4)

        floatingAdd.tap()
        XCTAssertTrue(app.navigationBars["添加作品"].waitForExistence(timeout: 5))
        app.navigationBars["添加作品"].buttons["取消"].tap()
        XCTAssertTrue(cardButton.waitForExistence(timeout: 5))

        let libraryCover = app.descendants(matching: .any)["series-card-cover"].firstMatch
        let libraryTitle = app.staticTexts["series-card-title"].firstMatch
        XCTAssertTrue(libraryCover.exists)
        XCTAssertTrue(libraryTitle.exists)
        XCTAssertLessThanOrEqual(libraryCover.frame.width, 100)
        XCTAssertGreaterThan(libraryCover.frame.height, libraryCover.frame.width)
        XCTAssertGreaterThanOrEqual(libraryTitle.frame.minX, libraryCover.frame.maxX - 4)
        XCTAssertFalse(app.staticTexts["共1季"].exists)
        XCTAssertFalse(app.staticTexts["共189集"].exists)
        XCTAssertFalse(app.staticTexts["看到第1季 · 第1集"].exists)

        let heat = app.descendants(matching: .any)["series-card-heat"].firstMatch
        let completionStatus = app.descendants(matching: .any)["series-card-completion-status"].firstMatch
        let shelfState = app.descendants(matching: .any)["series-card-shelf-state"].firstMatch
        XCTAssertTrue(heat.exists)
        XCTAssertTrue(completionStatus.exists)
        XCTAssertTrue(shelfState.exists)

        let libraryScreenshot = XCUIScreen.main.screenshot()
        let libraryAttachment = XCTAttachment(screenshot: libraryScreenshot)
        libraryAttachment.name = "series-library-card"
        libraryAttachment.lifetime = .keepAlways
        add(libraryAttachment)

        XCTAssertTrue(cardButton.exists)
        cardButton.swipeLeft()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 2))
        app.buttons["删除"].tap()
        XCTAssertTrue(app.alerts["删除这部漫剧？"].waitForExistence(timeout: 2))
        app.alerts.buttons["取消"].tap()

        cardButton.tap()

        XCTAssertTrue(app.staticTexts["基本信息"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["全189集"].exists)
        XCTAssertTrue(app.staticTexts["我的评分与点评"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["open-red-fruit-button"].exists)
        let copyTitle = app.buttons["copy-series-title"]
        XCTAssertTrue(copyTitle.exists)
        copyTitle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["series-title-copied"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["修改自动保存"].exists)
        XCTAssertFalse(app.buttons["heat-chart-style"].exists)
        let personalRating = app.descendants(matching: .any)["personal-rating-score"].firstMatch
        XCTAssertTrue(personalRating.exists)
        XCTAssertTrue(app.textFields["personal-rating-input"].exists)
        XCTAssertFalse(app.sliders.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["选集"].exists)
        XCTAssertFalse(app.staticTexts["第1季"].exists)
        XCTAssertFalse(app.staticTexts["已看 1 / 共189集"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["official-rating"].exists)
        let officialHeat = app.descendants(matching: .any)["official-heat"].firstMatch
        XCTAssertTrue(officialHeat.exists)
        XCTAssertTrue(officialHeat.label.contains("3930万"))
        XCTAssertTrue(app.staticTexts["修仙"].exists)
        XCTAssertFalse(app.textFields["episode-progress-input"].exists)
        XCTAssertFalse(app.buttons["第1集，已看，当前"].exists)
        XCTAssertFalse(app.buttons["第1集到第100集"].exists)
        XCTAssertFalse(app.buttons["第101集到第189集"].exists)

        let detailCover = app.descendants(matching: .any)["series-detail-cover"].firstMatch
        let detailTitle = app.staticTexts["series-detail-title"].firstMatch
        XCTAssertTrue(detailCover.exists)
        XCTAssertTrue(detailTitle.exists)
        XCTAssertLessThanOrEqual(detailCover.frame.width, 140)
        XCTAssertGreaterThan(detailCover.frame.height, detailCover.frame.width)
        XCTAssertGreaterThanOrEqual(detailTitle.frame.minX, detailCover.frame.maxX - 4)

        XCTAssertTrue(app.descendants(matching: .any)["official-rating"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["official-heat"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["official-tags"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["completion-status"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail-shelf-state"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["official-trend-section"].exists)
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any)["official-rating"].frame.minX,
            detailCover.frame.maxX - 4
        )
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any)["official-heat"].frame.minX,
            detailCover.frame.maxX - 4
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "series-detail-layout"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["漫剧记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["搜索作品名、简介或 #标签"].exists)
        XCTAssertFalse(app.navigationBars["漫剧记录"].exists)
        XCTAssertTrue(app.staticTexts["反派二代目，女主全都坏掉了"].firstMatch.exists)

        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.navigationBars["统计"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["stats-filter-watching"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["season-change-log-link"].exists)
    }
}
