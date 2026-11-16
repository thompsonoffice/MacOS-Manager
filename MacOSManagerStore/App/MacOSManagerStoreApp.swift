import SwiftUI

@main
struct MacOSManagerStoreApp: App {
    @StateObject private var session = StoreSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 720, minHeight: 560)
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
