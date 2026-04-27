import Foundation
import ClaudeLiteCore

@main
struct ClaudeLiteSmoke {
    static func main() async {
        do {
            let fileManager = FileManager.default
            let projectRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            let bootstrapLoader = LocalBootstrapConfigurationLoader(searchRoots: [projectRoot])
            let bootstrap = try bootstrapLoader.loadBootstrapConfiguration()
            let sessionURL = fileManager.temporaryDirectory
                .appending(path: "claude-lite-smoke-session.json")
            let apiClient = TuziAPIClient(baseURL: bootstrap?.baseURL ?? URL(string: "https://api.tu-zi.com")!)
            let services = SmokeServiceContainer(
                bootstrapLoader: bootstrapLoader,
                secureStore: EphemeralSecureStore(),
                sessionStore: PersistentSessionStore(fileURL: sessionURL),
                modelService: LiveModelService(apiClient: apiClient),
                connectionService: LiveConnectionService(apiClient: apiClient),
                chatService: LiveChatService(apiClient: apiClient)
            )

            let viewModel = await MainActor.run {
                ChatViewModel(services: services)
            }

            try await viewModel.start()

            let selectedModelID = await MainActor.run {
                viewModel.selectedModel?.id ?? "<none>"
            }

            await MainActor.run {
                viewModel.draftText = "Reply with exactly ok"
            }

            try await viewModel.send()

            let reply = await MainActor.run {
                viewModel.messages.last?.text ?? "<empty>"
            }

            print("selected_model=\(selectedModelID)")
            print("reply=\(reply)")
        } catch {
            fputs("smoke_failed=\(error)\n", stderr)
            exit(1)
        }
    }
}

private struct SmokeServiceContainer: ClaudeLiteServiceContainer {
    let bootstrapLoader: BootstrapConfigurationLoading
    let secureStore: SecureStoring
    let sessionStore: SessionStoring
    let modelService: ModelServing
    let connectionService: ConnectionServing
    let chatService: ChatServing
}

private final class EphemeralSecureStore: SecureStoring, @unchecked Sendable {
    private var modelAPIKey: String?
    private var userAPIKey: String?

    func readModelAPIKey() throws -> String? {
        modelAPIKey
    }

    func saveModelAPIKey(_ apiKey: String) throws {
        modelAPIKey = apiKey
    }

    func readUserAPIKey() throws -> String? {
        userAPIKey
    }

    func saveUserAPIKey(_ apiKey: String) throws {
        userAPIKey = apiKey
    }
}
