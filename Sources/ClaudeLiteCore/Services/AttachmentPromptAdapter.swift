import Foundation

enum AttachmentPromptAdapter {
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
                let data = try? Data(contentsOf: localURL),
                data.count <= 32_000,
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
}
