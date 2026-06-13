import AppKit
import ClaudeLiteCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @State private var viewModel: ChatViewModel
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false
    @State private var composerHeight = ChatInputHeight.default
    @State private var jumpButtonState = ChatJumpButtonState()
    @State private var latestAssistantFrame: CGRect?
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var previousLatestAssistantFrame: CGRect?
    @State private var jumpButtonIdleTask: Task<Void, Never>?
    @State private var previewedImageAttachment: ChatAttachment?

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            messageArea
            Divider()
            composer
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            do {
                try await viewModel.start()
            } catch {
                // ChatViewModel.start() keeps the startup failure visible and logs safe diagnostics.
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for fileURL in urls {
                    viewModel.addAttachment(from: fileURL)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for fileURL in urls {
                    viewModel.addAttachment(from: fileURL)
                }
            }
        }
        .sheet(item: $previewedImageAttachment) { attachment in
            ImageAttachmentPreviewSheet(attachment: attachment)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Lite")
                    .font(.system(size: 20, weight: .semibold))
                Text(statusSubtitle)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }

            Spacer()

            statusPill

            Picker("Model", selection: Binding(
                get: { viewModel.selectedModel?.id ?? "" },
                set: { viewModel.selectModel(id: $0) }
            )) {
                ForEach(viewModel.availableModelSections) { section in
                    Section(section.title) {
                        ForEach(section.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .disabled(viewModel.availableModels.isEmpty)

            Button("Check Again") {
                guard !isConnectionRefreshDisabled else {
                    return
                }

                Task {
                    guard !isConnectionRefreshDisabled else {
                        return
                    }

                    await viewModel.refreshConnection()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isConnectionRefreshDisabled)
        }
        .padding(20)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(viewModel.connectionStatus.label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var messageArea: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { scrollGeometry in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if viewModel.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Your conversation will stay here.")
                                        .font(.system(size: 22, weight: .semibold))
                                    Text("Start with a message, add a file or image, and keep the same thread across launches.")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 24)
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message) { attachment in
                                    previewedImageAttachment = attachment
                                }
                                    .id(message.id)
                                    .background {
                                        if MessageFrameTrackingPolicy.shouldTrack(
                                            messageID: message.id,
                                            trackedMessageID: latestAssistantID
                                        ) {
                                            GeometryReader { messageGeometry in
                                                Color.clear.preference(
                                                    key: MessageFramePreferenceKey.self,
                                                    value: MessageFrameTrackingPolicy.preferenceValue(
                                                        messageID: message.id,
                                                        trackedMessageID: latestAssistantID,
                                                        frame: messageGeometry.frame(in: .named(Self.chatScrollCoordinateSpace))
                                                    )
                                                )
                                            }
                                        } else {
                                            Color.clear
                                        }
                                    }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .coordinateSpace(name: Self.chatScrollCoordinateSpace)
                    .onAppear {
                        scrollViewportHeight = scrollGeometry.size.height
                        refreshJumpButtonState(targetID: latestAssistantID)
                    }
                    .onChange(of: scrollGeometry.size.height) { _, newHeight in
                        scrollViewportHeight = newHeight
                        refreshJumpButtonState(targetID: latestAssistantID)
                    }
                    .onChange(of: latestAssistantID) { _, newID in
                        previousLatestAssistantFrame = nil
                        refreshJumpButtonState(targetID: newID)
                    }
                    .onPreferenceChange(MessageFramePreferenceKey.self) { frames in
                        guard let latestAssistantID else {
                            latestAssistantFrame = nil
                            previousLatestAssistantFrame = nil
                            refreshJumpButtonState(targetID: nil)
                            return
                        }

                        let nextFrame = frames[latestAssistantID]
                        guard didLatestAssistantFrameChange(from: latestAssistantFrame, to: nextFrame) else {
                            return
                        }

                        latestAssistantFrame = nextFrame
                        let didMove = didLatestAssistantFrameMove(from: previousLatestAssistantFrame, to: nextFrame)
                        refreshJumpButtonState(targetID: latestAssistantID, treatAsScroll: didMove)
                        previousLatestAssistantFrame = latestAssistantFrame
                    }

                    if jumpButtonState.isVisible, let latestAssistantID {
                        Button {
                            jumpButtonIdleTask?.cancel()
                            withAnimation(.easeOut(duration: 0.18)) {
                                jumpButtonState.hideAfterJump()
                            }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy.scrollTo(latestAssistantID, anchor: .top)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 42, height: 42)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 22)
                        .padding(.bottom, 22)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }

            if !viewModel.draftAttachments.isEmpty {
                AttachmentPreviewStrip(
                    attachments: viewModel.draftAttachments,
                    context: .composer,
                    isTransmitting: false
                ) { attachmentID in
                    viewModel.removeDraftAttachment(id: attachmentID)
                } openImage: { attachment in
                    previewedImageAttachment = attachment
                }
            }

            ChatComposerInputView(
                text: $viewModel.draftText,
                height: $composerHeight,
                isSubmitEnabled: !isSendDisabled
            ) {
                sendDraft()
            }

            HStack {
                Button("Add File") {
                    showingFilePicker = true
                }
                .buttonStyle(.bordered)

                Button("Add Image") {
                    showingImagePicker = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    guard !isSendDisabled else {
                        return
                    }

                    sendDraft()
                } label: {
                    Text(viewModel.isSending ? "Sending..." : "Send")
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSendDisabled)
            }
        }
        .padding(20)
    }

    private var isConnectionRefreshDisabled: Bool {
        viewModel.connectionStatus == .checking || viewModel.isStarting
    }

    private var isSendDisabled: Bool {
        viewModel.isSending || !hasDraftContent
    }

    private var hasDraftContent: Bool {
        !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.draftAttachments.isEmpty
    }

    private var latestAssistantID: UUID? {
        ChatJumpTargetResolver.latestAssistantID(in: viewModel.messages)
    }

    private func sendDraft() {
        Task {
            guard !isSendDisabled else {
                return
            }

            try? await viewModel.send()
        }
    }

    private func refreshJumpButtonState(targetID: UUID?, treatAsScroll: Bool = false) {
        let latestAssistantIsNear = isLatestAssistantNear
        let wasVisible = jumpButtonState.isVisible

        withAnimation(.easeOut(duration: 0.18)) {
            jumpButtonState.update(targetID: targetID, latestAssistantIsNear: latestAssistantIsNear)
            if treatAsScroll {
                jumpButtonState.userScrolled()
            }
        }

        if jumpButtonState.isVisible {
            scheduleJumpButtonIdleHide()
        } else if wasVisible {
            jumpButtonIdleTask?.cancel()
        }
    }

    private var isLatestAssistantNear: Bool {
        guard latestAssistantID != nil, let latestAssistantFrame, scrollViewportHeight > 0 else {
            return true
        }

        let tolerance: CGFloat = 80
        return latestAssistantFrame.minY <= scrollViewportHeight + tolerance
            && latestAssistantFrame.maxY >= -tolerance
    }

    private func didLatestAssistantFrameMove(from oldFrame: CGRect?, to newFrame: CGRect?) -> Bool {
        guard let oldFrame, let newFrame else {
            return false
        }

        return abs(oldFrame.minY - newFrame.minY) > 2
    }

    private func didLatestAssistantFrameChange(from oldFrame: CGRect?, to newFrame: CGRect?) -> Bool {
        switch (oldFrame, newFrame) {
        case (nil, nil):
            false
        case (nil, _), (_, nil):
            true
        case let (oldFrame?, newFrame?):
            abs(oldFrame.minY - newFrame.minY) > 0.5
                || abs(oldFrame.maxY - newFrame.maxY) > 0.5
                || abs(oldFrame.width - newFrame.width) > 0.5
        }
    }

    private func scheduleJumpButtonIdleHide() {
        jumpButtonIdleTask?.cancel()
        jumpButtonIdleTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    jumpButtonState.hideForIdleTimeout()
                }
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .checking:
            .orange
        case .connected:
            .green
        case .disconnected:
            .red
        case .authFailed:
            .pink
        }
    }

    private var statusSubtitle: String {
        switch viewModel.connectionStatus {
        case .checking:
            "Checking the Tuzi gateway."
        case .connected:
            "Ready to talk with Claude."
        case .disconnected:
            "The app could not reach the server."
        case .authFailed:
            "A valid key is still needed."
        }
    }

    private static let chatScrollCoordinateSpace = "ClaudeLiteChatScroll"
}

private struct MessageFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let openImage: (ChatAttachment) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.role == .user ? "You" : "Claude")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if !message.attachments.isEmpty {
                    AttachmentPreviewStrip(
                        attachments: message.attachments,
                        context: .message,
                        isTransmitting: message.role == .user && message.status == .pending,
                        openImage: openImage
                    )
                }

                if !message.text.isEmpty {
                    switch MessageTextRenderingStrategy.strategy(for: message) {
                    case .nativeText:
                        Text(message.text)
                            .foregroundStyle(message.status == .pending ? .secondary : .primary)
                            .italic(message.status == .pending)
                            .textSelection(.enabled)
                    case .nativeMarkdown:
                        NativeMarkdownText(markdown: message.text)
                            .textSelection(.enabled)
                    case .webMarkdown:
                        MarkdownMessageView(markdown: message.text)
                            .frame(maxWidth: 580, alignment: .leading)
                    case .streamingMarkdownPilot:
                        MarkdownMessageView(markdown: message.text)
                            .frame(maxWidth: 580, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 580, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct NativeMarkdownText: View {
    let markdown: String

    var body: Text {
        guard let attributed = try? AttributedString(markdown: markdown) else {
            return Text(markdown)
        }

        return Text(attributed)
    }
}

private struct AttachmentPreviewStrip: View {
    enum Context {
        case composer
        case message
    }

    let attachments: [ChatAttachment]
    let context: Context
    let isTransmitting: Bool
    var remove: ((UUID) -> Void)?
    var openImage: ((ChatAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(attachments) { attachment in
                    switch attachment.kind {
                    case .image where attachment.localURL != nil:
                        ImageAttachmentPreview(
                            attachment: attachment,
                            size: imageSize,
                            isTransmitting: isTransmitting,
                            remove: context == .composer ? { remove?(attachment.id) } : nil,
                            open: { openImage?(attachment) }
                        )
                    case .image, .file:
                        AttachmentChip(
                            attachment: attachment,
                            remove: context == .composer ? { remove?(attachment.id) } : nil
                        )
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: context == .message ? 540 : .infinity, alignment: .leading)
    }

    private var imageSize: CGSize {
        switch context {
        case .composer:
            CGSize(width: 96, height: 72)
        case .message:
            CGSize(width: 168, height: 126)
        }
    }
}

private struct ImageAttachmentPreview: View {
    let attachment: ChatAttachment
    let size: CGSize
    let isTransmitting: Bool
    var remove: (() -> Void)?
    var open: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
                .frame(width: size.width, height: size.height)
                .clipped()

            if isTransmitting {
                AttachmentTransferOverlay()
            }

            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.58))
                }
                .buttonStyle(.plain)
                .padding(5)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            open?()
        }
        .accessibilityLabel(attachment.name)
        .accessibilityAddTraits(open == nil ? [] : .isButton)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = AttachmentImageLoader.thumbnail(for: attachment) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .medium))
                Text(attachment.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AttachmentTransferOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.36)

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
        }
        .accessibilityLabel("Sending image")
    }
}

private struct AttachmentChip: View {
    let attachment: ChatAttachment
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind == .image ? "photo" : "paperclip")
            Text(attachment.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.12))
        .clipShape(Capsule())
        .frame(maxWidth: 220, alignment: .leading)
    }
}

private struct ImageAttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let attachment: ChatAttachment
    @State private var image: NSImage?
    @State private var didFailToLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(attachment.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            ZStack {
                Color.black.opacity(0.04)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                } else if didFailToLoad {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "photo",
                        description: Text(attachment.name)
                    )
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .frame(minWidth: 720, minHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 590)
        .onAppear {
            image = AttachmentImageLoader.previewImage(for: attachment)
            didFailToLoad = image == nil
        }
        .onDisappear {
            image = nil
        }
    }
}
