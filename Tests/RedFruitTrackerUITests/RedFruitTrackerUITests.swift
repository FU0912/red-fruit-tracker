import XCTest
import UIKit

final class RedFruitTrackerUITests: XCTestCase {
    func testUnsignedBuildStaysOpenWithoutCloudKitEntitlement() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["library-search-field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["file-backup-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cloud-backup-status"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

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

        XCTAssertTrue(app.staticTexts["library-header-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library-search-field"].exists)
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

        let searchButton = app.buttons["library-search-field"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["file-backup-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cloud-backup-status"].exists)
        let title = app.staticTexts["library-header-title"]
        title.tap()
        let progress = app.descendants(matching: .any)["library-refresh-progress"]
        XCTAssertFalse(progress.exists)

        searchButton.tap()
        XCTAssertTrue(app.navigationBars["搜索作品"].waitForExistence(timeout: 5))
        XCTAssertFalse(progress.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let refreshButton = app.buttons["library-refresh-button"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
        refreshButton.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let stopButton = app.buttons["library-refresh-cancel"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        stopButton.tap()
        XCTAssertFalse(progress.exists)
    }

    func testSeriesCardAndDetailLayoutScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["library-header-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library-search-field"].exists)
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
        XCTAssertFalse(app.staticTexts["library-header-title"].isHittable)
        XCTAssertFalse(app.buttons["library-search-field"].isHittable)
        libraryList.swipeDown()
        XCTAssertTrue(app.staticTexts["library-header-title"].waitForExistence(timeout: 5))

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
        let officialTags = app.descendants(matching: .any)["official-tags"]
        XCTAssertTrue(officialTags.exists)
        XCTAssertTrue(officialTags.descendants(matching: .any)["detail-tag-修仙"].exists)
        XCTAssertFalse(app.textFields["episode-progress-input"].exists)
        XCTAssertFalse(app.buttons["第1集，已看，当前"].exists)
        XCTAssertFalse(app.buttons["第1集到第100集"].exists)
        XCTAssertFalse(app.buttons["第101集到第189集"].exists)

        let detailCover = app.descendants(matching: .any)["series-detail-cover"].firstMatch
        let detailTitle = app.buttons["copy-series-title"].firstMatch
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
        XCTAssertTrue(app.staticTexts["library-header-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library-search-field"].exists)
        XCTAssertFalse(app.navigationBars["漫剧记录"].exists)
        XCTAssertTrue(app.staticTexts["反派二代目，女主全都坏掉了"].firstMatch.exists)

        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["stats-filter-watching"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["season-change-log-link"].exists)
    }

    func testNextSeasonDateCanBeScheduledAndClearedFromLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        let card = app.buttons["series-card-ui-fixture-series"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let dateRow = app.buttons["next-season-date-picker"]
        XCTAssertTrue(dateRow.waitForExistence(timeout: 5))
        dateRow.tap()
        XCTAssertTrue(app.navigationBars["预约下一季"].waitForExistence(timeout: 3))

        let targetDate = upcomingFifthDay()
        let currentComponents = Calendar.current.dateComponents([.year, .month], from: Date())
        let targetComponents = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        if currentComponents.year != targetComponents.year || currentComponents.month != targetComponents.month {
            app.buttons["appointment-next-month"].tap()
        }
        let dayIdentifier = String(
            format: "appointment-day-%04d-%02d-%02d",
            targetComponents.year!,
            targetComponents.month!,
            targetComponents.day!
        )
        let targetDay = app.buttons[dayIdentifier]
        targetDay.tap()
        XCTAssertEqual(targetDay.value as? String, "已选")
        XCTAssertTrue(app.navigationBars["预约下一季"].exists)
        app.buttons["appointment-confirm"].tap()
        XCTAssertFalse(app.navigationBars["预约下一季"].waitForExistence(timeout: 1))
        XCTAssertEqual(dateRow.value as? String, "\(targetComponents.month!)月\(targetComponents.day!)日")

        dateRow.tap()
        XCTAssertTrue(app.navigationBars["预约下一季"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons[dayIdentifier].value as? String, "已选")
        app.navigationBars.buttons["取消"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.exists)
        XCTAssertFalse(app.buttons["series-card-next-season-date"].exists)

        app.tabBars.buttons["统计"].tap()
        app.buttons["stats-filter-appointments"].tap()
        XCTAssertTrue(app.navigationBars["我的预约"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["update-notification-segment"].exists)
        XCTAssertTrue(app.buttons["update-notification-edit"].exists)
    }

    func testLongPressAddImportsRedFruitClipboardLink() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        let addButton = app.buttons["add-series-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        addButton.tap()
        XCTAssertTrue(app.navigationBars["添加作品"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertFalse(app.navigationBars["添加作品"].waitForExistence(timeout: 1))

        let sharedLink = "https://hongguoduanju.com/detail?series_id=123456"
        UIPasteboard.general.string = "分享给你一部漫剧：\(sharedLink)"
        addButton.press(forDuration: 0.7)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let pasteAlert = springboard.alerts.firstMatch
        if pasteAlert.waitForExistence(timeout: 3) {
            let allowPaste = pasteAlert.buttons.matching(
                NSPredicate(format: "label IN %@", ["Allow Paste", "Allow", "Paste", "允许粘贴"])
            ).firstMatch
            if allowPaste.exists {
                allowPaste.tap()
            }
        }

        let linkField = app.textFields["add-series-source-url"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 5))
        XCTAssertEqual(linkField.value as? String, sharedLink)
    }

    func testStatisticsShowsWatchedWorkTagDistribution() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tag-distribution-chart"].waitForExistence(timeout: 5))
        let distributedWorkCount = app.descendants(matching: .any)["tag-distribution-work-count"]
        XCTAssertTrue(distributedWorkCount.waitForExistence(timeout: 5))
        XCTAssertEqual(distributedWorkCount.label, "5")
        let periodControl = app.segmentedControls.firstMatch
        XCTAssertTrue(periodControl.waitForExistence(timeout: 5))
        XCTAssertTrue(periodControl.buttons["本月"].exists)
        XCTAssertTrue(periodControl.buttons["按年"].exists)
        XCTAssertFalse(periodControl.buttons["本季度"].exists)
        let yearMenu = app.descendants(matching: .any)["tag-statistics-year-menu"]
        XCTAssertTrue(yearMenu.waitForExistence(timeout: 5))
        periodControl.buttons["按年"].tap()
        yearMenu.tap()
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentYearOption = app.descendants(matching: .any)["tag-statistics-year-\(currentYear)"]
        XCTAssertTrue(currentYearOption.waitForExistence(timeout: 3))
        currentYearOption.tap()
        XCTAssertEqual((yearMenu.value as? String)?.replacingOccurrences(of: ",", with: ""), "\(currentYear)年")
    }

    func testAppointmentDateSelectionCanBeConfirmedWithoutFollowToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        let card = app.buttons["series-card-ui-fixture-series"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let dateRow = app.buttons["next-season-date-picker"]
        XCTAssertTrue(dateRow.waitForExistence(timeout: 3))
        dateRow.tap()
        XCTAssertTrue(app.navigationBars["预约下一季"].waitForExistence(timeout: 3))

        let targetDate = upcomingFifthDay()
        let currentComponents = Calendar.current.dateComponents([.year, .month], from: Date())
        let targetComponents = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        if currentComponents.year != targetComponents.year || currentComponents.month != targetComponents.month {
            app.buttons["appointment-next-month"].tap()
        }

        let dayIdentifier = String(
            format: "appointment-day-%04d-%02d-%02d",
            targetComponents.year!,
            targetComponents.month!,
            targetComponents.day!
        )
        let targetDay = app.buttons[dayIdentifier]
        XCTAssertTrue(targetDay.waitForExistence(timeout: 3))
        targetDay.tap()
        XCTAssertEqual(targetDay.value as? String, "已选")
        XCTAssertTrue(app.navigationBars["预约下一季"].exists)
        app.buttons["appointment-confirm"].tap()

        XCTAssertFalse(app.navigationBars["预约下一季"].waitForExistence(timeout: 1))
        XCTAssertEqual(dateRow.value as? String, "\(targetComponents.month!)月\(targetComponents.day!)日")
    }

    func testReviewEditorStartsAtFiveLines() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        let card = app.buttons["series-card-ui-fixture-series"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let review = app.textFields["personal-review-input"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(review.frame.height, 100)
    }

    private func upcomingFifthDay() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let currentFifth = calendar.date(
            byAdding: .day,
            value: 4,
            to: calendar.dateInterval(of: .month, for: now)!.start
        )!
        if calendar.component(.day, from: now) <= 5 {
            return currentFifth
        }
        return calendar.date(byAdding: .month, value: 1, to: currentFifth)!
    }
}
