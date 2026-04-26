import Foundation

public enum MarkdownHTMLDocument {
    private static let renderingDirectoryName = "claude-lite-markdown-renderer"
    private static let markedRuntime = loadJavaScriptAsset(named: "marked.min")
    private static let mathJaxRuntime = loadJavaScriptAsset(named: "tex-svg")

    public static func makeHTML(for markdown: String) -> String {
        let source = javaScriptStringLiteral(for: markdown)
        let includesMath = containsMath(in: markdown)
        let mathJaxConfiguration = includesMath ? """
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
              },
              svg: {
                fontCache: 'global'
              }
            };
          </script>
        """ : ""
        let mathJaxRuntimeScript = includesMath ? """
          <script>
        \(mathJaxRuntime)
          </script>
        """ : ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light only;
              --text: #171717;
              --muted: #5f6368;
              --border: rgba(15, 23, 42, 0.12);
              --code-bg: rgba(15, 23, 42, 0.06);
              --quote-bg: rgba(15, 23, 42, 0.03);
              --link: #0f6fff;
            }

            * {
              box-sizing: border-box;
            }

            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: var(--text);
              font: 14px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }

            body {
              overflow: hidden;
            }

            #content {
              min-height: 20px;
              word-break: break-word;
            }

            #content.markdown-fallback {
              white-space: pre-wrap;
            }

            #content > :first-child {
              margin-top: 0;
            }

            #content > :last-child {
              margin-bottom: 0;
            }

            a {
              color: var(--link);
            }

            p, ul, ol, blockquote, pre, table {
              margin: 0 0 0.85em 0;
            }

            h1, h2, h3, h4, h5, h6 {
              margin: 1.1em 0 0.55em 0;
              line-height: 1.25;
            }

            h1 {
              font-size: 1.45em;
            }

            h2 {
              font-size: 1.28em;
            }

            h3 {
              font-size: 1.14em;
            }

            ul, ol {
              padding-left: 1.4em;
            }

            li + li {
              margin-top: 0.3em;
            }

            code {
              padding: 0.12em 0.35em;
              border-radius: 6px;
              background: var(--code-bg);
              font: 12px/1.5 "SF Mono", Menlo, monospace;
            }

            pre {
              padding: 0.85em 1em;
              border-radius: 12px;
              background: var(--code-bg);
              overflow-x: auto;
            }

            pre code {
              padding: 0;
              background: transparent;
            }

            blockquote {
              padding: 0.8em 1em;
              border-left: 4px solid var(--border);
              background: var(--quote-bg);
              color: var(--muted);
              border-radius: 0 12px 12px 0;
            }

            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 0.95em;
            }

            th, td {
              padding: 0.55em 0.7em;
              border: 1px solid var(--border);
              text-align: left;
              vertical-align: top;
            }

            img {
              max-width: 100%;
              border-radius: 12px;
            }

            hr {
              border: 0;
              border-top: 1px solid var(--border);
              margin: 1em 0;
            }
          </style>
        \(mathJaxConfiguration)
          <script>
        \(markedRuntime)
          </script>
        \(mathJaxRuntimeScript)
        </head>
        <body>
          <article id="content"></article>
          <script>
            const source = \(source);
            const article = document.getElementById('content');
            window.__renderComplete = false;

            function reportHeight() {
              requestAnimationFrame(() => {
                const height = Math.max(
                  article.getBoundingClientRect().height,
                  document.body.scrollHeight,
                  document.documentElement.scrollHeight
                );
                if (window.webkit?.messageHandlers?.contentHeight) {
                  window.webkit.messageHandlers.contentHeight.postMessage(height);
                }
              });
            }

            function renderFallback() {
              article.className = 'markdown-fallback';
              article.textContent = source;
              reportHeight();
            }

            function renderMarkdown() {
              if (!window.marked?.parse) {
                renderFallback();
                return;
              }

              article.innerHTML = window.marked.parse(source, {
                gfm: true,
                breaks: true
              });
              article.className = '';
              reportHeight();

              if (window.MathJax?.typesetPromise) {
                window.MathJax.typesetPromise([article]).then(() => {
                  window.__renderComplete = true;
                  reportHeight();
                }).catch(() => {
                  window.__renderComplete = true;
                  reportHeight();
                });
                return;
              }

              window.__renderComplete = true;
            }

            renderFallback();
            setTimeout(renderMarkdown, 0);
            window.addEventListener('resize', reportHeight);
          </script>
        </body>
        </html>
        """
    }

    public static func writeTemporaryFile(for markdown: String) throws -> URL {
        let directoryURL = try preparedRenderingDirectory()
        let fileURL = directoryURL.appending(path: "\(UUID().uuidString).html")
        try makeHTML(for: markdown).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public static func cleanupTemporaryFile(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func javaScriptStringLiteral(for markdown: String) -> String {
        let jsonObject = [markdown]
        let data = try? JSONSerialization.data(withJSONObject: jsonObject)
        let string = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(string.dropFirst().dropLast())
    }

    private static func containsMath(in markdown: String) -> Bool {
        markdown.contains("$$")
            || markdown.contains("$")
            || markdown.contains("\\(")
            || markdown.contains("\\[")
    }

    private static func preparedRenderingDirectory() throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appending(
            path: renderingDirectoryName,
            directoryHint: .isDirectory
        )

        if !fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private static func loadJavaScriptAsset(named name: String) -> String {
        guard
            let sourceURL = Bundle.module.url(forResource: name, withExtension: "js"),
            let source = try? String(contentsOf: sourceURL, encoding: .utf8)
        else {
            return ""
        }

        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }
}
