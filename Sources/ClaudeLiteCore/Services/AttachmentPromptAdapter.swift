import Foundation

enum AttachmentPromptAdapter {
    private static let maxInlineTextFileBytes = 32_000

    private static let textExtensions: Set<String> = [
        "txt", "md", "json", "csv", "tsv", "swift", "py", "js", "ts", "tsx", "jsx",
        "html", "css", "xml", "yaml", "yml", "log"
    ]

    static func renderMessageText(for message: ChatMessage) -> String {
        guard !message.attachments.isEmpty else {
            return message.text
        }

        let attachmentText = message.attachments.map(renderAttachmentSummary).joined(separator: "\n\n")
        if message.text.isEmpty {
            return attachmentText
        }

        return "\(attachmentText)\n\n\(message.text)"
    }

    private static func renderAttachmentSummary(_ attachment: ChatAttachment) -> String {
        switch attachment.kind {
        case .image:
            return "[Image attached: \(attachment.name)]"
        case .file:
            guard
                let localURL = attachment.localURL,
                textExtensions.contains(localURL.pathExtension.lowercased()),
                let readableURL = inlineableTextFileURL(for: localURL),
                let data = try? Data(contentsOf: readableURL),
                data.count <= maxInlineTextFileBytes,
                let text = String(data: data, encoding: .utf8)
            else {
                return "[File attached: \(attachment.name)]"
            }

            return """
            [File attached: \(attachment.name)]
            <file>
            \(text)
            </file>
            """
        }
    }

    private static func inlineableTextFileURL(for url: URL) -> URL? {
        guard url.isFileURL else {
            return nil
        }

        let resolvedURL = url.resolvingSymlinksInPath()
        guard
            let values = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize <= maxInlineTextFileBytes
        else {
            return nil
        }

        return resolvedURL
    }
}
