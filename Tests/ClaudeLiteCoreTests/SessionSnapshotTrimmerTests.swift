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
}
