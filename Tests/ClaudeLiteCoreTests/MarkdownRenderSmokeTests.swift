import AppKit
import Foundation
import Testing
import WebKit
@testable import ClaudeLiteCore

@MainActor
struct MarkdownRenderSmokeTests {
    @Test
    func rendersMarkdownAndMathInsideWebView() async throws {
        let markdown = """
        # Title

        - First item
        - Second item

        | Left | Right |
        | ---- | ----- |
        | A    | B     |

        ```swift
        print("hello")
        ```

        Inline math: $E=mc^2$

        $$a^2+b^2=c^2$$

        Escaped math: \\(x+y\\)
        """
        let documentURL = try MarkdownHTMLDocument.writeTemporaryFile(for: markdown)
        defer {
            MarkdownHTMLDocument.cleanupTemporaryFile(at: documentURL)
        }

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadFileURL(documentURL, allowingReadAccessTo: documentURL.deletingLastPathComponent())
        await delegate.waitForFinish()
        try await waitForRenderCompletion(in: webView)

        let heading = try await javaScriptString("document.querySelector('h1')?.textContent", in: webView)
        let listCount = try await javaScriptInt("document.querySelectorAll('li').length", in: webView)
        let hasTable = try await javaScriptBool("document.querySelector('table') !== null", in: webView)
        let hasCode = try await javaScriptBool("document.querySelector('pre code')?.textContent.includes('print(\"hello\")') ?? false", in: webView)
        let hasMath = try await javaScriptBool("document.querySelector('mjx-container') !== null || document.querySelector('svg') !== null", in: webView)
        let mathCount = try await javaScriptInt("document.querySelectorAll('mjx-container').length", in: webView)

        #expect(heading == "Title")
        #expect(listCount == 2)
        #expect(hasTable == true)
        #expect(hasCode == true)
        #expect(hasMath == true)
        #expect((mathCount ?? 0) >= 3)
    }

    @Test
    func rendersMarkdownAndMathFromGeneratedHTMLString() async throws {
        let markdown = """
        # Title

        - First item
        - Second item

        | Left | Right |
        | ---- | ----- |
        | A    | B     |

        ```swift
        print("hello")
        ```

        Inline math: $E=mc^2$

        $$a^2+b^2=c^2$$

        Escaped math: \\(x+y\\)
        """
        let html = MarkdownHTMLDocument.makeHTML(for: markdown)

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await delegate.waitForFinish()
        try await waitForRenderCompletion(in: webView)

        let heading = try await javaScriptString("document.querySelector('h1')?.textContent", in: webView)
        let listCount = try await javaScriptInt("document.querySelectorAll('li').length", in: webView)
        let hasTable = try await javaScriptBool("document.querySelector('table') !== null", in: webView)
        let hasCode = try await javaScriptBool("document.querySelector('pre code')?.textContent.includes('print(\"hello\")') ?? false", in: webView)
        let hasMath = try await javaScriptBool("document.querySelector('mjx-container') !== null || document.querySelector('svg') !== null", in: webView)
        let mathCount = try await javaScriptInt("document.querySelectorAll('mjx-container').length", in: webView)

        #expect(heading == "Title")
        #expect(listCount == 2)
        #expect(hasTable == true)
        #expect(hasCode == true)
        #expect(hasMath == true)
        #expect((mathCount ?? 0) >= 3)
    }

    @Test
    func rendersStandaloneDisplayMathWithoutRawDollarDelimiters() async throws {
        let markdown = """
        这是一个中文段落，用来确认公式前后的正文不会影响数学渲染。

        $$
        R_{\\mu\\nu} = \\partial_\\lambda \\Gamma^{\\lambda}_{\\mu\\nu} - \\partial_\\nu \\Gamma^{\\lambda}_{\\mu\\lambda}
        $$
        """
        let html = MarkdownHTMLDocument.makeHTML(for: markdown)

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await delegate.waitForFinish()
        try await waitForRenderCompletion(in: webView)

        let hasRawDisplayDelimiter = try await javaScriptBool("document.getElementById('content')?.textContent.includes('$$') ?? true", in: webView)
        let hasRenderedMath = try await javaScriptBool("document.querySelector('mjx-container') !== null || document.querySelector('svg') !== null", in: webView)

        #expect(hasRawDisplayDelimiter == false)
        #expect(hasRenderedMath == true)
    }

    @Test
    func rendersMarkdownWithoutUnsafeHTMLOrScriptLinks() async throws {
        let markdown = """
        # Safe heading

        <script>window.__unsafeScriptRan = true</script>
        <img src="x" onerror="window.__unsafeImageRan = true">
        <span style="background-image:url(https://example.com/pixel)">styled</span>
        <img srcset="https://example.com/tracker.png 1x" alt="tracker">
        [bad link](javascript:window.__unsafeLinkRan=true)
        """
        let html = MarkdownHTMLDocument.makeHTML(for: markdown)

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await delegate.waitForFinish()
        try await waitForRenderCompletion(in: webView)

        let scriptCount = try await javaScriptInt("document.querySelectorAll('#content script').length", in: webView)
        let unsafeImageCount = try await javaScriptInt("document.querySelectorAll('#content img[onerror]').length", in: webView)
        let javascriptLinkCount = try await javaScriptInt("document.querySelectorAll('#content a[href^=\"javascript:\"]').length", in: webView)
        let inlineStyleCount = try await javaScriptInt("document.querySelectorAll('#content [style]').length", in: webView)
        let srcsetCount = try await javaScriptInt("document.querySelectorAll('#content [srcset]').length", in: webView)
        let unsafeScriptRan = try await javaScriptBool("window.__unsafeScriptRan === true", in: webView)
        let unsafeImageRan = try await javaScriptBool("window.__unsafeImageRan === true", in: webView)
        let unsafeLinkRan = try await javaScriptBool("window.__unsafeLinkRan === true", in: webView)
        let heading = try await javaScriptString("document.querySelector('h1')?.textContent", in: webView)

        #expect(heading == "Safe heading")
        #expect(scriptCount == 0)
        #expect(unsafeImageCount == 0)
        #expect(javascriptLinkCount == 0)
        #expect(inlineStyleCount == 0)
        #expect(srcsetCount == 0)
        #expect(unsafeScriptRan == false)
        #expect(unsafeImageRan == false)
        #expect(unsafeLinkRan == false)
    }

    private func waitForRenderCompletion(in webView: WKWebView) async throws {
        for _ in 0..<50 {
            let isReady = try await javaScriptBool("window.__renderComplete === true", in: webView)
            if isReady == true {
                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        Issue.record("Markdown render did not complete within timeout.")
    }

    private func javaScriptString(_ script: String, in webView: WKWebView) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String)
                }
            }
        }
    }

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

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForFinish() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}
