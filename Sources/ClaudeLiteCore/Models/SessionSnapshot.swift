import Foundation

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let messages: [ChatMessage]
    public let selectedModelID: String?
    public let lastConnectionStatus: ConnectionStatus

    public init(messages: [ChatMessage], selectedModelID: String?, lastConnectionStatus: ConnectionStatus) {
        self.messages = messages
        self.selectedModelID = selectedModelID
        self.lastConnectionStatus = lastConnectionStatus
    }

    public static let empty = SessionSnapshot(
        messages: [],
        selectedModelID: nil,
        lastConnectionStatus: .checking
    )
}
