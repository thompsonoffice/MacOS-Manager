import AppKit
import SwiftUI

enum MainWindow {
    static let id = "main"
}

@main
struct MacOSManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session = Session()

    var body: some Scene {
        let _ = bindReopen()
        WindowGroup(id: MainWindow.id) {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 880, minHeight: 600)
                .onAppear {
                    appDelegate.openMainWindow = { openWindow(id: MainWindow.id) }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .windowArrangement) {
                ShowMainWindowButton()
            }
        }
    }

    private func bindReopen() -> Bool {
        appDelegate.openMainWindow = { openWindow(id: MainWindow.id) }
        return true
    }
}

/// The menu bar stays available when every window is closed, so this is where the reopen action is registered.
private struct ShowMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show macOS Manager") {
            AppDelegate.shared?.openMainWindow = { openWindow(id: MainWindow.id) }
            AppDelegate.shared?.ensureMainWindow()
        }
        .keyboardShortcut("0", modifiers: .command)
        .onAppear {
            AppDelegate.shared?.openMainWindow = { openWindow(id: MainWindow.id) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var openMainWindow: (() -> Void)?
    private var opening = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        opening = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.opening = false
            self?.ensureMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensureMainWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ensureMainWindow()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
        DispatchQueue.main.async { [weak self] in
            guard NSApp.isActive else { return }
            self?.ensureMainWindow(ignoring: closing)
        }
    }

    func ensureMainWindow(ignoring: NSWindow? = nil) {
        let candidates = NSApp.windows.filter { window in
            window !== ignoring && window.canBecomeMain && !window.isSheet
        }
        if let visible = candidates.first(where: \.isVisible) {
            if visible.isMiniaturized {
                visible.deminiaturize(nil)
            }
            visible.makeKeyAndOrderFront(nil)
            return
        }
        if let hidden = candidates.first {
            hidden.setIsVisible(true)
            hidden.makeKeyAndOrderFront(nil)
            return
        }
        guard !opening else { return }
        opening = true
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.opening = false
        }
    }
}

enum Announcer {
    /// Posts a VoiceOver announcement through NSAccessibility. The plain-language sentence is the announcement. Raw command text stays on screen.
    static func say(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: trimmed,
                .priority: NSAccessibilityPriorityLevel.high,
            ]
        )
    }
}
