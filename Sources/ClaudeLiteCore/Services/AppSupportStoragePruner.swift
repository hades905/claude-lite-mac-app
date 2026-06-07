import Foundation

public enum AppSupportStoragePruner {
    public static let defaultMaxTotalBytes = 100 * 1_024 * 1_024

    public struct PruneResult: Equatable, Sendable {
        public let beforeBytes: Int
        public let afterBytes: Int
        public let removedBytes: Int
        public let removedFileCount: Int

        public init(beforeBytes: Int, afterBytes: Int, removedBytes: Int, removedFileCount: Int) {
            self.beforeBytes = beforeBytes
            self.afterBytes = afterBytes
            self.removedBytes = removedBytes
            self.removedFileCount = removedFileCount
        }
    }

    @discardableResult
    public static func prune(
        directoryURL: URL,
        maxTotalBytes: Int = defaultMaxTotalBytes,
        fileManager: FileManager = .default
    ) throws -> PruneResult {
        guard maxTotalBytes > 0, fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            return PruneResult(beforeBytes: 0, afterBytes: 0, removedBytes: 0, removedFileCount: 0)
        }

        let beforeBytes = totalSize(in: directoryURL, fileManager: fileManager)
        var removedBytes = 0
        var removedFileCount = 0
        var candidates = try reclaimableFiles(in: directoryURL, fileManager: fileManager)
        while totalSize(in: directoryURL, fileManager: fileManager) > maxTotalBytes {
            guard let oldest = try candidates.min(by: { lhs, rhs in
                try modificationDate(lhs) < modificationDate(rhs)
            }) else {
                break
            }

            let size = fileSize(oldest)
            try? fileManager.removeItem(at: oldest)
            if !fileManager.fileExists(atPath: oldest.path(percentEncoded: false)) {
                removedBytes += size
                removedFileCount += 1
            }
            candidates.removeAll { $0 == oldest }
        }

        return PruneResult(
            beforeBytes: beforeBytes,
            afterBytes: totalSize(in: directoryURL, fileManager: fileManager),
            removedBytes: removedBytes,
            removedFileCount: removedFileCount
        )
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

    private static func fileSize(_ url: URL) -> Int {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return 0
        }

        return fileSize
    }

    private static func modificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }
}
