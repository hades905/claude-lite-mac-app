import Foundation
import Testing
@testable import ClaudeLiteCore

@Suite(.serialized)
struct TuziAPIClientTests {
    @Test
    func defaultClientUsesNonCachingSession() {
        let client = TuziAPIClient()

        #expect(client.usesURLCache == false)
    }

    @Test
    func defaultClientUsesShortNetworkTimeouts() {
        let client = TuziAPIClient()

        #expect(client.requestTimeoutSeconds == 30)
        #expect(client.resourceTimeoutSeconds == 45)
    }

    @Test
    func sendMessageDoesNotSetLocalMaxTokenCap() async throws {
        RecordingURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TuziAPIClient(
            baseURL: URL(string: "https://api.tu-zi.test")!,
            session: session
        )

        _ = try await client.sendMessage(
            conversation: [.user(text: "Write a long explanation.")],
            modelID: "claude-3-5-haiku",
            apiKey: "test-key"
        )

        let body = try #require(RecordingURLProtocol.lastRequestBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "claude-3-5-haiku")
        #expect(json["max_tokens"] == nil)
    }

    @Test
    func sendMessageEncodesImageAttachmentAsClaudeVisionContentBlock() async throws {
        RecordingURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TuziAPIClient(
            baseURL: URL(string: "https://api.tu-zi.test")!,
            session: session
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let imageURL = try writeTemporaryFile(named: "sample.png", data: imageData)

        _ = try await client.sendMessage(
            conversation: [
                .user(
                    text: "Describe this image.",
                    attachments: [
                        ChatAttachment(name: "sample.png", kind: .image, localURL: imageURL)
                    ]
                )
            ],
            modelID: "claude-3-5-sonnet",
            apiKey: "test-key"
        )

        let body = try #require(RecordingURLProtocol.lastRequestBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let firstMessage = try #require(messages.first)
        let content = try #require(firstMessage["content"] as? [[String: Any]])
        let textBlock = try #require(content.first { $0["type"] as? String == "text" })
        let imageBlock = try #require(content.first { $0["type"] as? String == "image" })
        let source = try #require(imageBlock["source"] as? [String: Any])
        let requestString = String(data: body, encoding: .utf8) ?? ""

        #expect(firstMessage["role"] as? String == "user")
        #expect(textBlock["text"] as? String == "Describe this image.")
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == imageData.base64EncodedString())
        #expect(!requestString.contains("[Image attached:"))
    }

    @Test
    func sendMessageSummarizesRestoredImageAttachmentWithoutLocalFile() async throws {
        RecordingURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TuziAPIClient(
            baseURL: URL(string: "https://api.tu-zi.test")!,
            session: session
        )

        _ = try await client.sendMessage(
            conversation: [
                .user(
                    text: "Earlier image",
                    attachments: [
                        ChatAttachment(name: "chart.png", kind: .image, localURL: nil)
                    ]
                ),
                .assistant(text: "I can see the chart."),
                .user(text: "Continue from that context.")
            ],
            modelID: "claude-3-5-haiku",
            apiKey: "test-key"
        )

        let body = try #require(RecordingURLProtocol.lastRequestBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let firstMessage = try #require(messages.first)

        #expect(firstMessage["role"] as? String == "user")
        #expect(firstMessage["content"] as? String == "[Image attached: chart.png]\n\nEarlier image")
    }

    @Test
    func serverErrorMessageIsRedactedAndBounded() async throws {
        RecordingURLProtocol.reset()
        RecordingURLProtocol.responseStatusCode = 500
        RecordingURLProtocol.responseBody = Data(
            ("server failed token=secret-token-123456 " + String(repeating: "x", count: 4_000)).utf8
        )
        defer {
            RecordingURLProtocol.reset()
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TuziAPIClient(
            baseURL: URL(string: "https://api.tu-zi.test")!,
            session: session
        )

        do {
            _ = try await client.sendMessage(
                conversation: [.user(text: "hello")],
                modelID: "claude-3-5-haiku",
                apiKey: "test-key"
            )
            Issue.record("Expected server error")
        } catch TuziAPIError.server(let message) {
            #expect(message.contains("token=<redacted>"))
            #expect(!message.contains("secret-token-123456"))
            #expect(message.count <= 600)
        }
    }

    private func writeTemporaryFile(named name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TuziAPIClientTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appending(path: name)
        try data.write(to: fileURL)
        return fileURL
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let store = RecordedRequestStore()

    static var lastRequestBody: Data? {
        store.requestBody
    }

    static var responseStatusCode: Int {
        get { store.responseStatusCode }
        set { store.responseStatusCode = newValue }
    }

    static var responseBody: Data {
        get { store.responseBody }
        set { store.responseBody = newValue }
    }

    static func reset() {
        store.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.tu-zi.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.store.record(requestBody(from: request))

        let data = Self.responseBody
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }
}

private final class RecordedRequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var body: Data?
    private var statusCode = 200
    private var bodyData = Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)

    var requestBody: Data? {
        lock.withLock { body }
    }

    var responseStatusCode: Int {
        get { lock.withLock { statusCode } }
        set { lock.withLock { statusCode = newValue } }
    }

    var responseBody: Data {
        get { lock.withLock { bodyData } }
        set { lock.withLock { bodyData = newValue } }
    }

    func reset() {
        lock.withLock {
            body = nil
            statusCode = 200
            bodyData = Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)
        }
    }

    func record(_ body: Data?) {
        lock.withLock {
            self.body = body
        }
    }
}
