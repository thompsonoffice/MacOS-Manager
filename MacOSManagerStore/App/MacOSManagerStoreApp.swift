import SwiftUI

@main
struct MacOSManagerStoreApp: App {
    @StateObject private var session = StoreSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 720, minHeight: 640)
        }
        .defaultSize(width: 880, height: 980)
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
