import Foundation
import Testing
@testable import ClaudeLiteCore

struct SessionSnapshotTrimmerTests {
    @Test
    func trimmerKeepsMostRecentMessagesWithinLimit() {
        let messages = (0..<20).map { index in
            ChatMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))")!,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "message-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let snapshot = SessionSnapshot(
            messages: messages,
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        let trimmed = SessionSnapshotTrimmer.trim(snapshot, maxMessages: 6)

        #expect(trimmed.messages.map(\.text) == [
            "message-14",
            "message-15",
            "message-16",
            "message-17",
            "message-18",
            "message-19"
        ])
        #expect(trimmed.selectedModelID == "claude-opus-4-7")
        #expect(trimmed.lastConnectionStatus == .connected)
    }

    @Test
    func trimmerLeavesSnapshotUntouchedWhenUnderLimit() {
        let snapshot = SessionSnapshot(
            messages: [
                .user(text: "hello"),
                .assistant(text: "ok")
            ],
            selectedModelID: nil,
            lastConnectionStatus: .checking
        )

        #expect(SessionSnapshotTrimmer.trim(snapshot, maxMessages: 10) == snapshot)
    }

    @Test
    func trimmerCapsPersistedTextVolume() {
        let messages = (0..<20).map { index in
            ChatMessage(
                id: UUID(uuidString: "10000000-0000-0000-0000-\(String(format: "%012d", index))")!,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: String(repeating: "\(index % 10)", count: 40_000),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let snapshot = SessionSnapshot(
            messages: messages,
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        let trimmed = SessionSnapshotTrimmer.trim(snapshot)

        #expect(trimmed.messages.count == 20)
        #expect(trimmed.messages.map(\ChatMessage.role) == messages.map(\ChatMessage.role))
        #expect(trimmed.messages.map(\ChatMessage.text.count).reduce(0, +) <= 512 * 1_024)
        #expect(trimmed.messages.allSatisfy { $0.text.count <= 32_000 })
        #expect(trimmed.messages.last?.text.hasPrefix(String(repeating: "9", count: 100)) == true)
        #expect(trimmed.messages.last?.text.hasSuffix("[truncated for local storage]") == true)
        #expect(trimmed.selectedModelID == "claude-opus-4-7")
        #expect(trimmed.lastConnectionStatus == ConnectionStatus.connected)
    }
}
