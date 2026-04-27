import AppKit
import SwiftUI

struct ChatComposerInputView: View {
    @Binding private var text: String
    @Binding private var height: CGFloat

    private let isSubmitEnabled: Bool
    private let onSubmit: () -> Void

    @State private var dragStartHeight: CGFloat?

    init(
        text: Binding<String>,
        height: Binding<CGFloat>,
        isSubmitEnabled: Bool,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._height = height
        self.isSubmitEnabled = isSubmitEnabled
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 6) {
            dragHandle

            ChatComposerTextInput(
                text: $text,
                isSubmitEnabled: isSubmitEnabled,
                onSubmit: onSubmit
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(height: clampedHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .onAppear(perform: clampHeight)
        .onChange(of: height) { _, _ in
            clampHeight()
        }
    }

    private var clampedHeight: CGFloat {
        ChatInputHeight.clamped(height)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.7))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .accessibilityLabel("Resize composer input")
            .accessibilityHint("Drag up or down to change the input height.")
            .help("Drag to resize")
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startingHeight = dragStartHeight ?? height

                if dragStartHeight == nil {
                    dragStartHeight = height
                }

                height = ChatInputHeight.clamped(startingHeight - value.translation.height)
            }
            .onEnded { _ in
                dragStartHeight = nil
                clampHeight()
            }
    }

    private func clampHeight() {
        let nextHeight = ChatInputHeight.clamped(height)

        if nextHeight != height {
            height = nextHeight
        }
    }
}

private struct ChatComposerTextInput: NSViewRepresentable {
    @Binding var text: String

    let isSubmitEnabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = KeyHandlingTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView: KeyHandlingTextView
        if let providedTextView = scrollView.documentView as? KeyHandlingTextView {
            textView = providedTextView
        } else {
            let replacementTextView = KeyHandlingTextView(frame: scrollView.contentView.bounds)
            scrollView.documentView = replacementTextView
            textView = replacementTextView
        }

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.importsGraphics = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.string = text
        textView.textColor = .labelColor
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.onSubmit = onSubmit
        textView.isSubmitEnabled = isSubmitEnabled
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text

        guard let textView = scrollView.documentView as? KeyHandlingTextView else {
            return
        }

        textView.onSubmit = onSubmit
        textView.isSubmitEnabled = isSubmitEnabled

        guard textView.string != text, !textView.hasMarkedText() else {
            return
        }

        let selectedRanges = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selectedRanges.clamped(toUTF16Length: (text as NSString).length)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}

private final class KeyHandlingTextView: NSTextView {
    var isSubmitEnabled = true
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.isReturnKey else {
            super.keyDown(with: event)
            return
        }

        switch ChatInputKeyCommand.action(
            forReturnKeyWithModifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: hasMarkedText()
        ) {
        case .submit:
            if isSubmitEnabled {
                onSubmit?()
            }
        case .insertNewline:
            insertNewline(nil)
        case .defaultHandling:
            super.keyDown(with: event)
        }
    }
}

private extension Array where Element == NSValue {
    func clamped(toUTF16Length length: Int) -> [NSValue] {
        map { value in
            let range = value.rangeValue
            let location = Swift.min(range.location, length)
            let rangeLength = Swift.min(range.length, length - location)
            return NSValue(range: NSRange(location: location, length: rangeLength))
        }
    }
}

private extension NSEvent {
    var isReturnKey: Bool {
        keyCode == 36
            || keyCode == 76
            || characters == "\r"
            || charactersIgnoringModifiers == "\r"
    }
}
