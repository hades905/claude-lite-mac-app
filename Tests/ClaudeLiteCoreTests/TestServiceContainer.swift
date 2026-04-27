import Foundation
@testable import ClaudeLiteCore

struct TestServiceContainer: ClaudeLiteServiceContainer {
    let bootstrapLoader: BootstrapConfigurationLoading
    let secureStore: SecureStoring
    let sessionStore: SessionStoring
    let modelService: ModelServing
    let connectionService: ConnectionServing
    let chatService: ChatServing

    private let storage: TestStorage

    init(
        availableModels: [ClaudeModel],
        replyText: String,
        bootstrapConfiguration: BootstrapConfiguration? = BootstrapConfiguration(
            modelAPIKey: "model-key",
            userAPIKey: "user-key",
            defaultModel: "claude-opus-4-7",
            baseURL: URL(string: "https://api.tu-zi.com")!
        )
    ) {
        let storage = TestStorage()
        self.storage = storage
        self.bootstrapLoader = TestBootstrapLoader(configuration: bootstrapConfiguration)
        self.secureStore = TestSecureStore(storage: storage)
        self.sessionStore = TestSessionStore(storage: storage)
        self.modelService = TestModelService(models: availableModels)
        self.connectionService = TestConnectionService()
        self.chatService = TestChatService(replyText: replyText)
    }

    init(
        availableModels: [ClaudeModel],
        chatService: any ChatServing,
        bootstrapConfiguration: BootstrapConfiguration? = BootstrapConfiguration(
            modelAPIKey: "model-key",
            userAPIKey: "user-key",
            defaultModel: "claude-opus-4-7",
            baseURL: URL(string: "https://api.tu-zi.com")!
        )
    ) {
        let storage = TestStorage()
        self.storage = storage
        self.bootstrapLoader = TestBootstrapLoader(configuration: bootstrapConfiguration)
        self.secureStore = TestSecureStore(storage: storage)
        self.sessionStore = TestSessionStore(storage: storage)
        self.modelService = TestModelService(models: availableModels)
        self.connectionService = TestConnectionService()
        self.chatService = chatService
    }

    var savedSnapshots: [SessionSnapshot] {
        storage.savedSnapshots
    }
}

private final class TestStorage: @unchecked Sendable {
    var modelAPIKey: String?
    var userAPIKey: String?
    var snapshot: SessionSnapshot = .empty
    var savedSnapshots: [SessionSnapshot] = []
}

private struct TestBootstrapLoader: BootstrapConfigurationLoading {
    let configuration: BootstrapConfiguration?

    func loadBootstrapConfiguration() throws -> BootstrapConfiguration? {
        configuration
    }
}

private struct TestSecureStore: SecureStoring {
    let storage: TestStorage

    func readModelAPIKey() throws -> String? {
        storage.modelAPIKey
    }

    func saveModelAPIKey(_ apiKey: String) throws {
        storage.modelAPIKey = apiKey
    }

    func readUserAPIKey() throws -> String? {
        storage.userAPIKey
    }

    func saveUserAPIKey(_ apiKey: String) throws {
        storage.userAPIKey = apiKey
    }
}

private struct TestSessionStore: SessionStoring {
    let storage: TestStorage

    func load() throws -> SessionSnapshot {
        storage.snapshot
    }

    func save(_ snapshot: SessionSnapshot) throws {
        storage.snapshot = snapshot
        storage.savedSnapshots.append(snapshot)
    }
}

private struct TestModelService: ModelServing {
    let models: [ClaudeModel]

    func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel] {
        models
    }
}

private struct TestConnectionService: ConnectionServing {
    func checkConnection(apiKey: String?) async -> ConnectionStatus {
        apiKey == nil ? .authFailed : .connected
    }
}

private struct TestChatService: ChatServing {
    let replyText: String

    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        .assistant(text: replyText)
    }
}
