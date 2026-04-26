import Foundation

public struct BootstrapConfiguration: Codable, Equatable, Sendable {
    public let modelAPIKey: String
    public let userAPIKey: String?
    public let defaultModel: String
    public let baseURL: URL

    enum CodingKeys: String, CodingKey {
        case modelAPIKey = "modelApiKey"
        case userAPIKey = "userApiKey"
        case defaultModel
        case baseURL
    }

    public init(modelAPIKey: String, userAPIKey: String?, defaultModel: String, baseURL: URL) {
        self.modelAPIKey = modelAPIKey
        self.userAPIKey = userAPIKey
        self.defaultModel = defaultModel
        self.baseURL = baseURL
    }

    public static func load(from fileURL: URL) throws -> BootstrapConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(BootstrapConfiguration.self, from: data)
    }
}
