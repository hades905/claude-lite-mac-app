import AppKit
import Foundation
import Testing
@testable import ClaudeLiteMacApp
@testable import ClaudeLiteCore

struct ChatInteractionBehaviorTests {
    @Test
    func latestAssistantTargetSelectsMostRecentAssistantIncludingPendingReply() {
        let firstAssistantID = UUID()
        let latestAssistantID = UUID()
        let messages: [ChatMessage] = [
            .assistant(id: firstAssistantID, text: "Earlier answer"),
            .user(text: "Follow up"),
            .assistant(
                id: latestAssistantID,
                text: "正在回复...",
                status: .pending
            ),
            .user(text: "Typed but not sent")
        ]

        #expect(ChatJumpTargetResolver.latestAssistantID(in: messages) == latestAssistantID)
    }

    @Test
    func lightweightMessagesAvoidWebMarkdownRendering() {
        #expect(MessageTextRenderingStrategy.strategy(for: .user(text: "Hello")) == .nativeText)
        #expect(MessageTextRenderingStrategy.strategy(for: .assistant(text: "正在回复...", status: .pending)) == .nativeText)
        #expect(MessageTextRenderingStrategy.strategy(for: .assistant(text: "# Answer")) == .nativeMarkdown)
        #expect(MessageTextRenderingStrategy.strategy(for: .assistant(text: "$$x^2$$")) == .webMarkdown)
        #expect(MessageTextRenderingStrategy.strategy(for: .assistant(text: "| A | B |\n| - | - |\n| 1 | 2 |")) == .webMarkdown)
        #expect(MessageTextRenderingStrategy.strategy(for: .assistant(text: "This costs $5 or $6 today")) == .nativeMarkdown)
    }

    @Test
    func frameTrackingOnlyReportsLatestAssistantMessage() {
        let userID = UUID()
        let earlierAssistantID = UUID()
        let latestAssistantID = UUID()
        let frame = CGRect(x: 0, y: 10, width: 200, height: 80)

        #expect(
            MessageFrameTrackingPolicy.preferenceValue(
                messageID: userID,
                trackedMessageID: latestAssistantID,
                frame: frame
            ).isEmpty
        )
        #expect(
            MessageFrameTrackingPolicy.preferenceValue(
                messageID: earlierAssistantID,
                trackedMessageID: latestAssistantID,
                frame: frame
            ).isEmpty
        )
        #expect(
            MessageFrameTrackingPolicy.preferenceValue(
                messageID: latestAssistantID,
                trackedMessageID: latestAssistantID,
                frame: frame
            ) == [latestAssistantID: frame]
        )
    }

    @Test
    func jumpButtonStaysHiddenWhenLatestAssistantIsNear() {
        let assistantID = UUID()
        var state = ChatJumpButtonState()

        state.update(targetID: assistantID, latestAssistantIsNear: true)
        state.userScrolled()

        #expect(state.isVisible == false)
    }

    @Test
    func jumpButtonAppearsWhenUserLeavesLatestAssistantArea() {
        let assistantID = UUID()
        var state = ChatJumpButtonState()

        state.update(targetID: assistantID, latestAssistantIsNear: true)
        state.update(targetID: assistantID, latestAssistantIsNear: false)
        state.userScrolled()

        #expect(state.isVisible == true)
    }

    @Test
    func jumpButtonHidesAfterClickUntilLatestAssistantIsReached() {
        let assistantID = UUID()
        var state = ChatJumpButtonState()

        state.update(targetID: assistantID, latestAssistantIsNear: false)
        state.userScrolled()
        state.hideAfterJump()

        #expect(state.isVisible == false)

        state.update(targetID: assistantID, latestAssistantIsNear: false)
        state.userScrolled()

        #expect(state.isVisible == false)

        state.update(targetID: assistantID, latestAssistantIsNear: true)

        #expect(state.isVisible == false)
    }

    @Test
    func jumpButtonCanReappearAfterIdleTimeoutWhenUserScrollsAgainOrNewAssistantArrives() {
        let assistantID = UUID()
        let nextAssistantID = UUID()
        var state = ChatJumpButtonState()

        state.update(targetID: assistantID, latestAssistantIsNear: false)
        state.userScrolled()
        state.hideForIdleTimeout()

        #expect(state.isVisible == false)

        state.userScrolled()

        #expect(state.isVisible == true)

        state.hideForIdleTimeout()
        state.update(targetID: nextAssistantID, latestAssistantIsNear: false)

        #expect(state.isVisible == true)
    }

    @Test
    func returnKeySubmitsButCommandReturnInsertsNewline() {
        #expect(
            ChatInputKeyCommand.action(
                forReturnKeyWithModifiers: [],
                hasMarkedText: false
            ) == .submit
        )
        #expect(
            ChatInputKeyCommand.action(
                forReturnKeyWithModifiers: .command,
                hasMarkedText: false
            ) == .insertNewline
        )
    }

    @Test
    func returnKeyDoesNotSubmitWhileInputMethodHasMarkedText() {
        #expect(
            ChatInputKeyCommand.action(
                forReturnKeyWithModifiers: [],
                hasMarkedText: true
            ) == .defaultHandling
        )
    }

    @Test
    func inputHeightIsClampedToAllowedRange() {
        #expect(ChatInputHeight.minimum == 72)
        #expect(ChatInputHeight.default == 120)
        #expect(ChatInputHeight.maximum == 260)
        #expect(ChatInputHeight.clamped(40) == ChatInputHeight.minimum)
        #expect(ChatInputHeight.clamped(120) == ChatInputHeight.default)
        #expect(ChatInputHeight.clamped(400) == ChatInputHeight.maximum)
    }
}
