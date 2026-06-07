import Foundation
import ClaudeLiteCore

@main
struct ClaudeLiteSmoke {
    static func main() async {
        do {
            if CommandLine.arguments.contains("--live") {
                try await runLiveSmoke()
            } else {
                try await runOfflineDiagnostics()
            }
        } catch {
            fputs("smoke_failed=\(error)\n", stderr)
            exit(1)
        }
    }

    private static func runOfflineDiagnostics() async throws {
        let sessionURL = FileManager.default.temporaryDirectory
            .appending(path: "claude-lite-offline-smoke-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: sessionURL)
        }

        let services = SmokeServiceContainer(
            bootstrapLoader: InlineBootstrapLoader(
                configuration: BootstrapConfiguration(
                    modelAPIKey: "test-offline-model-key",
                    userAPIKey: nil,
                    defaultModel: "claude-opus-4-6",
                    baseURL: URL(string: "https://api.tu-zi.com")!
                )
            ),
            secureStore: EphemeralSecureStore(),
            sessionStore: PersistentSessionStore(fileURL: sessionURL),
            modelService: OfflineModelService(),
            connectionService: OfflineConnectionService(),
            chatService: OfflineChatService(),
            logger: NoopAppLogger()
        )

        let metrics = try await exerciseChat(services: services)
        print("mode=offline")
        printMetrics(metrics)
    }

    private static func runLiveSmoke() async throws {
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
            chatService: LiveChatService(apiClient: apiClient),
            logger: NoopAppLogger()
        )

        let metrics = try await exerciseChat(services: services)
        print("mode=live")
        printMetrics(metrics)
    }

    private static func exerciseChat(services: SmokeServiceContainer) async throws -> SmokeMetrics {
        let viewModel = await MainActor.run {
            ChatViewModel(services: services)
        }

        let startBeganAt = Date()
        try await viewModel.start()
        let startMs = elapsedMilliseconds(since: startBeganAt)

        let selectedModelID = await MainActor.run {
            viewModel.selectedModel?.id ?? "<none>"
        }

        await MainActor.run {
            viewModel.draftText = "Reply with exactly ok"
        }

        let sendBeganAt = Date()
        try await viewModel.send()
        let sendMs = elapsedMilliseconds(since: sendBeganAt)

        let reply = await MainActor.run {
            viewModel.messages.last?.text ?? "<empty>"
        }

        return SmokeMetrics(
            selectedModelID: selectedModelID,
            reply: reply,
            startMs: startMs,
            sendMs: sendMs,
            residentMemoryMB: residentMemoryMegabytes()
        )
    }

    private static func printMetrics(_ metrics: SmokeMetrics) {
        print("selected_model=\(metrics.selectedModelID)")
        print("reply=\(metrics.reply)")
        print("start_ms=\(metrics.startMs)")
        print("send_ms=\(metrics.sendMs)")
        if let residentMemoryMB = metrics.residentMemoryMB {
            print("rss_mb=\(residentMemoryMB)")
        }
    }

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    private static func residentMemoryMegabytes() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return Int(info.resident_size / 1_024 / 1_024)
    }
}

private struct SmokeMetrics {
    let selectedModelID: String
    let reply: String
    let startMs: Int
    let sendMs: Int
    let residentMemoryMB: Int?
}

private struct SmokeServiceContainer: ClaudeLiteServiceContainer {
    let bootstrapLoader: BootstrapConfigurationLoading
    let secureStore: SecureStoring
    let sessionStore: SessionStoring
    let modelService: ModelServing
    let connectionService: ConnectionServing
    let chatService: ChatServing
    let logger: AppLogging
}

private struct InlineBootstrapLoader: BootstrapConfigurationLoading {
    let configuration: BootstrapConfiguration?

    func loadBootstrapConfiguration() throws -> BootstrapConfiguration? {
        configuration
    }
}

private struct OfflineModelService: ModelServing {
    func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel] {
        [
            ClaudeModel(id: "claude-opus-4-6", displayName: "Claude Opus 4.6")
        ]
    }
}

private struct OfflineConnectionService: ConnectionServing {
    func checkConnection(apiKey: String?) async -> ConnectionStatus {
        .connected
    }
}

private struct OfflineChatService: ChatServing {
    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        .assistant(text: "ok")
    }
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
