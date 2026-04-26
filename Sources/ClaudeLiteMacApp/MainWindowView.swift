import ClaudeLiteCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @State private var viewModel: ChatViewModel
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false

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
                await viewModel.refreshConnection()
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let fileURL = urls.first {
                viewModel.addAttachment(from: fileURL)
            }
        }
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let fileURL = urls.first {
                viewModel.addAttachment(from: fileURL)
            }
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
                ForEach(viewModel.availableModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .disabled(viewModel.availableModels.isEmpty)

            Button("Check Again") {
                Task {
                    await viewModel.refreshConnection()
                }
            }
            .buttonStyle(.bordered)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    MessageBubble(message: message)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.draftAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                viewModel.removeDraftAttachment(id: attachment.id)
                            }
                        }
                    }
                }
            }

            TextEditor(text: $viewModel.draftText)
                .font(.system(size: 14))
                .frame(minHeight: 100, maxHeight: 150)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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

                Button(viewModel.isSending ? "Sending..." : "Send") {
                    Task {
                        try? await viewModel.send()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending)
            }
        }
        .padding(20)
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
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.role == .user ? "You" : "Claude")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: attachment.kind == .image ? "photo" : "doc")
                            Text(attachment.name)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }

                if !message.text.isEmpty {
                    if message.status == .pending {
                        Text(message.text)
                            .foregroundStyle(.secondary)
                            .italic()
                            .textSelection(.enabled)
                    } else {
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

private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind == .image ? "photo" : "paperclip")
            Text(attachment.name)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.12))
        .clipShape(Capsule())
    }
}
