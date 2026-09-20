import XCTest

final class RedFruitTrackerUITests: XCTestCase {
    func testLibraryEmptyStateScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty"]
        app.launch()

        XCTAssertTrue(app.navigationBars["漫剧记录"].waitForExistence(timeout: 5))
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
    }

    func testSeriesCardAndDetailLayoutScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-fixture"]
        app.launch()

        let title = app.staticTexts["反派二代目，女主全都坏掉了"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let libraryScreenshot = XCUIScreen.main.screenshot()
        let libraryAttachment = XCTAttachment(screenshot: libraryScreenshot)
        libraryAttachment.name = "series-library-card"
        libraryAttachment.lifetime = .keepAlways
        add(libraryAttachment)

        title.tap()

        XCTAssertTrue(app.staticTexts["基本信息"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["选集"].exists)
        XCTAssertTrue(app.staticTexts["全189集"].exists)
        XCTAssertTrue(app.buttons["第1集，已看，当前"].exists)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "series-detail-layout"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
