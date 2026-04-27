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
        userContentController.addUserScript(Coordinator.heightObserverUserScript)
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
        nsView.configuration.userContentController.removeAllUserScripts()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"
        static let heightObserverUserScript = WKUserScript(
            source: """
            (() => {
              if (window.__claudeLiteHeightObserverInstalled) {
                window.__claudeLiteScheduleHeightReport?.();
                return;
              }

              window.__claudeLiteHeightObserverInstalled = true;
              let lastHeight = 0;
              let pending = false;

              function measuredHeight() {
                const content = document.getElementById('content');
                return Math.ceil(Math.max(
                  content?.getBoundingClientRect().height ?? 0,
                  document.body?.scrollHeight ?? 0,
                  document.documentElement?.scrollHeight ?? 0
                ));
              }

              function postHeight() {
                const height = measuredHeight();
                if (!Number.isFinite(height) || height <= 0 || Math.abs(height - lastHeight) <= 0.5) {
                  return;
                }

                lastHeight = height;
                if (window.webkit?.messageHandlers?.contentHeight) {
                  window.webkit.messageHandlers.contentHeight.postMessage(height);
                }
              }

              function flushHeightReport() {
                if (!pending) {
                  return;
                }

                pending = false;
                postHeight();
              }

              function scheduleHeightReport() {
                if (pending) {
                  return;
                }

                pending = true;
                requestAnimationFrame(() => {
                  requestAnimationFrame(flushHeightReport);
                });
                setTimeout(flushHeightReport, 50);
              }

              function installObservers() {
                const content = document.getElementById('content');
                const targets = [content, document.body, document.documentElement].filter(Boolean);

                if (window.ResizeObserver) {
                  const resizeObserver = new ResizeObserver(scheduleHeightReport);
                  targets.forEach((target) => resizeObserver.observe(target));
                  window.__claudeLiteHeightResizeObserver = resizeObserver;
                }

                if (content && window.MutationObserver) {
                  const mutationObserver = new MutationObserver(scheduleHeightReport);
                  mutationObserver.observe(content, {
                    attributes: true,
                    characterData: true,
                    childList: true,
                    subtree: true
                  });
                  window.__claudeLiteHeightMutationObserver = mutationObserver;
                }

                scheduleHeightReport();
              }

              window.__claudeLiteScheduleHeightReport = scheduleHeightReport;

              if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', installObservers, { once: true });
              } else {
                installObservers();
              }

              window.addEventListener('load', scheduleHeightReport);
              window.addEventListener('resize', scheduleHeightReport);
              document.fonts?.ready?.then(scheduleHeightReport, () => {});
              window.MathJax?.startup?.promise?.then(scheduleHeightReport, () => {});
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        private static let heightMeasurementScript = """
        Math.ceil(Math.max(
            document.getElementById('content')?.getBoundingClientRect().height ?? 0,
            document.body?.scrollHeight ?? 0,
            document.documentElement?.scrollHeight ?? 0
        ))
        """

        @Binding private var contentHeight: CGFloat
        private weak var webView: AutoSizingWebView?
        private var lastMarkdown: String?
        private var pendingHeightMeasurement = false
        private var lastResolvedHeight: CGFloat = 24

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func attach(_ webView: AutoSizingWebView) {
            self.webView = webView
        }

        func load(markdown: String) {
            guard markdown != lastMarkdown else {
                requestHeightUpdate()
                return
            }

            lastMarkdown = markdown
            let html = MarkdownHTMLDocument.makeHTML(for: markdown)
            webView?.loadHTMLString(html, baseURL: nil)
        }

        func requestHeightUpdate() {
            guard !pendingHeightMeasurement else {
                return
            }

            pendingHeightMeasurement = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.pendingHeightMeasurement = false
                self.webView?.evaluateJavaScript("window.__claudeLiteScheduleHeightReport?.();", completionHandler: nil)
                self.measureContentHeight()
            }
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
            requestHeightUpdate()
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
            let resolvedHeight = max(resolvedHeight.rounded(.up), 24)
            guard abs(resolvedHeight - lastResolvedHeight) > 0.5 || abs(resolvedHeight - contentHeight) > 0.5 else {
                return
            }

            lastResolvedHeight = resolvedHeight
            DispatchQueue.main.async { [weak self] in
                self?.contentHeight = resolvedHeight
            }
        }
    }
}

private final class AutoSizingWebView: WKWebView {
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if abs(newSize.width - oldWidth) > 0.5 {
            onResize?()
        }
    }
}
