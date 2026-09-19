import XCTest

final class RedFruitTrackerUITests: XCTestCase {
    func testLibraryEmptyStateScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["漫剧记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["还没有记录"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "library-empty-state"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
