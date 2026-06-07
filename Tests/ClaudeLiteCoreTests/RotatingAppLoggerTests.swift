import Foundation
import Testing
@testable import ClaudeLiteCore

struct RotatingAppLoggerTests {
    @Test
    func loggerRedactsSensitiveValuesAndMessageText() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let logger = RotatingAppLogger(
            directoryURL: directory,
            fileName: "app.log",
            maxFileBytes: 4_096,
            maxTotalBytes: 8_192
        )

        try logger.record(
            event: "send_failed",
            metadata: [
                "apiKey": "secret-model-key",
                "prompt": "this is a private question",
                "messageCount": "3"
            ]
        )

        let log = try String(contentsOf: directory.appending(path: "app.log"), encoding: .utf8)

        #expect(log.contains("send_failed"))
        #expect(log.contains("messageCount=3"))
        #expect(log.contains("apiKey=<redacted>"))
        #expect(log.contains("prompt=<redacted>"))
        #expect(!log.contains("secret-model-key"))
        #expect(!log.contains("this is a private question"))
    }

    @Test
    func loggerRedactsSensitiveTokensInsideSafeMetadataValues() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let logger = RotatingAppLogger(
            directoryURL: directory,
            fileName: "app.log",
            maxFileBytes: 4_096,
            maxTotalBytes: 8_192
        )
        let bearerToken = "Bearer " + "abc.def_123-456"
        let apiKey = "sk-" + "test_1234567890abcd"

        try logger.record(
            event: "network_failed",
            metadata: [
                "error": "request failed with \(bearerToken) and \(apiKey)"
            ]
        )

        let log = try String(contentsOf: directory.appending(path: "app.log"), encoding: .utf8)

        #expect(log.contains("network_failed"))
        #expect(log.contains("error=request failed with <redacted> and <redacted>"))
        #expect(!log.contains(bearerToken))
        #expect(!log.contains(apiKey))
    }

    @Test
    func loggerRedactsLocalPathsInsideSafeMetadataValues() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let logger = RotatingAppLogger(
            directoryURL: directory,
            fileName: "app.log",
            maxFileBytes: 4_096,
            maxTotalBytes: 8_192
        )

        try logger.record(
            event: "file_failed",
            metadata: [
                "error": "failed to read /Users/hadesz/Documents/private-plan.txt and file:///Users/hadesz/Pictures/private-photo.png"
            ]
        )

        let log = try String(contentsOf: directory.appending(path: "app.log"), encoding: .utf8)

        #expect(log.contains("file_failed"))
        #expect(log.contains("error=failed to read <local-path> and <local-path>"))
        #expect(!log.contains("/Users/hadesz"))
        #expect(!log.contains("private-plan.txt"))
        #expect(!log.contains("private-photo.png"))
    }

    @Test
    func loggerKeepsTotalSizeUnderLimit() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let logger = RotatingAppLogger(
            directoryURL: directory,
            fileName: "app.log",
            maxFileBytes: 256,
            maxTotalBytes: 768
        )

        for index in 0..<80 {
            try logger.record(
                event: "heartbeat",
                metadata: [
                    "index": "\(index)",
                    "payload": String(repeating: "x", count: 80)
                ]
            )
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let totalBytes = try files.reduce(0) { partial, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return partial + (values.fileSize ?? 0)
        }

        #expect(totalBytes <= 768)
        #expect(files.contains { $0.lastPathComponent == "app.log" })
    }
}
