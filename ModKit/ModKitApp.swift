import SwiftUI

@main
struct ModKitApp: App {
    var body: some Scene {
        Window("ModKit", id: "main") {
            ContentView()
                .environmentObject(AppSettings.shared)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
