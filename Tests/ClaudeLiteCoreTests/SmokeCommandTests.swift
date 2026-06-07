import Foundation
import Testing

struct SmokeCommandTests {
    @Test
    func smokeCommandDefaultsToOfflineDiagnosticsWithoutLiveChat() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/ClaudeLiteSmoke/main.swift"),
            encoding: .utf8
        )

        #expect(source.contains("runOfflineDiagnostics"))
        #expect(source.contains("--live"))
        #expect(source.contains("LiveChatService"))
        #expect(source.contains("OfflineChatService"))
        #expect(source.contains("""
        if CommandLine.arguments.contains("--live") {
                        try await runLiveSmoke()
                    } else {
                        try await runOfflineDiagnostics()
                    }
        """))
    }
}
