import XCTest

final class DayNavigationUITests: XCTestCase {
    func testCalendarBarRespondsToSwipeDirection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sticker-test"]
        app.launch()

        let date = Calendar.current.startOfDay(for: .now)
        expectDate(date, in: app.staticTexts["active-date"])
        let year = app.buttons["tab-year"]
        year.tap()
        let scroll = app.scrollViews["month-scroll"]
        XCTAssertTrue(app.buttons[dayID("month", date)].waitForExistence(timeout: 3))
        let width = year.frame.width
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let lower = start.withOffset(CGVector(dx: 0, dy: 124))
        start.press(forDuration: 0.08, thenDragTo: lower, withVelocity: .slow, thenHoldForDuration: 0.15)
        XCTAssertLessThan(year.frame.width, width - 12)
        lower.press(forDuration: 0.06, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(year.frame.width, width, accuracy: 1)
        XCTAssertTrue(year.isSelected)
    }

    func testWeekNotePreviewsOpenTheSelectedDay() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sticker-test"]
        app.launch()

        let date = Calendar.current.startOfDay(for: .now)
        let week = app.buttons["tab-week"]
        XCTAssertTrue(week.waitForExistence(timeout: 4))
        week.tap()
        let row = app.buttons[dayID("week", date)]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-day-'")).count, 7)
        capture(app, named: "weekly sticky note previews")
        row.tap()
        expectDate(date, in: app.staticTexts["active-date"])
    }

    func testPinnedYearHeaderCoversScrollingMonthTitle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sticker-test"]
        app.launch()

        let date = Calendar.current.startOfDay(for: .now)
        expectDate(date, in: app.staticTexts["active-date"])
        let dayTab = app.buttons["tab-day"]
        let yearTab = app.buttons["tab-year"]
        yearTab.tap()
        let header = app.staticTexts["year-period"]
        let scroll = app.scrollViews["month-scroll"]
        let monthDay = app.buttons[dayID("month", date)]
        XCTAssertTrue(monthDay.waitForExistence(timeout: 3))
        let headerY = header.frame.minY
        let dayY = monthDay.frame.minY
        let tabWidth = yearTab.frame.width
        XCTAssertLessThan(yearTab.frame.maxX - dayTab.frame.minX, app.frame.width * 0.75)
        capture(app, named: "year header at rest")
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let finish = start.withOffset(CGVector(dx: 0, dy: -124))
        start.press(forDuration: 0.08, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertLessThan(monthDay.frame.minY, dayY - 40)
        XCTAssertEqual(header.frame.minY, headerY, accuracy: 1)
        capture(app, named: "year header during scroll")
        let barRestored = NSPredicate { _, _ in abs(yearTab.frame.width - tabWidth) < 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: barRestored, object: yearTab)], timeout: 3),
                       .completed, "the labels and width are restored when scrolling stops")

        let currentPeriod = header.label
        let arrow = app.buttons["next year"]
        XCTAssertTrue(arrow.exists)
        let target = arrow.frame
        XCTAssertTrue(app.frame.contains(target))
        // Exercise the on-screen control even when XCTest's scroll hit probe picks the content beneath it.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.midX - app.frame.minX, dy: target.midY - app.frame.minY))
            .tap()
        let jumped = NSPredicate(format: "label != %@", currentPeriod)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: jumped, object: header)], timeout: 3),
                       .completed, "the pinned arrow should still change years after scrolling")
    }

    func testSwitchingTabsPreservesTheActiveDate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let date = Calendar.current.startOfDay(for: .now)
        let dayHeader = app.staticTexts["active-date"]
        let day = app.buttons["tab-day"]
        let week = app.buttons["tab-week"]
        let year = app.buttons["tab-year"]
        expectDate(date, in: dayHeader)
        XCTAssertEqual(week.frame.height, day.frame.height, accuracy: 1)
        XCTAssertEqual(year.frame.height, day.frame.height, accuracy: 1)
        capture(app, named: "day selected in clear glass")

        week.tap()
        XCTAssertTrue(week.isSelected)
        XCTAssertTrue(app.staticTexts["week-period"].waitForExistence(timeout: 3))

        year.tap()
        XCTAssertTrue(year.isSelected)
        let currentDay = app.buttons[dayID("month", date)]
        XCTAssertTrue(currentDay.waitForExistence(timeout: 3))
        XCTAssertTrue(currentDay.isHittable)
        XCTAssertTrue(currentDay.isSelected)
        capture(app, named: "bolder calendar and clear glass")

        day.tap()
        expectDate(date, in: dayHeader)
        XCTAssertTrue(day.isSelected)
    }

    func testSwipesAndCalendarTabsOpenTheExpectedDate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let note = app.buttons["note"]
        let header = app.staticTexts["active-date"]
        let dayTab = app.buttons["tab-day"]

        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(dayTab.isSelected)
        XCTAssertFalse(app.staticTexts["peel to turn the day"].exists)
        note.tap()
        expectDate(today, in: header)
        capture(app, named: "day and glass bottom bar")

        note.swipeUp()
        expectDate(tomorrow, in: header)
        note.swipeDown()
        expectDate(today, in: header)
        note.swipeDown()
        expectDate(yesterday, in: header)
        note.swipeLeft()
        expectDate(today, in: header)
        note.swipeRight()
        expectDate(yesterday, in: header)

        let week = app.buttons["tab-week"]
        week.tap()
        XCTAssertTrue(week.isSelected)
        let focusedDay = app.buttons[dayID("week", yesterday)]
        XCTAssertTrue(focusedDay.waitForExistence(timeout: 3))
        XCTAssertTrue(focusedDay.isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-day-'")).count, 7)
        let followingWeek = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: 1, to: yesterday))
        app.buttons["next week"].tap()
        app.buttons[dayID("week", followingWeek)].tap()
        expectDate(followingWeek, in: header)
        XCTAssertTrue(dayTab.isSelected)

        let year = app.buttons["tab-year"]
        year.tap()
        XCTAssertTrue(year.isSelected)
        let overview = app.staticTexts["year-period"]
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        let initialYear = overview.label
        app.buttons["next year"].tap()
        XCTAssertNotEqual(overview.label, initialYear)

        let pickedDay = try XCTUnwrap(calendar.date(byAdding: .year, value: 1, to: followingWeek))
        let dateButton = app.buttons[dayID("month", pickedDay)]
        XCTAssertTrue(dateButton.waitForExistence(timeout: 3))
        dateButton.tap()
        expectDate(pickedDay, in: header)
        XCTAssertTrue(dayTab.isSelected)
    }

    func testCalendarOpensToActiveMonthAndShowsSavedSticker() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sticker-test", "-reset-stickers"]
        app.launch()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let monthStart = try XCTUnwrap(calendar.dateInterval(of: .month, for: today)).start
        let nextMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: monthStart))

        app.buttons["edit-note"].tap()
        let frog = app.buttons["tray-frog"]
        XCTAssertTrue(frog.waitForExistence(timeout: 3))
        frog.tap()
        let note = app.buttons["note"]
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.76)).tap()
        XCTAssertEqual(note.value as? String, "1 sticker placed")
        app.buttons["edit-note"].tap()

        let year = app.buttons["tab-year"]
        year.tap()
        XCTAssertTrue(year.isSelected)
        let decorated = app.buttons[dayID("month", today)]
        XCTAssertTrue(decorated.waitForExistence(timeout: 3))
        XCTAssertTrue(decorated.isHittable)
        XCTAssertTrue(decorated.isSelected)
        XCTAssertEqual(decorated.value as? String, "1 sticker")
        capture(app, named: "month grid with saved sticker")

        let next = app.buttons[dayID("month", nextMonth)]
        if !next.isHittable { app.scrollViews["month-scroll"].swipeUp() }
        XCTAssertTrue(next.isHittable)
        next.tap()
        expectDate(nextMonth, in: app.staticTexts["active-date"])
        XCTAssertEqual(note.value as? String, "0 stickers placed")

        year.tap()
        app.buttons["next year"].tap()
        let nextYear = try XCTUnwrap(calendar.date(byAdding: .year, value: 1, to: nextMonth))
        let jumped = app.buttons[dayID("month", nextYear)]
        XCTAssertTrue(jumped.waitForExistence(timeout: 3))
        XCTAssertTrue(jumped.isHittable)
        jumped.tap()
        expectDate(nextYear, in: app.staticTexts["active-date"])
    }

    private func expectDate(_ date: Date, in header: XCUIElement) {
        let label = date.formatted(.dateTime.day().month(.wide))
        let expected = NSPredicate(format: "exists == true AND label ==[c] %@", label)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: header)], timeout: 3),
                       .completed, "expected \(label), got \(header.exists ? header.label : "no date header")")
    }

    private func dayID(_ scope: String, _ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(scope)-day-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
