import AppKit
import SwiftUI
import Testing
import WebKit
@testable import ClaudeLiteMacApp

@MainActor
struct MarkdownMessageViewIntegrationTests {
    @Test
    func markdownMessageViewBuildsStructuredDOM() async throws {
        _ = NSApplication.shared

        let markdown = """
        # Title

        First line

        - one
        - two
        """

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: MarkdownMessageView(markdown: markdown))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer {
            window.orderOut(nil)
        }

        let webView = try await findWebView(in: hostingView)
        try await waitForJavaScript(
            "document.querySelector('h1')?.textContent === 'Title' && document.querySelector('ul') !== null && (document.getElementById('content')?.childElementCount ?? 0) > 0",
            in: webView
        )

        let childCount = try await javaScriptInt(
            "document.getElementById('content')?.childElementCount ?? 0",
            in: webView
        )
        let listCount = try await javaScriptInt(
            "document.querySelectorAll('li').length",
            in: webView
        )

        #expect(childCount ?? 0 > 0)
        #expect(listCount == 2)
    }

    @Test
    func markdownMessageViewExpandsToFitLongRenderedMarkdown() async throws {
        _ = NSApplication.shared

        let markdown = """
        # Long rendered answer

        This answer intentionally mixes several Markdown features that change height while the WebView is loading. It starts with normal text so the fallback renderer has one shape, then it switches to richer content after Markdown and MathJax finish.

        ## Comparison table

        | Step | What changes | Why it matters |
        | ---- | ------------ | -------------- |
        | Parse | Markdown becomes headings, paragraphs, and a table. | The document gets taller after the first paint. |
        | Typeset | Display math becomes SVG. | MathJax can change the final layout after Markdown parsing. |
        | Measure | The native view updates its frame. | The SwiftUI bubble must grow instead of clipping. |

        $$\\sum_{k=1}^{n} k^2 = \\frac{n(n+1)(2n+1)}{6}$$

        The first long paragraph continues with enough prose to require multiple visual lines at the test width. The important part is that the answer should remain readable all the way to the end, without hiding the last paragraphs below the native WebView frame.

        A second long paragraph adds more vertical space after the display math. This mirrors a real assistant answer where explanatory text often follows formulas, tables, and headings instead of ending immediately after the math block.

        ### Final notes

        The final paragraph must still be visible. If the WebView reports an early height and never updates after rich rendering completes, this paragraph is the kind of content that gets clipped in the chat bubble.
        """

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 140),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: ScrollView {
                LazyVStack(alignment: .leading) {
                    MarkdownMessageView(markdown: markdown)
                        .frame(width: 580, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 620, height: 140)
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer {
            window.orderOut(nil)
        }

        let webView = try await findWebView(in: hostingView)
        try await waitForJavaScript("window.__renderComplete === true", in: webView)
        try await Task.sleep(for: .milliseconds(700))

        let appendedLateContent = try await javaScriptBool("""
        (() => {
            const article = document.getElementById('content');
            if (!article) {
                return false;
            }

            const lateContent = document.createElement('section');
            lateContent.id = 'late-rendered-content';
            lateContent.innerHTML = `
                <p>The renderer added this paragraph after Markdown and MathJax completed. The native view still needs to grow when final layout changes arrive late.</p>
                <p>Another paragraph makes the height difference large enough to catch clipping instead of hiding it behind a small tolerance.</p>
                <p>The last line should remain visible inside the WebView viewport after the height is reported back to SwiftUI.</p>
            `;
            article.appendChild(lateContent);
            return true;
        })()
        """, in: webView)
        #expect(appendedLateContent == true)

        try await waitForUnclippedContent(in: webView, hostedBy: hostingView)

        let renderedHeight = try await javaScriptDouble(Self.renderedHeightScript, in: webView)
        let viewportHeight = try await javaScriptDouble("Math.ceil(window.innerHeight)", in: webView)

        #expect((renderedHeight ?? 0) > 360)
        #expect((viewportHeight ?? 0) + 2 >= (renderedHeight ?? 0))
        #expect(webView.frame.height + 2 >= CGFloat(renderedHeight ?? 0))
    }

    private func findWebView(in rootView: NSView) async throws -> WKWebView {
        for _ in 0..<50 {
            if let webView = firstWebView(in: rootView) {
                return webView
            }

            try await Task.sleep(for: .milliseconds(100))
            rootView.layoutSubtreeIfNeeded()
        }

        throw NSError(domain: "MarkdownMessageViewIntegrationTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to locate WKWebView inside MarkdownMessageView."
        ])
    }

    private func firstWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }

        for subview in view.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }

        return nil
    }

    private func waitForJavaScript(_ script: String, in webView: WKWebView) async throws {
        for _ in 0..<50 {
            if try await javaScriptBool(script, in: webView) == true {
                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        Issue.record("Timed out waiting for MarkdownMessageView DOM to finish rendering.")
    }

    private func waitForUnclippedContent(in webView: WKWebView, hostedBy hostingView: NSView) async throws {
        for _ in 0..<50 {
            hostingView.layoutSubtreeIfNeeded()

            let renderedHeight = try await javaScriptDouble(Self.renderedHeightScript, in: webView) ?? 0
            let viewportHeight = try await javaScriptDouble("Math.ceil(window.innerHeight)", in: webView) ?? 0
            if renderedHeight > 360, viewportHeight + 2 >= renderedHeight, webView.frame.height + 2 >= CGFloat(renderedHeight) {
                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        let renderedHeight = try await javaScriptDouble(Self.renderedHeightScript, in: webView) ?? 0
        let viewportHeight = try await javaScriptDouble("Math.ceil(window.innerHeight)", in: webView) ?? 0
        Issue.record("Timed out waiting for MarkdownMessageView to fit rendered content. renderedHeight=\(renderedHeight), viewportHeight=\(viewportHeight), webViewHeight=\(webView.frame.height)")
    }

    private static let renderedHeightScript = """
    Math.ceil(Math.max(
        document.getElementById('content')?.getBoundingClientRect().height ?? 0,
        document.body.scrollHeight,
        document.documentElement.scrollHeight
    ))
    """

    private func javaScriptInt(_ script: String, in webView: WKWebView) async throws -> Int? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (value as? NSNumber)?.intValue)
                }
            }
        }
    }

    private func javaScriptDouble(_ script: String, in webView: WKWebView) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (value as? NSNumber)?.doubleValue)
                }
            }
        }
    }

    private func javaScriptBool(_ script: String, in webView: WKWebView) async throws -> Bool? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (value as? NSNumber)?.boolValue)
                }
            }
        }
    }
}
