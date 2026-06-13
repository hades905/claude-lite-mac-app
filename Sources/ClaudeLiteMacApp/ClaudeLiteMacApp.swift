import SwiftUI
import ClaudeLiteCore

@main
struct ClaudeLiteMacApp: App {
    private let services = LiveServiceContainer.live()
    private let runtimeOptions = StreamingMarkdownRuntimeOptions.environment()

    var body: some Scene {
        WindowGroup {
            MainWindowView(
                viewModel: ChatViewModel(services: services),
                appLogger: services.logger,
                streamingMarkdownPilotEnabled: runtimeOptions.streamingMarkdownPilotEnabled
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 760)
    }
}
