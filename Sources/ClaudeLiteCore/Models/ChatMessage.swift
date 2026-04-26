import Foundation

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case pending
        case sent
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let attachments: [ChatAttachment]
    public let createdAt: Date
    public let status: Status

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        status: Status = .sent
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.status = status
    }

    public static func user(
        text: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date()
    ) -> ChatMessage {
        ChatMessage(role: .user, text: text, attachments: attachments, createdAt: createdAt)
    }

    public static func assistant(
        id: UUID = UUID(),
        text: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        status: Status = .sent
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .assistant,
            text: text,
            attachments: attachments,
            createdAt: createdAt,
            status: status
        )
    }

    public func replacing(id: UUID? = nil, status: Status? = nil) -> ChatMessage {
        ChatMessage(
            id: id ?? self.id,
            role: role,
            text: text,
            attachments: attachments,
            createdAt: createdAt,
            status: status ?? self.status
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case attachments
        case createdAt
        case status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .sent
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
    }
}
