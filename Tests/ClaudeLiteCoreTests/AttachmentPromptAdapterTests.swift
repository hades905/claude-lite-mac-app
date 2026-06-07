import Foundation
import Testing
@testable import ClaudeLiteCore

struct AttachmentPromptAdapterTests {
    @Test
    func smallTextAttachmentIncludesFileContent() throws {
        let fileURL = try writeTemporaryFile(
            named: "notes.txt",
            contents: "keep this context"
        )
        let message = ChatMessage.user(
            text: "What matters here?",
            attachments: [
                ChatAttachment(name: "notes.txt", kind: .file, localURL: fileURL)
            ]
        )

        let rendered = AttachmentPromptAdapter.renderMessageText(for: message)

        #expect(rendered.contains("[File attached: notes.txt]"))
        #expect(rendered.contains("<file>\nkeep this context\n</file>"))
        #expect(rendered.hasSuffix("What matters here?"))
    }

    @Test
    func largeTextAttachmentUsesSummaryWithoutInlineContent() throws {
        let fileURL = try writeTemporaryFile(
            named: "large.txt",
            contents: String(repeating: "x", count: 32_001)
        )
        let message = ChatMessage.user(
            text: "",
            attachments: [
                ChatAttachment(name: "large.txt", kind: .file, localURL: fileURL)
            ]
        )

        let rendered = AttachmentPromptAdapter.renderMessageText(for: message)

        #expect(rendered == "[File attached: large.txt]")
    }

    @Test
    func textAttachmentWithoutSizeMetadataIsSummarizedWithoutReadingData() {
        SizeMetadataUnavailableURLProtocol.reset()
        URLProtocol.registerClass(SizeMetadataUnavailableURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(SizeMetadataUnavailableURLProtocol.self)
        }

        let message = ChatMessage.user(
            text: "",
            attachments: [
                ChatAttachment(
                    name: "remote.txt",
                    kind: .file,
                    localURL: URL(string: "attachment-test://fixture/remote.txt")!
                )
            ]
        )

        let rendered = AttachmentPromptAdapter.renderMessageText(for: message)

        #expect(rendered == "[File attached: remote.txt]")
        #expect(SizeMetadataUnavailableURLProtocol.requestCount == 0)
    }

    private func writeTemporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AttachmentPromptAdapterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appending(path: name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

private final class SizeMetadataUnavailableURLProtocol: URLProtocol, @unchecked Sendable {
    private static let counter = RequestCounter()

    static var requestCount: Int {
        counter.value
    }

    static func reset() {
        counter.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "attachment-test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.counter.increment()

        let data = Data("this should not be read".utf8)
        let response = URLResponse(
            url: request.url!,
            mimeType: "text/plain",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func reset() {
        lock.withLock {
            count = 0
        }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
