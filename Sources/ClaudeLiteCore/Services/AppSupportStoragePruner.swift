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
        try prune(
            directoryURL: directoryURL,
            maxTotalBytes: maxTotalBytes,
            fileManager: fileManager,
            scanObserver: nil
        )
    }

    static func prune(
        directoryURL: URL,
        maxTotalBytes: Int = defaultMaxTotalBytes,
        fileManager: FileManager = .default,
        scanObserver: (() -> Void)? = nil
    ) throws -> PruneResult {
        guard maxTotalBytes > 0, fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            return PruneResult(beforeBytes: 0, afterBytes: 0, removedBytes: 0, removedFileCount: 0)
        }

        let inventory = try storageInventory(
            in: directoryURL,
            fileManager: fileManager,
            scanObserver: scanObserver
        )
        let beforeBytes = inventory.totalBytes
        var afterBytes = beforeBytes
        var removedBytes = 0
        var removedFileCount = 0

        let candidates = inventory.reclaimableFiles.sorted {
            $0.modificationDate < $1.modificationDate
        }
        for candidate in candidates where afterBytes > maxTotalBytes {
            try? fileManager.removeItem(at: candidate.url)
            if !fileManager.fileExists(atPath: candidate.url.path(percentEncoded: false)) {
                removedBytes += candidate.size
                removedFileCount += 1
                afterBytes -= candidate.size
            }
        }

        return PruneResult(
            beforeBytes: beforeBytes,
            afterBytes: afterBytes,
            removedBytes: removedBytes,
            removedFileCount: removedFileCount
        )
    }

    private struct ReclaimableFile {
        let url: URL
        let size: Int
        let modificationDate: Date
    }

    private struct StorageInventory {
        let totalBytes: Int
        let reclaimableFiles: [ReclaimableFile]
    }

    private static func storageInventory(
        in directoryURL: URL,
        fileManager: FileManager,
        scanObserver: (() -> Void)?
    ) throws -> StorageInventory {
        scanObserver?()
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: []
        ) else {
            return StorageInventory(totalBytes: 0, reclaimableFiles: [])
        }

        var totalBytes = 0
        var reclaimableFiles: [ReclaimableFile] = []
        for item in enumerator {
            guard
                let url = item as? URL,
                let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ]),
                values.isRegularFile == true
            else {
                continue
            }

            let size = values.fileSize ?? 0
            totalBytes += size
            if isReclaimable(url, relativeTo: directoryURL) {
                reclaimableFiles.append(
                    ReclaimableFile(
                        url: url,
                        size: size,
                        modificationDate: values.contentModificationDate ?? .distantPast
                    )
                )
            }
        }

        return StorageInventory(totalBytes: totalBytes, reclaimableFiles: reclaimableFiles)
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

}
