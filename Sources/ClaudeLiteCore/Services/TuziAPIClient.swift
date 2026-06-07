import Foundation

public final class TuziAPIClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.tu-zi.com")!

    private let baseURL: URL
    private let session: URLSession

    public var usesURLCache: Bool {
        session.configuration.urlCache != nil
    }

    public var requestTimeoutSeconds: TimeInterval {
        session.configuration.timeoutIntervalForRequest
    }

    public var resourceTimeoutSeconds: TimeInterval {
        session.configuration.timeoutIntervalForResource
    }

    public convenience init(baseURL: URL = defaultBaseURL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        self.init(baseURL: baseURL, session: URLSession(configuration: configuration))
    }

    public init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchModels(apiKey: String) async throws -> [ClaudeModel] {
        var request = URLRequest(url: baseURL.appending(path: "/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return payload.data.map { ClaudeModel(id: $0.id, displayName: $0.id) }
    }

    public func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        var request = URLRequest(url: baseURL.appending(path: "/v1/messages"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = MessageRequest(
            model: modelID,
            maxTokens: nil,
            messages: try conversation.map {
                MessageRequest.MessagePayload(
                    role: $0.role.rawValue,
                    content: try AttachmentPromptAdapter.renderMessageContent(for: $0)
                )
            },
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(MessageResponse.self, from: data)
        let replyText = payload.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .assistant(text: replyText.isEmpty ? "(empty reply)" : replyText)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuziAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw TuziAPIError.unauthorized
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TuziAPIError.server(message)
        }
    }
}

public enum TuziAPIError: Error {
    case invalidResponse
    case unauthorized
    case server(String)
}

private struct ModelsResponse: Decodable {
    let data: [ModelItem]

    struct ModelItem: Decodable {
        let id: String
    }
}

private struct MessageRequest: Encodable {
    let model: String
    let maxTokens: Int?
    let messages: [MessagePayload]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case stream
    }

    struct MessagePayload: Encodable {
        let role: String
        let content: AttachmentPromptAdapter.MessageContent
    }
}

private struct MessageResponse: Decodable {
    let content: [ContentItem]

    struct ContentItem: Decodable {
        let type: String
        let text: String
    }
}
