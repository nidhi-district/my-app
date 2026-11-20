import XCTest

final class EditStickerUITests: XCTestCase {
    func testEditOpensStickerDrawerAndPlacesOnActiveNote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sticker-test", "-reset-stickers"]
        app.launch()

        let edit = app.buttons["edit-note"]
        let drawer = app.buttons["sticker-drawer"]
        let frog = app.buttons["tray-frog"]
        let note = app.buttons["note"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        XCTAssertFalse(drawer.exists)
        XCTAssertFalse(frog.exists)

        edit.tap()
        XCTAssertTrue(frog.waitForExistence(timeout: 3))
        XCTAssertTrue(frog.isHittable)
        XCTAssertEqual(drawer.value as? String, "expanded")
        XCTAssertTrue(app.buttons["tray-moon"].isHittable)
        XCTAssertFalse(app.buttons["open-washi-tape"].exists)
        capture(app, named: "open sticker drawer")

        drawer.tap()
        XCTAssertFalse(frog.exists)
        XCTAssertEqual(drawer.value as? String, "collapsed")
        drawer.tap()
        XCTAssertTrue(frog.waitForExistence(timeout: 3))
        frog.tap()
        let prompt = app.staticTexts["placement-hint"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertEqual(prompt.label, "tap the note to place frog")
        XCTAssertFalse(frog.exists)

        let point = note.coordinate(withNormalizedOffset: CGVector(dx: 0.26, dy: 0.72))
        point.tap()
        XCTAssertTrue(app.sliders["decoration-size"].waitForExistence(timeout: 3))
        XCTAssertEqual(note.value as? String, "1 sticker placed")
        XCTAssertTrue(app.sliders["decoration-rotation"].exists)
        XCTAssertTrue(app.buttons["delete-decoration"].exists)
        capture(app, named: "sticker on paper")

        drawer.tap()
        XCTAssertTrue(frog.waitForExistence(timeout: 3))
        app.buttons["tray-cat"].tap()
        XCTAssertTrue(app.buttons["cancel-placement"].waitForExistence(timeout: 3))
        app.buttons["cancel-placement"].tap()
        XCTAssertTrue(frog.waitForExistence(timeout: 3))
        XCTAssertEqual(note.value as? String, "1 sticker placed")
        edit.tap()
        XCTAssertFalse(drawer.exists)
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
