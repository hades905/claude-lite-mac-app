import Foundation

public protocol BootstrapConfigurationLoading: Sendable {
    func loadBootstrapConfiguration() throws -> BootstrapConfiguration?
}

public protocol SecureStoring: Sendable {
    func readModelAPIKey() throws -> String?
    func saveModelAPIKey(_ apiKey: String) throws
    func readUserAPIKey() throws -> String?
    func saveUserAPIKey(_ apiKey: String) throws
}

public protocol SessionStoring: Sendable {
    func load() throws -> SessionSnapshot
    func save(_ snapshot: SessionSnapshot) throws
}

public protocol ModelServing: Sendable {
    func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel]
}

public protocol ConnectionServing: Sendable {
    func checkConnection(apiKey: String?) async -> ConnectionStatus
}

public protocol ChatServing: Sendable {
    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage
}

public protocol ClaudeLiteServiceContainer: Sendable {
    var bootstrapLoader: BootstrapConfigurationLoading { get }
    var secureStore: SecureStoring { get }
    var sessionStore: SessionStoring { get }
    var modelService: ModelServing { get }
    var connectionService: ConnectionServing { get }
    var chatService: ChatServing { get }
    var logger: AppLogging { get }
}
