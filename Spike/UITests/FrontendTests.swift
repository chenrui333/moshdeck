import XCTest

final class FrontendTests: XCTestCase {
    @MainActor
    func testPhysicalSSHConnection() throws {
        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "MOSHDECK_SPIKE_HOST", "MOSHDECK_SPIKE_USER", "MOSHDECK_SPIKE_HOST_KEY",
            "MOSHDECK_SPIKE_SESSION", "MOSHDECK_SPIKE_TMUX",
        ]
        guard keys.allSatisfy({ environment[$0] != nil }) else {
            throw XCTSkip("Requires an explicitly supplied, verified physical-device host profile.")
        }
        let app = XCUIApplication()
        app.launchEnvironment = Dictionary(
            uniqueKeysWithValues: keys.compactMap { key in
                environment[key].map { (key, $0) }
            })
        app.launchEnvironment["MOSHDECK_SPIKE_MODE"] = "clean-shell"
        app.launch()
        app.tabBars.buttons["SSH"].tap()
        app.buttons["Unlock MoshDeck"].tap()
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 45), "Complete device-owner authentication on the phone.")
        guard connect.exists else { return }
        connect.tap()
        let status = app.staticTexts["remote.status"]
        let finished = NSPredicate(format: "value IN %@", ["Connected", "Failed", "Disconnected", "Cancelled"])
        expectation(for: finished, evaluatedWith: status)
        waitForExpectations(timeout: 40)
        XCTAssertEqual(status.value as? String, "Connected", "Physical connection result: \(status.label)")
    }

    @MainActor
    func testSSHSetupRequiresAppUnlock() {
        let app = XCUIApplication()
        app.launchEnvironment = ["MOSHDECK_SPIKE_HOST": "fixture.example.invalid", "MOSHDECK_SPIKE_USER": "fixture"]
        app.launch()
        app.tabBars.buttons["SSH"].tap()
        XCTAssertTrue(app.buttons["Unlock MoshDeck"].exists)
        XCTAssertFalse(app.buttons["Connect"].exists)
        XCTAssertFalse(app.textFields["Mac username"].exists)
        XCTAssertEqual(app.staticTexts["remote.status"].label, "App locked")
        XCTAssertEqual(app.staticTexts["remote.status"].value as? String, "Locked")
    }

    // Execute with -configuration Release to verify the shipped navigation.
    @MainActor
    func testReleaseStartsLockedWithoutFixtureNavigation() throws {
        #if DEBUG
            throw XCTSkip("Requires the Release application and test configuration.")
        #else
            let app = XCUIApplication()
            app.launch()
            XCTAssertTrue(app.buttons["Unlock MoshDeck"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertFalse(app.staticTexts["fixture.result"].exists)
            XCTAssertFalse(app.buttons["Run fixture"].exists)
            XCTAssertFalse(app.buttons["Connect"].exists)
            XCTAssertFalse(app.textFields["Mac username"].exists)
            XCTAssertEqual(app.staticTexts["remote.status"].value as? String, "Locked")
        #endif
    }

    @MainActor
    func testRealTerminalParserAndInputPaths() {
        let app = XCUIApplication()
        app.launch()
        let result = app.staticTexts["fixture.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        let completed = NSPredicate(format: "label BEGINSWITH 'PASS:' OR label BEGINSWITH 'FAIL:'")
        expectation(for: completed, evaluatedWith: result)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(result.label.hasPrefix("PASS:"), result.label)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic terminal fixture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTerminalAccessoryKeysDismissalAndRotation() {
        let app = XCUIApplication()
        app.launch()
        let result = app.staticTexts["fixture.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label BEGINSWITH 'PASS:'"), evaluatedWith: result)
        waitForExpectations(timeout: 30)
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let control = app.buttons["Control"]
        XCTAssertEqual(control.value as? String, "Off")
        control.tap()
        XCTAssertEqual(control.value as? String, "Armed for next key")
        app.typeText("c")
        XCTAssertEqual(control.value as? String, "Off")
        for label in ["Escape", "Tab", "Up Arrow", "Down Arrow", "Left Arrow", "Right Arrow"] {
            let key = app.buttons[label]
            XCTAssertTrue(key.isHittable, label)
            XCTAssertGreaterThanOrEqual(key.frame.width, 44)
            XCTAssertGreaterThanOrEqual(key.frame.height, 44)
            key.tap()
        }
        let keyboardScreenshot = XCTAttachment(screenshot: app.screenshot())
        keyboardScreenshot.name = "Synthetic terminal with consolidated accessory"
        keyboardScreenshot.lifetime = .keepAlways
        add(keyboardScreenshot)
        control.tap()
        app.buttons["Hide Keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["Check key input"].tap()
        XCTAssertEqual(app.staticTexts["fixture.keys"].label, "PASS: accessory bytes")
        for _ in 0..<3 {
            app.buttons["Show Keyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(control.value as? String, "Off")
            app.buttons["Hide Keyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hide Keyboard"].isHittable)
        app.buttons["Hide Keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["SSH"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic layout after keyboard rotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testNativeSessionPanelSelectionAndDismissal() {
        let app = XCUIApplication()
        app.launch()
        let open = app.buttons["Sessions"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let infra = app.buttons["session.option.infra"]
        XCTAssertTrue(infra.waitForExistence(timeout: 5))
        XCTAssertTrue(infra.isHittable)
        XCTAssertGreaterThanOrEqual(infra.frame.height, 44)
        XCTAssertTrue(app.staticTexts["Reconnect target: work"].exists)
        XCTAssertFalse(app.staticTexts["Current session: work"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic native session side panel"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        infra.tap()
        XCTAssertTrue(infra.waitForNonExistence(timeout: 5))
        XCTAssertEqual(open.value as? String, "Selected infra")
        open.tap()
        app.buttons["Close sessions"].firstMatch.tap()
        XCTAssertTrue(infra.waitForNonExistence(timeout: 5))
        XCTAssertTrue(open.isHittable)
    }

    @MainActor
    func testInteractiveSessionSwipeAndVerticalScroll() {
        let app = XCUIApplication()
        app.launch()
        let result = app.staticTexts["fixture.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label BEGINSWITH 'PASS:'"), evaluatedWith: result)
        waitForExpectations(timeout: 30)
        let terminal = app.descendants(matching: .any)["fixture.terminal"].firstMatch
        XCTAssertTrue(terminal.exists)
        let selected = app.staticTexts["fixture.swipe.session"]
        XCTAssertEqual(selected.label, "work")
        let middle = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(
            forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 25, dy: 0)), withVelocity: .slow,
            thenHoldForDuration: 0.3)
        XCTAssertEqual(selected.label, "work", "A short drag must cancel")
        middle.press(
            forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 5, dy: -150)), withVelocity: .slow,
            thenHoldForDuration: 0.2)
        XCTAssertEqual(selected.label, "work", "Vertical scrolling must not change sessions")
        let left = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let right = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(selected.label, "infra")
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(selected.label, "infra", "The first session must not wrap")
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(selected.label, "work")
        XCTAssertFalse(app.otherElements["session.swipe.preview"].exists)
        app.buttons["Sessions"].tap()
        XCTAssertTrue(app.buttons["session.option.infra"].waitForExistence(timeout: 5))
        app.buttons["session.option.infra"].tap()
        XCTAssertEqual(app.buttons["Sessions"].value as? String, "Selected infra")
        app.buttons["Scroll fixture"].tap()
        let scrollStart = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let scrollEnd = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd, withVelocity: .slow, thenHoldForDuration: 0.2)
        app.buttons["Check scrolling"].tap()
        XCTAssertEqual(app.staticTexts["fixture.scroll"].label, "PASS: viewport scrolled")
        XCTAssertEqual(selected.label, "work")
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 1)
        let selection = app.textViews["Terminal text for selection and copy"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let selectionStart = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionStart.withOffset(CGVector(dx: 170, dy: 0)))
        app.buttons["Done"].tap()
        XCTAssertEqual(selected.label, "work", "Selection interaction must not navigate")
    }

    @MainActor
    func testComposerDraftSurvivesThirtySecondBackground() {
        let app = XCUIApplication()
        app.launch()
        let compose = app.buttons["Compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15))
        compose.tap()
        let editor = app.textViews["Prompt draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Synthetic draft retention marker.")
        let before = editor.value as? String
        XCTAssertTrue(before?.contains("Synthetic draft retention marker") == true)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 30)
        app.activate()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, before)
    }

}
