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
    case streamingMarkdownPilot

    struct Decision: Equatable {
        let strategy: MessageTextRenderingStrategy
        let streamingMarkdownFallbackReason: StreamingMarkdownFallbackReason?
    }

    enum StreamingMarkdownFallbackReason: Equatable {
        case pilotDisabled
        case notAssistant
        case notPending
        case markdownImage
        case taskList
        case footnote
        case mermaid
        case rawHTML
    }

    static func strategy(
        for message: ChatMessage,
        streamingMarkdownPilotEnabled: Bool = false
    ) -> MessageTextRenderingStrategy {
        decision(
            for: message,
            streamingMarkdownPilotEnabled: streamingMarkdownPilotEnabled
        ).strategy
    }

    static func decision(
        for message: ChatMessage,
        streamingMarkdownPilotEnabled: Bool = false
    ) -> Decision {
        if message.role == .user {
            return Decision(strategy: .nativeText, streamingMarkdownFallbackReason: .notAssistant)
        }

        if message.status == .pending {
            if !streamingMarkdownPilotEnabled {
                return Decision(strategy: .nativeText, streamingMarkdownFallbackReason: .pilotDisabled)
            }

            if let fallbackReason = streamingMarkdownPilotFallbackReason(for: message.text) {
                return Decision(strategy: .nativeText, streamingMarkdownFallbackReason: fallbackReason)
            }

            return Decision(strategy: .streamingMarkdownPilot, streamingMarkdownFallbackReason: nil)
        }

        let strategy: MessageTextRenderingStrategy = requiresWebMarkdown(message.text) ? .webMarkdown : .nativeMarkdown
        return Decision(strategy: strategy, streamingMarkdownFallbackReason: .notPending)
    }

    private static func requiresWebMarkdown(_ text: String) -> Bool {
        MarkdownHTMLDocument.containsSupportedMath(in: text) || containsMarkdownTable(in: text)
    }

    private static func streamingMarkdownPilotFallbackReason(
        for text: String
    ) -> StreamingMarkdownFallbackReason? {
        if containsMarkdownImage(in: text) {
            return .markdownImage
        }

        if containsTaskListItem(in: text) {
            return .taskList
        }

        if text.contains("[^") {
            return .footnote
        }

        if containsMermaidFence(in: text) {
            return .mermaid
        }

        if containsRawHTML(in: text) {
            return .rawHTML
        }

        return nil
    }

    private static func containsMarkdownImage(in text: String) -> Bool {
        text.contains("![")
    }

    private static func containsTaskListItem(in text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- [ ]")
                || trimmed.hasPrefix("- [x]")
                || trimmed.hasPrefix("- [X]")
                || trimmed.hasPrefix("* [ ]")
                || trimmed.hasPrefix("* [x]")
                || trimmed.hasPrefix("* [X]")
        }
    }

    private static func containsMermaidFence(in text: String) -> Bool {
        text.range(of: #"```\s*mermaid\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsRawHTML(in text: String) -> Bool {
        text.range(of: #"<[A-Za-z][^>]*>"#, options: .regularExpression) != nil
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
