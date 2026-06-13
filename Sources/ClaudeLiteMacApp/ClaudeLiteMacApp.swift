import SwiftUI
import ClaudeLiteCore

@main
struct ClaudeLiteMacApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: ChatViewModel(services: LiveServiceContainer.live()))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 760)
    }
}
