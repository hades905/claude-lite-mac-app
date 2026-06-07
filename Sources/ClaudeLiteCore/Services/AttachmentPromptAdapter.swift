import Foundation
import UniformTypeIdentifiers

enum AttachmentPromptAdapter {
    private static let maxInlineTextFileBytes = 32_000
    static let maxFileAttachmentBytes = 20 * 1_024 * 1_024
    static let maxImageAttachmentBytes = 20 * 1_024 * 1_024

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

    static func renderMessageContent(for message: ChatMessage) throws -> MessageContent {
        guard message.attachments.contains(where: { $0.kind == .image }) else {
            return .text(renderMessageText(for: message))
        }

        var blocks: [ContentBlock] = []
        for attachment in message.attachments {
            switch attachment.kind {
            case .image:
                let image = try renderImageAttachment(attachment)
                blocks.append(.image(mediaType: image.mediaType, data: image.base64Data))
            case .file:
                let text = renderAttachmentSummary(attachment)
                if !text.isEmpty {
                    blocks.append(.text(text))
                }
            }
        }

        if !message.text.isEmpty {
            blocks.append(.text(message.text))
        }

        return .blocks(blocks)
    }

    enum MessageContent: Encodable {
        case text(String)
        case blocks([ContentBlock])

        func encode(to encoder: any Encoder) throws {
            switch self {
            case let .text(text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case let .blocks(blocks):
                var container = encoder.singleValueContainer()
                try container.encode(blocks)
            }
        }
    }

    enum ContentBlock: Encodable {
        case text(String)
        case image(mediaType: String, data: String)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
        }

        enum SourceCodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .text(text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case let .image(mediaType, data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(data, forKey: .data)
            }
        }
    }

    private static func renderAttachmentSummary(_ attachment: ChatAttachment) -> String {
        let safeName = sanitizedAttachmentName(attachment.name)
        switch attachment.kind {
        case .image:
            return "[Image attached: \(safeName)]"
        case .file:
            guard
                let localURL = attachment.localURL,
                textExtensions.contains(localURL.pathExtension.lowercased()),
                let readableURL = inlineableTextFileURL(for: localURL),
                let data = try? Data(contentsOf: readableURL),
                data.count <= maxInlineTextFileBytes,
                let text = String(data: data, encoding: .utf8)
            else {
                return "[File attached: \(safeName)]"
            }

            return """
            [File attached: \(safeName)]
            <file>
            \(text)
            </file>
            """
        }
    }

    private static func sanitizedAttachmentName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || ".-_ ".unicodeScalars.contains(scalar)
                ? Character(scalar)
                : "_"
        }
        let collapsed = String(scalars).replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "attachment" : trimmed
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

    private static func renderImageAttachment(_ attachment: ChatAttachment) throws -> ImageAttachmentPayload {
        guard let localURL = attachment.localURL, localURL.isFileURL else {
            throw AttachmentPromptAdapterError.unreadableImage(attachment.name)
        }

        guard imageAttachmentIsWithinSizeLimit(localURL) else {
            throw AttachmentPromptAdapterError.imageTooLarge(attachment.name)
        }

        let mediaType = mimeType(for: localURL) ?? "application/octet-stream"
        let data = try readSecurityScopedData(from: localURL)
        guard !data.isEmpty else {
            throw AttachmentPromptAdapterError.unreadableImage(attachment.name)
        }

        return ImageAttachmentPayload(mediaType: mediaType, base64Data: data.base64EncodedString())
    }

    private static func readSecurityScopedData(from url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: url)
    }

    static func imageAttachmentIsWithinSizeLimit(_ url: URL) -> Bool {
        fileAttachmentIsWithinSizeLimit(url)
    }

    static func fileAttachmentIsWithinSizeLimit(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard
            let values = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let fileSize = values.fileSize
        else {
            return false
        }

        return fileSize <= maxFileAttachmentBytes
    }

    private static func mimeType(for url: URL) -> String? {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType
        }
    }
}

enum AttachmentPromptAdapterError: Error, Equatable {
    case unreadableImage(String)
    case imageTooLarge(String)
    case fileTooLarge(String)
}

private struct ImageAttachmentPayload {
    let mediaType: String
    let base64Data: String
}
