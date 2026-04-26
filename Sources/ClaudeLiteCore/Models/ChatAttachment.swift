import Foundation

public struct ChatAttachment: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case file
        case image
    }

    public let id: UUID
    public let name: String
    public let kind: Kind
    public let localURL: URL?

    public init(id: UUID = UUID(), name: String, kind: Kind, localURL: URL? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.localURL = localURL
    }
}
