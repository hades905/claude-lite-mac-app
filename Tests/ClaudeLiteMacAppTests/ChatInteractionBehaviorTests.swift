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
