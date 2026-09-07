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
    func testTerminalKeyboardDismissalAndExpansion() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Fixture"].tap()
        XCTAssertTrue(app.staticTexts["fixture.result"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hide Keyboard"].isHittable)
        app.buttons["Hide Keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["SSH"].isHittable)
        app.buttons["Expand terminal"].tap()
        XCTAssertTrue(app.buttons["Restore controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hide Keyboard"].isHittable)
        app.buttons["Restore controls"].tap()
        XCTAssertTrue(app.tabBars.buttons["SSH"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["SSH"].isHittable)
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
