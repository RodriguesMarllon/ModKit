import SwiftUI

@main
struct ModScanApp: App {
    var body: some Scene {
        Window("ModScan", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
