import Foundation

public final class PersistentSessionStore: SessionStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> SessionSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SessionSnapshot.self, from: data)
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
