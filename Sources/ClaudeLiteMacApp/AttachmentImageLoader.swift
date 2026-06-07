import AppKit
import ClaudeLiteCore
import Foundation
import ImageIO

enum AttachmentImageLoader {
    static let thumbnailPixelSize: CGFloat = 384
    static let previewPixelSize: CGFloat = 3_200

    static func thumbnail(for attachment: ChatAttachment, maxPixelSize: CGFloat = thumbnailPixelSize) -> NSImage? {
        image(for: attachment, maxPixelSize: maxPixelSize)
    }

    static func previewImage(for attachment: ChatAttachment, maxPixelSize: CGFloat = previewPixelSize) -> NSImage? {
        image(for: attachment, maxPixelSize: maxPixelSize)
    }

    private static func image(for attachment: ChatAttachment, maxPixelSize: CGFloat) -> NSImage? {
        guard attachment.kind == .image, let url = attachment.localURL else {
            return nil
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
