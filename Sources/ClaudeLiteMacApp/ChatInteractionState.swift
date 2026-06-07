import AppKit
import ClaudeLiteCore

enum ChatJumpTargetResolver {
    static func latestAssistantID(in messages: [ChatMessage]) -> UUID? {
        messages.reversed().first { message in
            message.role == .assistant
        }?.id
    }
}

enum MessageTextRenderingStrategy: Equatable {
    case nativeText
    case nativeMarkdown
    case webMarkdown

    static func strategy(for message: ChatMessage) -> MessageTextRenderingStrategy {
        if message.role == .user || message.status == .pending {
            return .nativeText
        }

        return requiresWebMarkdown(message.text) ? .webMarkdown : .nativeMarkdown
    }

    private static func requiresWebMarkdown(_ text: String) -> Bool {
        MarkdownHTMLDocument.containsSupportedMath(in: text) || containsMarkdownTable(in: text)
    }

    private static func containsMarkdownTable(in text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else {
            return false
        }

        for index in 0..<(lines.count - 1) {
            if lines[index].contains("|"), isTableSeparatorLine(lines[index + 1]) {
                return true
            }
        }

        return false
    }

    private static func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        let columns = trimmed.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard !columns.isEmpty else {
            return false
        }

        return columns.allSatisfy { column in
            column.contains("-") && column.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }
}

enum MessageFrameTrackingPolicy {
    static func shouldTrack(messageID: UUID, trackedMessageID: UUID?) -> Bool {
        messageID == trackedMessageID
    }

    static func preferenceValue(
        messageID: UUID,
        trackedMessageID: UUID?,
        frame: CGRect
    ) -> [UUID: CGRect] {
        guard shouldTrack(messageID: messageID, trackedMessageID: trackedMessageID) else {
            return [:]
        }

        return [messageID: frame]
    }
}

struct ChatJumpButtonState {
    private(set) var isVisible = false

    private var targetID: UUID?
    private var latestAssistantIsNear = true
    private var userHasScrolledAway = false
    private var suppressedAfterJumpTargetID: UUID?
    private var isHiddenForIdleTimeout = false

    mutating func update(targetID newTargetID: UUID?, latestAssistantIsNear isNear: Bool) {
        let targetChanged = targetID != newTargetID

        targetID = newTargetID
        latestAssistantIsNear = isNear

        if targetChanged {
            suppressedAfterJumpTargetID = nil
            isHiddenForIdleTimeout = false
            userHasScrolledAway = !isNear
        }

        if isNear {
            suppressedAfterJumpTargetID = nil
            isHiddenForIdleTimeout = false
            userHasScrolledAway = false
        }

        refreshVisibility()
    }

    mutating func userScrolled() {
        if !latestAssistantIsNear {
            userHasScrolledAway = true
            isHiddenForIdleTimeout = false
        }

        refreshVisibility()
    }

    mutating func hideAfterJump() {
        suppressedAfterJumpTargetID = targetID
        isHiddenForIdleTimeout = false
        isVisible = false
    }

    mutating func hideForIdleTimeout() {
        isHiddenForIdleTimeout = true
        isVisible = false
    }

    private mutating func refreshVisibility() {
        guard let targetID, !latestAssistantIsNear else {
            isVisible = false
            return
        }

        guard suppressedAfterJumpTargetID != targetID else {
            isVisible = false
            return
        }

        guard !isHiddenForIdleTimeout else {
            isVisible = false
            return
        }

        isVisible = userHasScrolledAway
    }
}

enum ChatInputKeyCommand {
    enum Action: Equatable {
        case submit
        case insertNewline
        case defaultHandling
    }

    static func action(
        forReturnKeyWithModifiers modifiers: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> Action {
        guard !hasMarkedText else {
            return .defaultHandling
        }

        let commandModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        if commandModifiers.contains(.command) {
            return .insertNewline
        }

        if commandModifiers.isEmpty {
            return .submit
        }

        return .defaultHandling
    }
}

enum ChatInputHeight {
    static let minimum: CGFloat = 72
    static let `default`: CGFloat = 120
    static let maximum: CGFloat = 260

    static func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, minimum), maximum)
    }
}
