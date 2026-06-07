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

        try AppSupportStoragePruner.prune(directoryURL: directory, maxTotalBytes: 32_000)

        #expect(FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: sessionURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: oldLogURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)))
        #expect(totalSize(in: directory) <= 32_000)
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
}
