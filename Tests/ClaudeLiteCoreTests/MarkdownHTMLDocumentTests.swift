import Foundation
import Testing
@testable import ClaudeLiteCore

struct MarkdownHTMLDocumentTests {
    @Test
    func includesInlineMarkdownAndMathRenderingHooks() {
        let html = MarkdownHTMLDocument.makeHTML(for: """
        # Title

        Inline math: $E=mc^2$

        ```swift
        print("hello")
        ```
        """)

        #expect(!html.contains("marked.min.js"))
        #expect(!html.contains("tex-svg.js"))
        #expect(html.contains("article.textContent = source"))
        #expect(html.contains("window.MathJax"))
        #expect(html.contains("marked v13.0.2"))
        #expect(html.contains("white-space: pre-wrap"))
        #expect(html.contains("print(\\\"hello\\\")"))
        #expect(html.contains("E=mc^2"))
    }

    @Test
    func skipsMathJaxForCurrencyText() {
        let html = MarkdownHTMLDocument.makeHTML(for: "This costs $5 today")

        #expect(html.contains("This costs $5 today"))
        #expect(!html.contains("window.MathJax = {"))
        #expect(!html.contains("MathJax.loader"))
        #expect(!MarkdownHTMLDocument.containsSupportedMath(in: "This costs $5 or $6 today"))
        #expect(MarkdownHTMLDocument.containsSupportedMath(in: "$E=mc^2$"))
    }

    @Test
    func includesMathJaxForChineseParagraphWithStandaloneDisplayMath() {
        let html = MarkdownHTMLDocument.makeHTML(for: """
        这是一个中文段落，用来确认公式前后的正文不会影响数学渲染。

        $$
        R_{\\mu\\nu} = \\partial_\\lambda \\Gamma^{\\lambda}_{\\mu\\nu} - \\partial_\\nu \\Gamma^{\\lambda}_{\\mu\\lambda}
        $$
        """)

        #expect(html.contains("这是一个中文段落"))
        #expect(html.contains("window.MathJax = {"))
        #expect(html.contains("MathJax.loader"))
        #expect(html.contains("R_{\\\\mu\\\\nu}"))
    }

    @Test
    func includesMathJaxForSupportedMathDelimiters() {
        let examples = [
            "$E=mc^2$",
            "$$a^2+b^2=c^2$$",
            "\\(x+y\\)"
        ]

        for markdown in examples {
            let html = MarkdownHTMLDocument.makeHTML(for: markdown)

            #expect(html.contains("window.MathJax = {"))
            #expect(html.contains("MathJax.loader"))
        }
    }

    @Test
    func embedsMarkedRuntimeOutsideProjectDirectory() throws {
        let tempDirectory = try TestSupport.makeTemporaryDirectory()
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probeSourceURL = tempDirectory.appending(path: "probe.swift")
        let bundleAccessorURL = tempDirectory.appending(path: "resource_bundle_accessor.swift")
        let binaryURL = tempDirectory.appending(path: "markdown-probe")
        let markdownDocumentURL = packageRoot
            .appending(path: "Sources/ClaudeLiteCore/Rendering/MarkdownHTMLDocument.swift")
        let markdownDocumentSource = try String(contentsOf: markdownDocumentURL, encoding: .utf8)
        let usesModuleBundle = markdownDocumentSource.contains("Bundle.module")

        try """
        import Foundation

        @main
        struct Probe {
            static func main() {
                let html = MarkdownHTMLDocument.makeHTML(for: "# Title\\n\\nFirst line\\nSecond line")
                print(html.contains("marked v13.0.2") ? "HAS_MARKED" : "NO_MARKED")
            }
        }
        """.write(to: probeSourceURL, atomically: true, encoding: .utf8)

        var compileArguments = [
            "swiftc",
            "-o", binaryURL.path(percentEncoded: false),
            probeSourceURL.path(percentEncoded: false),
            markdownDocumentURL.path(percentEncoded: false)
        ]

        if usesModuleBundle {
            let bundleURL = try builtResourceBundleURL(in: packageRoot)
            try """
            import Foundation

            extension Foundation.Bundle {
                static let module: Bundle = {
                    guard let bundle = Bundle(path: "\(bundleURL.path(percentEncoded: false))") else {
                        Swift.fatalError("Missing test resource bundle at \(bundleURL.path(percentEncoded: false))")
                    }
                    return bundle
                }()
            }
            """.write(to: bundleAccessorURL, atomically: true, encoding: .utf8)
            compileArguments.insert(bundleAccessorURL.path(percentEncoded: false), at: 3)
        }

        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: compileArguments,
            currentDirectoryURL: packageRoot
        )

        let output = try runProcess(
            executableURL: binaryURL,
            arguments: [],
            currentDirectoryURL: tempDirectory
        )

        #expect(output.contains("HAS_MARKED"))
    }

    private func builtResourceBundleURL(in packageRoot: URL) throws -> URL {
        let buildDirectory = packageRoot.appending(path: ".build", directoryHint: .isDirectory)
        let enumerator = FileManager.default.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent.hasSuffix("ClaudeLiteCore.bundle") else {
                continue
            }

            return url
        }

        throw NSError(domain: "MarkdownHTMLDocumentTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to find built ClaudeLiteCore resource bundle."
        ])
    }

    @discardableResult
    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let errorOutput = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "MarkdownHTMLDocumentTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Process failed: \(executableURL.lastPathComponent) \(arguments.joined(separator: " "))\n\(errorOutput)"
            ])
        }

        return output
    }
}
