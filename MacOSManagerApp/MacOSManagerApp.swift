import SwiftUI

@main
struct MacOSManagerApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 880, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

enum Announcer {
    static func say(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
