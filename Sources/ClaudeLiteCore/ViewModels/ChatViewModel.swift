import Foundation
import Observation

@MainActor
@Observable
public final class ChatViewModel {
    public static let pendingReplyText = "正在回复..."

    public private(set) var messages: [ChatMessage] = []
    public private(set) var availableModels: [ClaudeModel] = []
    public private(set) var selectedModel: ClaudeModel?
    public private(set) var connectionStatus: ConnectionStatus = .checking
    public private(set) var isStarting = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    public var draftText = ""
    public private(set) var draftAttachments: [ChatAttachment] = []
    public var availableModelSections: [ClaudeModelSection] {
        ModelCatalog.coreClaudeSections(from: availableModels)
    }

    private let services: any ClaudeLiteServiceContainer
    private var bootstrapConfiguration: BootstrapConfiguration?

    public init(services: any ClaudeLiteServiceContainer) {
        self.services = services
    }

    public func start() async throws {
        let startedAt = Date()
        isStarting = true
        defer { isStarting = false }
        log(event: "start_begin")

        bootstrapConfiguration = try services.bootstrapLoader.loadBootstrapConfiguration()

        let snapshot = try services.sessionStore.load()
        messages = snapshot.messages
        connectionStatus = snapshot.lastConnectionStatus

        let apiKey = try resolvedModelAPIKey()
        connectionStatus = .checking

        if let apiKey, !apiKey.isEmpty {
            availableModels = try await services.modelService.fetchClaudeModels(apiKey: apiKey)
            selectedModel = ModelCatalog.resolveSelection(
                available: availableModels,
                storedSelection: snapshot.selectedModelID,
                bootstrapDefault: bootstrapConfiguration?.defaultModel
            )
            connectionStatus = .connected
            log(
                event: "start_connected",
                metadata: [
                    "modelCount": "\(availableModels.count)",
                    "messageCount": "\(messages.count)"
                ]
            )
        } else {
            availableModels = []
            selectedModel = nil
            connectionStatus = .authFailed
            log(event: "start_auth_failed", metadata: ["messageCount": "\(messages.count)"])
        }

        try persistSnapshot()
        logStartCompleted(startedAt: startedAt)
    }

    public func refreshConnection() async {
        do {
            let apiKey = try resolvedModelAPIKey()
            connectionStatus = .checking
            connectionStatus = await services.connectionService.checkConnection(apiKey: apiKey)
            log(event: "connection_checked", metadata: ["status": connectionStatus.rawValue])

            if let apiKey, connectionStatus == .connected {
                availableModels = try await services.modelService.fetchClaudeModels(apiKey: apiKey)
                selectedModel = ModelCatalog.resolveSelection(
                    available: availableModels,
                    storedSelection: selectedModel?.id,
                    bootstrapDefault: bootstrapConfiguration?.defaultModel
                )
            }

            try persistSnapshot()
        } catch {
            errorMessage = readableMessage(for: error)
            connectionStatus = .disconnected
            log(event: "connection_failed", metadata: ["error": String(describing: type(of: error))])
        }
    }

    public func selectModel(id: String) {
        selectedModel = availableModels.first(where: { $0.id == id })
        try? persistSnapshot()
    }

    public func addAttachment(from fileURL: URL) {
        let isImage = ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(fileURL.pathExtension.lowercased())
        let attachment = ChatAttachment(
            name: fileURL.lastPathComponent,
            kind: isImage ? .image : .file,
            localURL: fileURL
        )
        draftAttachments.append(attachment)
    }

    public func removeDraftAttachment(id: UUID) {
        draftAttachments.removeAll { $0.id == id }
    }

    public func send() async throws {
        guard !isSending else {
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !draftAttachments.isEmpty else {
            return
        }

        guard let apiKey = try resolvedModelAPIKey(), !apiKey.isEmpty else {
            connectionStatus = .authFailed
            throw ChatViewModelError.missingAPIKey
        }

        guard let selectedModel else {
            throw ChatViewModelError.missingModel
        }

        isSending = true
        defer { isSending = false }

        errorMessage = nil
        let outgoingForRequest = ChatMessage.user(text: trimmed, attachments: draftAttachments)
        let outgoing = outgoingForRequest.replacing(status: .pending)
        let conversation = messages.filter { $0.status != .pending } + [outgoingForRequest]
        let pendingReplyID = UUID()
        let pendingReply = ChatMessage.assistant(
            id: pendingReplyID,
            text: Self.pendingReplyText,
            status: .pending
        )
        messages.append(outgoing)
        messages.append(pendingReply)
        draftText = ""
        draftAttachments = []
        try persistSnapshot()
        let sendStartedAt = Date()
        log(
            event: "send_started",
            metadata: [
                "model": selectedModel.id,
                "messageCount": "\(conversation.count)",
                "attachmentCount": "\(outgoingForRequest.attachments.count)"
            ]
        )

        do {
            let reply = try await services.chatService.sendMessage(
                conversation: conversation,
                modelID: selectedModel.id,
                apiKey: apiKey
            )
            replaceMessage(
                id: outgoing.id,
                with: outgoingForRequest.replacing(status: .sent)
            )
            replaceMessage(
                id: pendingReplyID,
                with: reply.replacing(id: pendingReplyID, status: .sent)
            )
            connectionStatus = .connected
            try persistSnapshot()
            log(
                event: "send_succeeded",
                metadata: [
                    "durationMs": elapsedMilliseconds(since: sendStartedAt),
                    "model": selectedModel.id,
                    "messageCount": "\(conversation.count)",
                    "attachmentCount": "\(outgoingForRequest.attachments.count)"
                ]
            )
        } catch {
            replaceMessage(
                id: outgoing.id,
                with: outgoingForRequest.replacing(status: .sent)
            )
            messages.removeAll { $0.id == pendingReplyID }
            errorMessage = readableMessage(for: error)
            if !isLocalAttachmentError(error) {
                connectionStatus = .disconnected
            }
            try persistSnapshot()
            log(
                event: "send_failed",
                metadata: [
                    "durationMs": elapsedMilliseconds(since: sendStartedAt),
                    "model": selectedModel.id,
                    "messageCount": "\(conversation.count)",
                    "attachmentCount": "\(outgoingForRequest.attachments.count)",
                    "error": String(describing: type(of: error))
                ]
            )
            throw error
        }
    }

    private func resolvedModelAPIKey() throws -> String? {
        return bootstrapConfiguration?.modelAPIKey
    }

    private func persistSnapshot() throws {
        let snapshot = SessionSnapshot(
            messages: messages.compactMap { message in
                if message.role == .assistant, message.status == .pending {
                    return nil
                }

                if message.role == .user, message.status == .pending {
                    return message.replacing(status: .sent)
                }

                return message
            },
            selectedModelID: selectedModel?.id,
            lastConnectionStatus: connectionStatus
        )
        try services.sessionStore.save(SessionSnapshotTrimmer.trim(snapshot))
    }

    private func replaceMessage(id: UUID, with updated: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            messages.append(updated)
            return
        }

        messages[index] = updated
    }

    private func readableMessage(for error: Error) -> String {
        switch error {
        case TuziAPIError.unauthorized:
            "Key not accepted."
        case ChatViewModelError.missingAPIKey:
            "Key not accepted."
        case ChatViewModelError.missingModel:
            "Selected model is unavailable."
        case AttachmentPromptAdapterError.imageTooLarge:
            "Image is too large. Choose one under 20 MB."
        case AttachmentPromptAdapterError.unreadableImage:
            "Image could not be read."
        default:
            "Can’t reach server."
        }
    }

    private func isLocalAttachmentError(_ error: Error) -> Bool {
        switch error {
        case AttachmentPromptAdapterError.imageTooLarge:
            true
        case AttachmentPromptAdapterError.unreadableImage:
            true
        default:
            false
        }
    }

    private func log(event: String, metadata: [String: String] = [:]) {
        try? services.logger.record(event: event, metadata: metadata)
    }

    private func logStartCompleted(startedAt: Date) {
        log(
            event: "start_completed",
            metadata: [
                "durationMs": elapsedMilliseconds(since: startedAt),
                "messageCount": "\(messages.count)",
                "modelCount": "\(availableModels.count)",
                "status": connectionStatus.rawValue
            ]
        )
    }

    private func elapsedMilliseconds(since startedAt: Date) -> String {
        "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))"
    }
}

public enum ChatViewModelError: Error {
    case missingAPIKey
    case missingModel
}
