import AppKit
import ClaudeLiteCore
import SwiftUI
import WebKit

struct MarkdownMessageView: View {
    let markdown: String
    @State private var contentHeight: CGFloat = 24

    var body: some View {
        MarkdownWebView(markdown: markdown, contentHeight: $contentHeight)
            .frame(height: max(contentHeight, 24))
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> AutoSizingWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Coordinator.heightMessageName)
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .nonPersistent()

        let webView = AutoSizingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.onResize = {
            context.coordinator.requestHeightUpdate()
        }

        context.coordinator.attach(webView)
        context.coordinator.load(markdown: markdown)
        return webView
    }

    func updateNSView(_ nsView: AutoSizingWebView, context: Context) {
        context.coordinator.attach(nsView)
        context.coordinator.load(markdown: markdown)
    }

    static func dismantleNSView(_ nsView: AutoSizingWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        nsView.onResize = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"
        private static let heightMeasurementScript = """
        Math.max(
            document.getElementById('content')?.getBoundingClientRect().height ?? 0,
            document.body.scrollHeight,
            document.documentElement.scrollHeight
        )
        """

        @Binding private var contentHeight: CGFloat
        private weak var webView: AutoSizingWebView?
        private var lastHTML: String?

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func attach(_ webView: AutoSizingWebView) {
            self.webView = webView
        }

        func load(markdown: String) {
            let html = MarkdownHTMLDocument.makeHTML(for: markdown)
            guard html != lastHTML else {
                requestHeightUpdate()
                return
            }

            lastHTML = html
            webView?.loadHTMLString(html, baseURL: nil)
        }

        func requestHeightUpdate() {
            webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
            measureContentHeight()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                message.name == Self.heightMessageName,
                let number = message.body as? NSNumber
            else {
                return
            }

            let resolvedHeight = max(CGFloat(truncating: number), 24)
            updateContentHeight(resolvedHeight)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureContentHeight()

            for delay in [0.05, 0.2, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.measureContentHeight()
                }
            }
        }

        private func measureContentHeight() {
            webView?.evaluateJavaScript(Self.heightMeasurementScript) { [weak self] value, _ in
                guard
                    let self,
                    let number = value as? NSNumber
                else {
                    return
                }

                self.updateContentHeight(max(CGFloat(truncating: number), 24))
            }
        }

        private func updateContentHeight(_ resolvedHeight: CGFloat) {
            if abs(resolvedHeight - contentHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.contentHeight = resolvedHeight
                }
            }
        }
    }
}

private final class AutoSizingWebView: WKWebView {
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}
