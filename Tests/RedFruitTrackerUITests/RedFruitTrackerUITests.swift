import XCTest

final class RedFruitTrackerUITests: XCTestCase {
    func testLibraryEmptyStateScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["漫剧记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["还没有记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["添加作品"].firstMatch.exists)

        app.buttons["添加作品"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["添加作品"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["作品名称"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存"].exists)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "library-empty-state"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
