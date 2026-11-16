import XCTest

final class AccessibilityAuditUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testMainWindowHasLabeledStatusModelAndVersionList() {
        let root = app.descendants(matching: .any)["store-root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "The main window root should appear.")

        let title = app.staticTexts["app-title"]
        XCTAssertTrue(title.exists, "The app title should be present for VoiceOver.")
        XCTAssertFalse((title.label.isEmpty), "The app title must have a spoken label.")

        let status = app.staticTexts["status-message"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "A plain-language status message should appear.")
        XCTAssertFalse(status.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        XCTAssertTrue(app.staticTexts["model-identifier"].exists)
        XCTAssertTrue(app.staticTexts["installed-version"].exists)
        XCTAssertTrue(app.staticTexts["compatible-version-list"].exists || app.groups["compatible-version-list"].exists || elementExists("compatible-version-list"))

        let lookup = app.buttons["lookup-button"]
        XCTAssertTrue(lookup.exists)
        XCTAssertFalse(lookup.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(lookup.label.lowercased().contains("button"), "The spoken name should be the action, not the generic word button twice.")
    }

    func testInteractiveControlsHaveNonEmptyLabels() {
        // Give the async catalog load a moment so version rows can appear on a real Mac.
        _ = app.staticTexts["status-message"].waitForExistence(timeout: 15)
        sleep(2)

        let buttons = app.buttons.allElementsBoundByIndex
        XCTAssertGreaterThan(buttons.count, 0, "The window should expose at least the Look up button.")
        for button in buttons {
            let label = button.label.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(label.isEmpty, "A button is missing an accessibility label.")
        }

        let fields = app.textFields.allElementsBoundByIndex
        XCTAssertGreaterThan(fields.count, 0, "The model identifier field should be present.")
        for field in fields {
            XCTAssertFalse(field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A text field is missing an accessibility label.")
        }
    }

    func testAuditDoesNotOpenApplePagesOrStartADownload() {
        // This test only inspects the UI. It does not click a download button,
        // so CI cannot start an Apple download or Software Update.
        let downloadButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-apple-download-"))
        // Presence is allowed; clicking is not part of this audit.
        _ = downloadButtons.count
        XCTAssertTrue(app.buttons["lookup-button"].exists)
    }

    private func elementExists(_ identifier: String) -> Bool {
        app.descendants(matching: .any)[identifier].exists
    }
}
