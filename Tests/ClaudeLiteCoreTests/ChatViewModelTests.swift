import Foundation
import Testing
@testable import ClaudeLiteCore

@MainActor
struct ChatViewModelTests {
    @Test
    func startUsesBootstrapConfigurationWithoutTouchingSecureStore() async throws {
        let services = RecordingServiceContainer(
            secureStore: ThrowingSecureStore(),
            bootstrapConfiguration: BootstrapConfiguration(
                modelAPIKey: "bootstrap-model-key",
                userAPIKey: "bootstrap-user-key",
                defaultModel: "claude-opus-4-7",
                baseURL: URL(string: "https://api.tu-zi.com")!
            ),
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "ok"
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()

        #expect(services.recordingModelService.recordedAPIKeys == ["bootstrap-model-key"])
        #expect(services.recordingConnectionService.recordedAPIKeys.isEmpty)
        #expect(viewModel.connectionStatus == .connected)
    }

    @Test
    func refreshAndSendPreferBootstrapModelAPIKeyOverSecureStoreValue() async throws {
        let services = RecordingServiceContainer(
            secureStore: LegacySecureStore(modelAPIKey: "stale-key", userAPIKey: "stale-user-key"),
            bootstrapConfiguration: BootstrapConfiguration(
                modelAPIKey: "bootstrap-model-key",
                userAPIKey: "bootstrap-user-key",
                defaultModel: "claude-opus-4-7",
                baseURL: URL(string: "https://api.tu-zi.com")!
            ),
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "ok"
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        await viewModel.refreshConnection()
        viewModel.draftText = "hello"
        try await viewModel.send()

        #expect(services.recordingModelService.recordedAPIKeys == [
            "bootstrap-model-key",
            "bootstrap-model-key"
        ])
        #expect(services.recordingConnectionService.recordedAPIKeys == [
            "bootstrap-model-key"
        ])
        #expect(services.recordingChatService.recordedAPIKeys == ["bootstrap-model-key"])
    }

    @Test
    func sendAppendsUserAndAssistantMessagesAndClearsDraft() async throws {
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "ok"
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "Reply with ok"

        try await viewModel.send()

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.first?.text == "Reply with ok")
        #expect(viewModel.messages.last?.text == "ok")
        #expect(viewModel.draftText.isEmpty)
        #expect(services.savedSnapshots.last?.selectedModelID == "claude-opus-4-7")
    }

    @Test
    func sendRecordsDiagnosticsWithoutMessageText() async throws {
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "private assistant reply"
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "private user prompt"

        try await viewModel.send()

        #expect(services.logEntries.contains { $0.event == "send_succeeded" })
        #expect(services.logEntries.contains { entry in
            entry.metadata["model"] == "claude-opus-4-7" &&
                entry.metadata["messageCount"] == "1"
        })
        #expect(!services.logEntries.contains { entry in
            entry.metadata.values.contains("private user prompt") ||
                entry.metadata.values.contains("private assistant reply")
        })
    }

    @Test
    func startRecordsDurationDiagnosticsWithoutSecrets() async throws {
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "ok",
            bootstrapConfiguration: BootstrapConfiguration(
                modelAPIKey: "private-model-key",
                userAPIKey: "private-user-key",
                defaultModel: "claude-opus-4-7",
                baseURL: URL(string: "https://api.tu-zi.com")!
            )
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()

        let completedEntry = try #require(services.logEntries.last { $0.event == "start_completed" })
        #expect(completedEntry.metadata["status"] == ConnectionStatus.connected.rawValue)
        #expect(completedEntry.metadata["modelCount"] == "1")
        #expect(completedEntry.metadata["messageCount"] == "0")
        #expect(completedEntry.metadata["durationMs"] != nil)
        #expect(!services.logEntries.contains { entry in
            entry.metadata.values.contains("private-model-key") ||
                entry.metadata.values.contains("private-user-key")
        })
    }

    @Test
    func oversizedImageFailureShowsActionableErrorMessage() async throws {
        let chatService = FailingChatService(error: AttachmentPromptAdapterError.imageTooLarge("huge.png"))
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            chatService: chatService
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "describe image"

        await #expect(throws: AttachmentPromptAdapterError.imageTooLarge("huge.png")) {
            try await viewModel.send()
        }

        #expect(viewModel.errorMessage == "Image is too large. Choose one under 20 MB.")
        #expect(viewModel.connectionStatus == .connected)
    }

    @Test
    func sendShowsPendingAssistantMessageUntilReplyArrives() async throws {
        let chatService = ControlledChatService()
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            chatService: chatService
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "Show me markdown"

        let sendTask = Task {
            try await viewModel.send()
        }

        await Task.yield()
        await Task.yield()

        #expect(viewModel.isSending)
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.role == .assistant)
        #expect(viewModel.messages.last?.text == "正在回复...")
        #expect(viewModel.messages.last?.status == .pending)
        #expect(services.savedSnapshots.last?.messages.count == 1)

        chatService.resume(with: .assistant(text: "**done**"))
        try await sendTask.value

        #expect(!viewModel.isSending)
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.text == "**done**")
        #expect(viewModel.messages.last?.status == .sent)
    }

    @Test
    func sendMarksOutgoingImageMessagePendingUntilReplyArrives() async throws {
        let chatService = ControlledChatService()
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            chatService: chatService
        )
        let viewModel = ChatViewModel(services: services)
        let imageURL = try writeTemporaryImage(named: "sample.png")

        try await viewModel.start()
        viewModel.draftText = "Describe this image"
        viewModel.addAttachment(from: imageURL)

        let sendTask = Task {
            try await viewModel.send()
        }

        await waitUntilSending(viewModel)

        let outgoing = try #require(viewModel.messages.first)
        #expect(outgoing.role == .user)
        #expect(outgoing.status == .pending)
        #expect(outgoing.attachments.first?.kind == .image)

        chatService.resume(with: .assistant(text: "done"))
        try await sendTask.value

        #expect(viewModel.messages.first?.status == .sent)
    }

    @Test
    func sendIgnoresDuplicateCallWhileReplyIsPending() async throws {
        let chatService = ControlledChatService()
        let services = TestServiceContainer(
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            chatService: chatService
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "First message"

        let firstSendTask = Task {
            try await viewModel.send()
        }

        await waitUntilSending(viewModel)
        viewModel.draftText = "Second message"

        let secondSendTask = Task {
            try await viewModel.send()
        }

        await Task.yield()
        await Task.yield()

        #expect(await chatService.recordedConversations().count == 1)
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.draftText == "Second message")

        await chatService.resumeAll(with: .assistant(text: "done"))
        try await firstSendTask.value
        try await secondSendTask.value

        #expect(viewModel.messages.count == 2)
        #expect(!viewModel.isSending)
    }

    @Test
    func secondSequentialSendUsesCompletedHistoryOnly() async throws {
        let services = RecordingServiceContainer(
            secureStore: ThrowingSecureStore(),
            bootstrapConfiguration: BootstrapConfiguration(
                modelAPIKey: "bootstrap-model-key",
                userAPIKey: "bootstrap-user-key",
                defaultModel: "claude-opus-4-7",
                baseURL: URL(string: "https://api.tu-zi.com")!
            ),
            availableModels: [
                ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
            ],
            replyText: "ok"
        )
        let viewModel = ChatViewModel(services: services)

        try await viewModel.start()
        viewModel.draftText = "First"
        try await viewModel.send()
        viewModel.draftText = "Second"
        try await viewModel.send()

        let conversations = services.recordingChatService.recordedConversations
        #expect(conversations.count == 2)
        #expect(conversations[0].map(\.text) == ["First"])
        #expect(conversations[1].map(\.text) == ["First", "ok", "Second"])
        #expect(conversations[1].allSatisfy { $0.status == .sent })
    }

    private func waitUntilSending(_ viewModel: ChatViewModel) async {
        for _ in 0..<20 {
            if viewModel.isSending {
                return
            }

            await Task.yield()
        }
    }

    private func writeTemporaryImage(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChatViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appending(path: name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)
        return fileURL
    }
}

private final class ControlledChatService: ChatServing, @unchecked Sendable {
    private let state = ControlledChatServiceState()

    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        try await state.waitForReply(conversation: conversation)
    }

    func resume(with reply: ChatMessage) {
        Task {
            await state.resume(with: reply)
        }
    }

    func resumeAll(with reply: ChatMessage) async {
        await state.resumeAll(with: reply)
    }

    func recordedConversations() async -> [[ChatMessage]] {
        await state.recordedConversations
    }
}

private struct FailingChatService: ChatServing {
    let error: Error

    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        throw error
    }
}

private actor ControlledChatServiceState {
    private var continuations: [CheckedContinuation<ChatMessage, Error>] = []
    private(set) var recordedConversations: [[ChatMessage]] = []

    func waitForReply(conversation: [ChatMessage]) async throws -> ChatMessage {
        recordedConversations.append(conversation)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func resume(with reply: ChatMessage) {
        guard !continuations.isEmpty else {
            return
        }

        continuations.removeFirst().resume(returning: reply)
    }

    func resumeAll(with reply: ChatMessage) {
        let continuations = self.continuations
        self.continuations = []
        continuations.forEach { $0.resume(returning: reply) }
    }
}

private struct RecordingServiceContainer: ClaudeLiteServiceContainer {
    let bootstrapLoader: BootstrapConfigurationLoading
    let secureStore: SecureStoring
    let sessionStore: SessionStoring
    let modelService: any ModelServing
    let connectionService: any ConnectionServing
    let chatService: any ChatServing
    let logger: AppLogging

    let recordingModelService: RecordingModelService
    let recordingConnectionService: RecordingConnectionService
    let recordingChatService: RecordingChatService

    init(
        secureStore: SecureStoring,
        bootstrapConfiguration: BootstrapConfiguration,
        availableModels: [ClaudeModel],
        replyText: String
    ) {
        let modelService = RecordingModelService(models: availableModels)
        let connectionService = RecordingConnectionService()
        let chatService = RecordingChatService(replyText: replyText)

        self.bootstrapLoader = InlineBootstrapLoader(configuration: bootstrapConfiguration)
        self.secureStore = secureStore
        self.sessionStore = InlineSessionStore()
        self.modelService = modelService
        self.connectionService = connectionService
        self.chatService = chatService
        self.logger = NoopAppLogger()
        self.recordingModelService = modelService
        self.recordingConnectionService = connectionService
        self.recordingChatService = chatService
    }
}

private struct ThrowingSecureStore: SecureStoring {
    func readModelAPIKey() throws -> String? {
        throw TestSecureStoreError.unexpectedAccess
    }

    func saveModelAPIKey(_ apiKey: String) throws {
        throw TestSecureStoreError.unexpectedAccess
    }

    func readUserAPIKey() throws -> String? {
        throw TestSecureStoreError.unexpectedAccess
    }

    func saveUserAPIKey(_ apiKey: String) throws {
        throw TestSecureStoreError.unexpectedAccess
    }
}

private struct LegacySecureStore: SecureStoring {
    let modelAPIKey: String?
    let userAPIKey: String?

    func readModelAPIKey() throws -> String? {
        modelAPIKey
    }

    func saveModelAPIKey(_ apiKey: String) throws {}

    func readUserAPIKey() throws -> String? {
        userAPIKey
    }

    func saveUserAPIKey(_ apiKey: String) throws {}
}

private enum TestSecureStoreError: Error {
    case unexpectedAccess
}

private struct InlineBootstrapLoader: BootstrapConfigurationLoading {
    let configuration: BootstrapConfiguration?

    func loadBootstrapConfiguration() throws -> BootstrapConfiguration? {
        configuration
    }
}

private final class InlineSessionStore: SessionStoring, @unchecked Sendable {
    private var snapshot: SessionSnapshot = .empty

    func load() throws -> SessionSnapshot {
        snapshot
    }

    func save(_ snapshot: SessionSnapshot) throws {
        self.snapshot = snapshot
    }
}

private final class RecordingModelService: ModelServing, @unchecked Sendable {
    private(set) var recordedAPIKeys: [String] = []
    private let models: [ClaudeModel]

    init(models: [ClaudeModel]) {
        self.models = models
    }

    func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel] {
        recordedAPIKeys.append(apiKey)
        return models
    }
}

private final class RecordingConnectionService: ConnectionServing, @unchecked Sendable {
    private(set) var recordedAPIKeys: [String?] = []

    func checkConnection(apiKey: String?) async -> ConnectionStatus {
        recordedAPIKeys.append(apiKey)
        return apiKey == nil ? .authFailed : .connected
    }
}

private final class RecordingChatService: ChatServing, @unchecked Sendable {
    private(set) var recordedAPIKeys: [String] = []
    private(set) var recordedConversations: [[ChatMessage]] = []
    private let replyText: String

    init(replyText: String) {
        self.replyText = replyText
    }

    func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        recordedAPIKeys.append(apiKey)
        recordedConversations.append(conversation)
        return .assistant(text: replyText)
    }
}
