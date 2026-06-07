import Foundation

public enum SessionSnapshotTrimmer {
    public static let defaultMaxMessages = 200
    public static let defaultMaxMessageTextCharacters = 32_000
    public static let defaultMaxTotalTextCharacters = 512 * 1_024
    private static let truncationMarker = "[truncated for local storage]"

    public static func trim(
        _ snapshot: SessionSnapshot,
        maxMessages: Int = defaultMaxMessages,
        maxMessageTextCharacters: Int = defaultMaxMessageTextCharacters,
        maxTotalTextCharacters: Int = defaultMaxTotalTextCharacters
    ) -> SessionSnapshot {
        let messageLimited = limitMessages(snapshot.messages, maxMessages: maxMessages)
        let textLimited = limitTextVolume(
            messageLimited,
            maxMessageTextCharacters: maxMessageTextCharacters,
            maxTotalTextCharacters: maxTotalTextCharacters
        )

        return SessionSnapshot(
            messages: textLimited,
            selectedModelID: snapshot.selectedModelID,
            lastConnectionStatus: snapshot.lastConnectionStatus
        )
    }

    private static func limitMessages(_ messages: [ChatMessage], maxMessages: Int) -> [ChatMessage] {
        guard maxMessages > 0, messages.count > maxMessages else {
            return messages
        }

        return Array(messages.suffix(maxMessages))
    }

    private static func limitTextVolume(
        _ messages: [ChatMessage],
        maxMessageTextCharacters: Int,
        maxTotalTextCharacters: Int
    ) -> [ChatMessage] {
        guard maxMessageTextCharacters > 0, maxTotalTextCharacters > 0 else {
            return messages.map { $0.replacing(text: "") }
        }

        var remaining = maxTotalTextCharacters
        var trimmedReversed: [ChatMessage] = []

        for message in messages.reversed() {
            let allowedCharacters = min(maxMessageTextCharacters, max(0, remaining))
            let trimmedText = textByLimiting(message.text, to: allowedCharacters)
            remaining -= trimmedText.count
            trimmedReversed.append(message.replacing(text: trimmedText))
        }

        return trimmedReversed.reversed()
    }

    private static func textByLimiting(_ text: String, to maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        guard maxCharacters > truncationMarker.count else {
            return String(truncationMarker.prefix(maxCharacters))
        }

        let prefixLength = maxCharacters - truncationMarker.count
        return String(text.prefix(prefixLength)) + truncationMarker
    }
}
