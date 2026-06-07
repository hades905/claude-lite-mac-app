import Foundation

public enum AppSupportStoragePruner {
    public static let defaultMaxTotalBytes = 100 * 1_024 * 1_024

    public static func prune(
        directoryURL: URL,
        maxTotalBytes: Int = defaultMaxTotalBytes,
        fileManager: FileManager = .default
    ) throws {
        guard maxTotalBytes > 0, fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            return
        }

        var candidates = try reclaimableFiles(in: directoryURL, fileManager: fileManager)
        while totalSize(in: directoryURL, fileManager: fileManager) > maxTotalBytes {
            guard let oldest = try candidates.min(by: { lhs, rhs in
                try modificationDate(lhs) < modificationDate(rhs)
            }) else {
                return
            }

            try? fileManager.removeItem(at: oldest)
            candidates.removeAll { $0 == oldest }
        }
    }

    private static func reclaimableFiles(in directoryURL: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard
                let url = item as? URL,
                isReclaimable(url, relativeTo: directoryURL),
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else {
                return nil
            }

            return url
        }
    }

    private static func isReclaimable(_ url: URL, relativeTo directoryURL: URL) -> Bool {
        let baseComponents = normalizedPathComponents(directoryURL)
        let fileComponents = normalizedPathComponents(url)
        guard fileComponents.count > baseComponents.count else {
            return false
        }

        guard Array(fileComponents.prefix(baseComponents.count)) == baseComponents else {
            return false
        }

        let relativeComponents = fileComponents.dropFirst(baseComponents.count)
        guard let firstComponent = relativeComponents.first else {
            return false
        }

        return ["Logs", "Cache", "Caches", "Temporary", "tmp"].contains(firstComponent)
    }

    private static func normalizedPathComponents(_ url: URL) -> [String] {
        var components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        if components.count > 1, components[1] == "private" {
            components.remove(at: 1)
        }
        return components
    }

    private static func totalSize(in directoryURL: URL, fileManager: FileManager) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.compactMap { item -> Int? in
            guard
                let url = item as? URL,
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else {
                return nil
            }

            return values.fileSize
        }.reduce(0, +)
    }

    private static func modificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }
}
