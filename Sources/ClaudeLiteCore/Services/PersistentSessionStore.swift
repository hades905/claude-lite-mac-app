import Foundation

public final class PersistentSessionStore: SessionStoring {
    public static let defaultMaxSessionFileBytes = 2 * 1_024 * 1_024

    private let fileURL: URL
    private let maxSessionFileBytes: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL, maxSessionFileBytes: Int = defaultMaxSessionFileBytes) {
        self.fileURL = fileURL
        self.maxSessionFileBytes = maxSessionFileBytes
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> SessionSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return .empty
        }

        guard fileSize() <= maxSessionFileBytes else {
            try? FileManager.default.removeItem(at: fileURL)
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode(SessionSnapshot.self, from: data)
        } catch is DecodingError {
            try? FileManager.default.removeItem(at: fileURL)
            return .empty
        }
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private func fileSize() -> Int {
        guard
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return 0
        }

        return fileSize
    }
}
