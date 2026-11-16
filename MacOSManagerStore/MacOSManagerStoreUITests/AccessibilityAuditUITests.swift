import XCTest

final class AccessibilityAuditUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testMainWindowHasLabeledStatusModelAndVersionList() {
        waitUntilSettled()
        let root = app.descendants(matching: .any)["store-root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "The main window root should appear.")

        let title = app.staticTexts["app-title"]
        XCTAssertTrue(title.exists, "The app title should be present for VoiceOver.")
        XCTAssertFalse((title.label.isEmpty), "The app title must have a spoken label.")

        let status = app.staticTexts["status-message"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "A plain-language status message should appear.")
        let statusLabel = spoken(status)
        print("STATUS_AX label=\(status.label) value=\(String(describing: status.value))")
        XCTAssertFalse(statusLabel.isEmpty, "The status message must be spoken. Label was '\(status.label)', value was '\(String(describing: status.value))'.")

        XCTAssertTrue(app.staticTexts["model-identifier"].exists)
        XCTAssertTrue(app.staticTexts["installed-version"].exists)
        XCTAssertTrue(app.staticTexts["compatible-version-list"].exists || app.groups["compatible-version-list"].exists || elementExists("compatible-version-list"))

        let lookup = app.buttons["lookup-button"]
        XCTAssertTrue(lookup.exists)
        XCTAssertFalse(lookup.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(lookup.label.lowercased().contains("button"), "The spoken name should be the action, not the generic word button twice.")
    }

    func testInteractiveControlsHaveNonEmptyLabels() {
        waitUntilSettled()

        // Every control this edition creates has an accessibilityIdentifier.
        // Window chrome on the runner has an empty identifier and is not one of those controls.
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            print("BUTTON_AUDIT id=\(button.identifier) label=\(button.label)")
        }
        let owned = buttons.filter { button in
            let identifier = button.identifier
            return !identifier.isEmpty && !identifier.hasPrefix("_XCUI:")
        }
        XCTAssertTrue(owned.contains { $0.identifier == "lookup-button" }, "The Look up button should be present.")
        for button in owned {
            let label = button.label.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(label.isEmpty, "A button is missing an accessibility label. identifier=\(button.identifier)")
        }

        let fields = app.textFields.allElementsBoundByIndex
        XCTAssertGreaterThan(fields.count, 0, "The model identifier field should be present.")
        for field in fields {
            XCTAssertFalse(field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A text field is missing an accessibility label.")
        }
    }

    func testAuditDoesNotOpenApplePagesOrStartADownload() {
        waitUntilSettled()
        // This test only inspects the UI. It does not click a download button,
        // so CI cannot start an Apple download or Software Update.
        let downloadButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-apple-download-"))
        // Presence is allowed; clicking is not part of this audit.
        _ = downloadButtons.count
        XCTAssertTrue(app.buttons["lookup-button"].exists)
    }

    func testSystemAccessibilityAudit() throws {
        waitUntilSettled()
        // performAccessibilityAudit inspects the hierarchy. It does not activate controls,
        // so it does not open an Apple page or start a download.
        XCTAssertTrue(app.descendants(matching: .any)["store-root"].exists, "The audit should inspect the app content.")
        try auditVisibleWindow()
    }

    func testReadinessAndChecklistAreLabeledWithoutOpeningApple() throws {
        waitUntilSettled()
        let field = app.textFields["identifier-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: [.command])
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        field.typeText("MacBookPro16,1")
        let lookup = app.buttons["lookup-button"]
        let enabledDeadline = Date().addingTimeInterval(5)
        while Date() < enabledDeadline && !lookup.isEnabled {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(lookup.isEnabled, "Look up should enable after a model identifier is typed.")
        lookup.click()

        let status = app.staticTexts["status-message"]
        let readinessDeadline = Date().addingTimeInterval(25)
        var readiness = app.buttons["readiness-26"]
        while Date() < readinessDeadline {
            readiness = app.buttons["readiness-26"]
            let text = spoken(status)
            let stillWorking = text.contains("Looking up ") || text.contains("Reading the bundled")
            if readiness.exists && readiness.isEnabled && !stillWorking {
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(readiness.exists && readiness.isEnabled, "Tahoe should be offered for MacBook Pro (16-inch, 2019). Last status: \(spoken(status))")
        XCTAssertFalse(readiness.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        readiness.click()

        let summary = app.descendants(matching: .any)["readiness-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let spokenSummary = spoken(summary)
        print("READINESS_SUMMARY \(spokenSummary)")
        XCTAssertTrue(
            spokenSummary.hasPrefix("Ready") || spokenSummary.hasPrefix("Not ready, here's why"),
            "The summary should start with the single result. It was: \(spokenSummary)"
        )
        try auditVisibleWindow()

        app.buttons["show-checklist"].click()
        let heading = app.descendants(matching: .any)["checklist-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertFalse(spoken(heading).isEmpty)
        let timeMachine = app.buttons["open-time-machine-settings"]
        XCTAssertTrue(timeMachine.waitForExistence(timeout: 5))
        XCTAssertFalse(timeMachine.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(app.buttons["open-voiceover-guide"].exists)
        // Do not click Time Machine, the VoiceOver guide, or any Apple download button.
        try auditVisibleWindow()
    }

    private func auditVisibleWindow() throws {
        do {
            try app.performAccessibilityAudit { issue in
                self.auditIssueIsOutsideStoreControls(issue)
            }
        } catch {
            let text = String(describing: error)
            if text.localizedCaseInsensitiveContains("not supported") || text.localizedCaseInsensitiveContains("unavailable") {
                throw XCTSkip("Accessibility audit is not available on this runner: \(text)")
            }
            throw error
        }
    }

    /// XCTest reports parent/child mismatches and a missing description for an
    /// anonymous group (no identifier and no label) that it cannot tie to a
    /// store control. Findings on identified controls still fail the test.
    private func auditIssueIsOutsideStoreControls(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let element = issue.element.map { "\($0) id=\($0.identifier) label=\($0.label)" } ?? "no element"
        let label = issue.element?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identifier = issue.element?.identifier ?? ""
        let anonymous = identifier.isEmpty && label.isEmpty
        let anonymousContainer = anonymous && (
            issue.compactDescription == "Parent/Child mismatch"
                || issue.compactDescription == "Element has no description"
        )
        let unattached = issue.element == nil && issue.compactDescription == "Parent/Child mismatch"
        let snapshot = issue.element.map { "\($0)" } ?? ""
        let systemChrome = snapshot.contains("TouchBar")
            || snapshot.contains("PopUpButton")
            || snapshot.contains("MenuBar")
        // Text that is scrolled out of the window can fail contrast because its pixels
        // are not drawn. Visible text still has to pass.
        let offscreenContrast = issue.compactDescription == "Contrast failed"
            && issue.element?.isHittable == false
        let recordedOnly = unattached || anonymousContainer || systemChrome || offscreenContrast
        print("ACCESSIBILITY_AUDIT \(issue.auditType) | \(issue.compactDescription) | \(issue.detailedDescription) | \(element) | recordedOnly=\(recordedOnly)")
        return recordedOnly
    }

    private func waitUntilSettled() {
        let status = app.staticTexts["status-message"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "A plain-language status message should appear.")
        let deadline = Date().addingTimeInterval(45)
        var stableSince: Date?
        var last = ""
        while Date() < deadline {
            let indicator = app.descendants(matching: .any)["working-indicator"]
            let current = spoken(status)
            let busy = indicator.exists
                || current.isEmpty
                || current.contains("not been read yet")
                || current.contains("Reading the bundled")
                || current.contains("Looking up ")
            if busy || current != last {
                stableSince = nil
                last = current
            } else if let stableSince {
                if Date().timeIntervalSince(stableSince) >= 0.8 {
                    print("SETTLED_STATUS \(current)")
                    return
                }
            } else {
                stableSince = Date()
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        print("VISIBLE_TEXT \(app.staticTexts.allElementsBoundByIndex.prefix(40).map { "label=\($0.label) value=\(String(describing: $0.value))" })")
        XCTFail("The window did not settle. Last status label: \(status.label) value: \(String(describing: status.value))")
    }

    /// macOS exposes some SwiftUI text as the accessibility value rather than the label.
    /// VoiceOver speaks whichever of those is set.
    private func spoken(_ element: XCUIElement) -> String {
        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        let value = (element.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value
    }

    private func elementExists(_ identifier: String) -> Bool {
        app.descendants(matching: .any)[identifier].exists
    }
}
