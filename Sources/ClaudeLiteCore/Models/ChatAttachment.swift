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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Kind.self, forKey: .kind)
        localURL = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
    }
}
