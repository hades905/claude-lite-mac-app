import Foundation
import Testing
@testable import ClaudeLiteCore

struct AppSupportStoragePrunerTests {
    @Test
    func prunerKeepsProtectedFilesAndRemovesOldReclaimableFilesUntilUnderLimit() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let configURL = directory.appending(path: ".local/tuzi-config.json")
        let sessionURL = directory.appending(path: "session.json")
        let oldLogURL = directory.appending(path: "Logs/old.log")
        let newLogURL = directory.appending(path: "Logs/new.log")
        let cacheURL = directory.appending(path: "Cache/render-cache.bin")

        try writeFile(configURL, byteCount: 4_000, age: 100)
        try writeFile(sessionURL, byteCount: 4_000, age: 90)
        try writeFile(oldLogURL, byteCount: 70_000, age: 80)
        try writeFile(newLogURL, byteCount: 20_000, age: 10)
        try writeFile(cacheURL, byteCount: 20_000, age: 70)

        let result = try AppSupportStoragePruner.prune(directoryURL: directory, maxTotalBytes: 32_000)

        #expect(FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: sessionURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: oldLogURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)))
        #expect(totalSize(in: directory) <= 32_000)
        #expect(result.beforeBytes == 118_000)
        #expect(result.afterBytes == totalSize(in: directory))
        #expect(result.removedBytes == 90_000)
        #expect(result.removedFileCount == 2)
    }

    @Test
    func prunerCountsAndRemovesHiddenFilesInsideReclaimableDirectories() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let configURL = directory.appending(path: ".local/tuzi-config.json")
        let hiddenCacheURL = directory.appending(path: "Cache/.render-cache.bin")
        let visibleCacheURL = directory.appending(path: "Cache/render-cache.bin")

        try writeFile(configURL, byteCount: 4_000, age: 100)
        try writeFile(hiddenCacheURL, byteCount: 70_000, age: 80)
        try writeFile(visibleCacheURL, byteCount: 20_000, age: 10)

        let result = try AppSupportStoragePruner.prune(directoryURL: directory, maxTotalBytes: 24_000)

        #expect(FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: hiddenCacheURL.path(percentEncoded: false)))
        #expect(totalSize(in: directory) <= 24_000)
        #expect(result.beforeBytes == 94_000)
        #expect(result.removedBytes >= 70_000)
        #expect(result.removedFileCount >= 1)
    }

    @Test
    func prunerAvoidsRepeatedFullDirectoryScansWhileRemovingManyFiles() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let counter = ScanCounter()

        try writeFile(directory.appending(path: "session.json"), byteCount: 1_000, age: 1)
        for index in 0 ..< 12 {
            try writeFile(
                directory.appending(path: "Cache/cache-\(index).bin"),
                byteCount: 10_000,
                age: TimeInterval(100 - index)
            )
        }

        let result = try AppSupportStoragePruner.prune(
            directoryURL: directory,
            maxTotalBytes: 11_000,
            scanObserver: counter.recordScan
        )

        #expect(result.removedFileCount == 11)
        #expect(totalSize(in: directory) <= 11_000)
        #expect(counter.scanCount <= 3)
    }

    private func writeFile(_ url: URL, byteCount: Int, age: TimeInterval) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: byteCount).write(to: url)
        let date = Date(timeIntervalSinceNow: -age)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private func totalSize(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
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
}

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var scans = 0

    var scanCount: Int {
        lock.withLock { scans }
    }

    func recordScan() {
        lock.withLock {
            scans += 1
        }
    }
}
