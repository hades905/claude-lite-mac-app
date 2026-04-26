import Foundation

public struct LiveServiceContainer: ClaudeLiteServiceContainer {
    public let bootstrapLoader: BootstrapConfigurationLoading
    public let secureStore: SecureStoring
    public let sessionStore: SessionStoring
    public let modelService: ModelServing
    public let connectionService: ConnectionServing
    public let chatService: ChatServing

    public init(
        bootstrapLoader: BootstrapConfigurationLoading,
        secureStore: SecureStoring,
        sessionStore: SessionStoring,
        modelService: ModelServing,
        connectionService: ConnectionServing,
        chatService: ChatServing
    ) {
        self.bootstrapLoader = bootstrapLoader
        self.secureStore = secureStore
        self.sessionStore = sessionStore
        self.modelService = modelService
        self.connectionService = connectionService
        self.chatService = chatService
    }

    public static func live() -> LiveServiceContainer {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "ClaudeLiteMacApp", directoryHint: .isDirectory)
        let sessionStore = PersistentSessionStore(fileURL: appSupport.appending(path: "session.json"))
        let bootstrapLoader = LocalBootstrapConfigurationLoader(
            searchRoots: defaultBootstrapSearchRoots(
                currentDirectory: currentDirectory,
                bundleURL: Bundle.main.bundleURL
            )
        )
        let secureStore = NoopSecureStore()
        let apiClient = TuziAPIClient()
        let modelService = LiveModelService(apiClient: apiClient)
        let connectionService = LiveConnectionService(apiClient: apiClient)
        let chatService = LiveChatService(apiClient: apiClient)

        return LiveServiceContainer(
            bootstrapLoader: bootstrapLoader,
            secureStore: secureStore,
            sessionStore: sessionStore,
            modelService: modelService,
            connectionService: connectionService,
            chatService: chatService
        )
    }

    static func defaultBootstrapSearchRoots(currentDirectory: URL, bundleURL: URL) -> [URL] {
        var roots: [URL] = [currentDirectory]
        let bundleParent = bundleURL.deletingLastPathComponent()
        let bundleGrandparent = bundleParent.deletingLastPathComponent()

        for candidate in [bundleParent, bundleGrandparent] where !roots.contains(candidate) {
            roots.append(candidate)
        }

        return roots
    }
}

public struct LiveModelService: ModelServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel] {
        ModelCatalog.claudeOnly(from: try await apiClient.fetchModels(apiKey: apiKey))
    }
}

public struct LiveConnectionService: ConnectionServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func checkConnection(apiKey: String?) async -> ConnectionStatus {
        guard let apiKey, !apiKey.isEmpty else {
            return .authFailed
        }

        do {
            _ = try await apiClient.fetchModels(apiKey: apiKey)
            return .connected
        } catch TuziAPIError.unauthorized {
            return .authFailed
        } catch {
            return .disconnected
        }
    }
}

public struct LiveChatService: ChatServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        try await apiClient.sendMessage(conversation: conversation, modelID: modelID, apiKey: apiKey)
    }
}
