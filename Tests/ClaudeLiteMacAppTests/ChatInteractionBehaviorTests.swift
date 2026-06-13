import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClaudeLiteMacApp
@testable import ClaudeLiteCore

struct ChatInteractionBehaviorTests {
    @Test
    func startupTaskDoesNotRefreshConnectionAfterStartFailure() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appending(path: "Sources/ClaudeLiteMacApp/MainWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let taskStart = try #require(source.range(of: ".task {"))
        let importerStart = try #require(source.range(of: ".fileImporter("))
        let startupTask = String(source[taskStart.lowerBound..<importerStart.lowerBound])

        #expect(startupTask.contains("try await viewModel.start()"))
        #expect(!startupTask.contains("await viewModel.refreshConnection()"))
    }

    @Test
    func fileImportersAllowMultipleAttachments() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appending(path: "Sources/ClaudeLiteMacApp/MainWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.components(separatedBy: "allowsMultipleSelection: true").count >= 3)
        #expect(!source.contains("allowsMultipleSelection: false"))
        #expect(source.contains("for fileURL in urls"))
        #expect(!source.contains("let fileURL = urls.first"))
    }

    @Test
    func mainWindowRecordsMessageRenderingDiagnosticsWhenMessagesAppear() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appending(path: "Sources/ClaudeLiteMacApp/MainWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("@State private var renderingDiagnosticLogger = MessageRenderingDiagnosticLogger()"))
        #expect(source.contains("private let appLogger: AppLogging"))
        #expect(source.contains("onRenderDecision: { message in"))
        #expect(source.contains("renderingDiagnosticLogger.recordIfNeeded("))
        #expect(source.contains("logger: appLogger"))
        #expect(source.contains(".onAppear {"))
        #expect(source.contains("onRenderDecision(message)"))
        let renderingStrategyStart = try #require(source.range(of: "switch MessageTextRenderingStrategy.strategy("))
        let nativeTextStart = try #require(source.range(of: "case .nativeText:"))
        let renderingStrategySource = String(source[renderingStrategyStart.lowerBound..<nativeTextStart.lowerBound])
        #expect(renderingStrategySource.contains("for: message"))
        #expect(renderingStrategySource.contains("streamingMarkdownPilotEnabled: streamingMarkdownPilotEnabled"))
    }

    @Test
    func appEntryPassesLiveLoggerToMainWindow() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appending(path: "Sources/ClaudeLiteMacApp/ClaudeLiteMacApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("private let services = LiveServiceContainer.live()"))
        #expect(source.contains("ChatViewModel(services: services)"))
        #expect(source.contains("appLogger: services.logger"))
    }

    @Test
    func restoredImageAttachmentsWithoutLocalFileRenderAsChips() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appending(path: "Sources/ClaudeLiteMacApp/MainWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case .image where attachment.localURL != nil"))
        #expect(source.contains("case .image, .file:"))
    }

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
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: String(repeating: "Long plain answer. ", count: 2_000))
            ) == .nativeMarkdown
        )
    }

    @Test
    func streamingMarkdownPilotOnlySelectsSafePendingAssistantMessagesWhenEnabled() {
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "Streaming **answer**", status: .pending),
                streamingMarkdownPilotEnabled: false
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .user(text: "Streaming **answer**"),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "Streaming **answer**", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .streamingMarkdownPilot
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "![remote](https://example.com/image.png)", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "- [ ] task", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "Footnote[^1]\n\n[^1]: private note", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "```mermaid\ngraph TD\nA-->B\n```", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "<script>alert(1)</script>", status: .pending),
                streamingMarkdownPilotEnabled: true
            ) == .nativeText
        )
        #expect(
            MessageTextRenderingStrategy.strategy(
                for: .assistant(text: "Finished **answer**", status: .sent),
                streamingMarkdownPilotEnabled: true
            ) == .nativeMarkdown
        )
    }

    @Test
    func streamingMarkdownPilotDecisionReportsFallbackReasons() {
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "Streaming **answer**", status: .pending),
                streamingMarkdownPilotEnabled: false
            ).streamingMarkdownFallbackReason == .pilotDisabled
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .user(text: "Streaming **answer**"),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .notAssistant
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "Finished **answer**", status: .sent),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .notPending
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "![remote](https://example.com/image.png)", status: .pending),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .markdownImage
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "- [x] task", status: .pending),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .taskList
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "Footnote[^1]\n\n[^1]: private note", status: .pending),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .footnote
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "```mermaid\ngraph TD\nA-->B\n```", status: .pending),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .mermaid
        )
        #expect(
            MessageTextRenderingStrategy.decision(
                for: .assistant(text: "<script>alert(1)</script>", status: .pending),
                streamingMarkdownPilotEnabled: true
            ).streamingMarkdownFallbackReason == .rawHTML
        )

        let selectedDecision = MessageTextRenderingStrategy.decision(
            for: .assistant(text: "Streaming **answer**", status: .pending),
            streamingMarkdownPilotEnabled: true
        )

        #expect(selectedDecision.strategy == .streamingMarkdownPilot)
        #expect(selectedDecision.streamingMarkdownFallbackReason == nil)
    }

    @Test
    func streamingMarkdownRenderDiagnosticsAvoidMessageContent() {
        let message = ChatMessage.assistant(
            text: "private assistant reply with **markdown**",
            status: .pending
        )
        let decision = MessageTextRenderingStrategy.decision(
            for: message,
            streamingMarkdownPilotEnabled: false
        )

        let metadata = MessageRenderingDiagnostics.metadata(
            for: message,
            decision: decision
        )

        #expect(MessageRenderingDiagnostics.event == "message_render_decided")
        #expect(metadata["role"] == "assistant")
        #expect(metadata["status"] == "pending")
        #expect(metadata["strategy"] == "nativeText")
        #expect(metadata["streamingMarkdownFallbackReason"] == "pilotDisabled")
        #expect(metadata["attachmentCount"] == "0")
        #expect(metadata["textCharacterCount"] == "\(message.text.count)")
        #expect(!metadata.keys.contains("text"))
        #expect(!metadata.values.contains { $0.contains("private assistant reply") })
    }

    @Test
    func messageRenderingDiagnosticLoggerRecordsEachMessageOnlyOnceWithoutContent() throws {
        let logger = RecordingAppLogger()
        var diagnosticLogger = MessageRenderingDiagnosticLogger()
        let message = ChatMessage.assistant(
            text: "private assistant reply with **markdown**",
            status: .pending
        )

        diagnosticLogger.recordIfNeeded(
            message: message,
            streamingMarkdownPilotEnabled: false,
            logger: logger
        )
        diagnosticLogger.recordIfNeeded(
            message: message,
            streamingMarkdownPilotEnabled: false,
            logger: logger
        )

        let entry = try #require(logger.entries.first)
        #expect(logger.entries.count == 1)
        #expect(entry.event == MessageRenderingDiagnostics.event)
        #expect(entry.metadata["strategy"] == "nativeText")
        #expect(entry.metadata["streamingMarkdownFallbackReason"] == "pilotDisabled")
        #expect(!entry.metadata.values.contains { $0.contains("private assistant reply") })
    }

    @Test
    func messageRenderingDiagnosticLoggerRecordsWhenRenderedStateChanges() {
        let logger = RecordingAppLogger()
        var diagnosticLogger = MessageRenderingDiagnosticLogger()
        let messageID = UUID()
        let pendingMessage = ChatMessage.assistant(
            id: messageID,
            text: "正在回复...",
            status: .pending
        )
        let sentMessage = ChatMessage.assistant(
            id: messageID,
            text: "final **markdown** answer",
            status: .sent
        )

        diagnosticLogger.recordIfNeeded(
            message: pendingMessage,
            streamingMarkdownPilotEnabled: false,
            logger: logger
        )
        diagnosticLogger.recordIfNeeded(
            message: sentMessage,
            streamingMarkdownPilotEnabled: false,
            logger: logger
        )
        diagnosticLogger.recordIfNeeded(
            message: sentMessage,
            streamingMarkdownPilotEnabled: false,
            logger: logger
        )

        #expect(logger.entries.count == 2)
        #expect(logger.entries.map { $0.metadata["status"] } == ["pending", "sent"])
        #expect(logger.entries.map { $0.metadata["strategy"] } == ["nativeText", "nativeMarkdown"])
        #expect(!logger.entries.contains { entry in
            entry.metadata.values.contains { $0.contains("final **markdown** answer") }
        })
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

    @Test
    func attachmentImageLoaderDownsamplesThumbnailImage() throws {
        let imageURL = try writePNG(width: 960, height: 640)
        let attachment = ChatAttachment(name: "large.png", kind: .image, localURL: imageURL)

        let thumbnail = try #require(AttachmentImageLoader.thumbnail(for: attachment, maxPixelSize: 120))

        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 120)
        #expect(min(thumbnail.size.width, thumbnail.size.height) > 0)
    }

    private func writePNG(width: Int, height: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChatInteractionBehaviorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "fixture.png")

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 240
            pixels[index + 1] = 80
            pixels[index + 2] = 40
            pixels[index + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))

        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return fileURL
    }
}

private final class RecordingAppLogger: AppLogging, @unchecked Sendable {
    private(set) var entries: [(event: String, metadata: [String: String])] = []

    func record(event: String, metadata: [String: String]) throws {
        entries.append((event: event, metadata: metadata))
    }
}
