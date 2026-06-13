import SwiftUI
import ClaudeLiteCore

@main
struct ClaudeLiteMacApp: App {
    private let services = LiveServiceContainer.live()

    var body: some Scene {
        WindowGroup {
            MainWindowView(
                viewModel: ChatViewModel(services: services),
                appLogger: services.logger
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 760)
    }
}
