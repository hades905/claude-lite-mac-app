import Foundation

public enum SessionSnapshotTrimmer {
    public static let defaultMaxMessages = 200

    public static func trim(
        _ snapshot: SessionSnapshot,
        maxMessages: Int = defaultMaxMessages
    ) -> SessionSnapshot {
        guard maxMessages > 0, snapshot.messages.count > maxMessages else {
            return snapshot
        }

        return SessionSnapshot(
            messages: Array(snapshot.messages.suffix(maxMessages)),
            selectedModelID: snapshot.selectedModelID,
            lastConnectionStatus: snapshot.lastConnectionStatus
        )
    }
}
