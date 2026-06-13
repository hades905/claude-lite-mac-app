import Foundation

public protocol AppLogging: Sendable {
    func record(event: String, metadata: [String: String]) throws
}

public struct NoopAppLogger: AppLogging {
    public init() {}

    public func record(event: String, metadata: [String: String]) throws {}
}

public final class RotatingAppLogger: AppLogging, @unchecked Sendable {
    public static let defaultMaxTotalBytes = 100 * 1_024 * 1_024
    private let directoryURL: URL
    private let fileName: String
    private let maxFileBytes: Int
    private let maxTotalBytes: Int
    private let fileManager: FileManager
    private let pruneSizePassObserver: (@Sendable () -> Void)?
    private let lock = NSLock()
    private let sensitiveKeys: Set<String> = [
        "apikey", "api_key", "authorization", "bearer", "token", "key",
        "prompt", "reply", "conversation", "content", "text"
    ]

    public init(
        directoryURL: URL,
        fileName: String = "claude-lite.log",
        maxFileBytes: Int = 1_024 * 1_024,
        maxTotalBytes: Int = defaultMaxTotalBytes,
        fileManager: FileManager = .default,
        pruneSizePassObserver: (@Sendable () -> Void)? = nil
    ) {
        self.directoryURL = directoryURL
        self.fileName = fileName
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
        self.fileManager = fileManager
        self.pruneSizePassObserver = pruneSizePassObserver
    }

    public func record(event: String, metadata: [String: String] = [:]) throws {
        lock.withLock {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let activeURL = directoryURL.appending(path: fileName)
                try rotateActiveLogIfNeeded(activeURL: activeURL)
                let line = logLine(event: event, metadata: metadata)
                try append(line, to: activeURL)
                try pruneLogs()
            } catch {
                // Logging must never make app behavior worse.
            }
        }
    }

    private func logLine(event: String, metadata: [String: String]) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeEvent = sanitize(event)
        let fields = metadata
            .sorted { $0.key < $1.key }
            .map { key, value in "\(sanitize(key))=\(redactedValue(value, for: key))" }
            .joined(separator: " ")

        if fields.isEmpty {
            return "\(timestamp) event=\(safeEvent)\n"
        }

        return "\(timestamp) event=\(safeEvent) \(fields)\n"
    }

    private func redactedValue(_ value: String, for key: String) -> String {
        let normalizedKey = key.lowercased()
        guard !sensitiveKeys.contains(where: { normalizedKey.contains($0) }) else {
            return "<redacted>"
        }

        return redactSensitiveTokens(in: redactLocalPaths(in: sanitize(value)))
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private func redactSensitiveTokens(in value: String) -> String {
        var redacted = value
        let patterns = [
            #"Bearer [A-Za-z0-9._-]{12,}"#,
            #"Basic [A-Za-z0-9+/=_-]{12,}"#,
            #"sk-[A-Za-z0-9_-]{12,}"#,
            #"(?i)([?&](?:api[_-]?key|token|access[_-]?token|auth(?:orization)?)=)[^&\s]+"#,
            #"(?i)\b((?:api[_-]?key|token|access[_-]?token|auth(?:orization)?)=)[^&\s]+"#
        ]

        for pattern in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement(forSensitiveTokenPattern: pattern),
                options: .regularExpression
            )
        }

        return redacted
    }

    private func replacement(forSensitiveTokenPattern pattern: String) -> String {
        pattern.contains("=)") ? "$1<redacted>" : "<redacted>"
    }

    private func redactLocalPaths(in value: String) -> String {
        var redacted = value
        let patterns = [
            #"file:///Users/[^\s]+"#,
            #"/Users/[^\s]+"#
        ]

        for pattern in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "<local-path>",
                options: .regularExpression
            )
        }

        return redacted
    }

    private func append(_ line: String, to url: URL) throws {
        let data = Data(line.utf8)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private func rotateActiveLogIfNeeded(activeURL: URL) throws {
        guard fileSize(activeURL) >= maxFileBytes else {
            return
        }

        let rotatedName = "\(fileName).\(Int(Date().timeIntervalSince1970)).\(UUID().uuidString.prefix(8))"
        let rotatedURL = directoryURL.appending(path: rotatedName)
        try fileManager.moveItem(at: activeURL, to: rotatedURL)
    }

    private func pruneLogs() throws {
        let logFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ).filter { $0.lastPathComponent == fileName || $0.lastPathComponent.hasPrefix("\(fileName).") }
        pruneSizePassObserver?()
        let inventory = logFiles.map { url in
            LogFile(
                url: url,
                size: fileSize(url),
                modificationDate: (try? modificationDate(url)) ?? .distantPast
            )
        }

        var totalBytes = inventory.reduce(0) { partial, file in partial + file.size }
        for file in inventory.sorted(by: { $0.modificationDate < $1.modificationDate }) where totalBytes > maxTotalBytes {
            try? fileManager.removeItem(at: file.url)

            if !fileManager.fileExists(atPath: file.url.path(percentEncoded: false)) {
                totalBytes -= file.size
            }
        }
    }

    private struct LogFile {
        let url: URL
        let size: Int
        let modificationDate: Date
    }

    private func fileSize(_ url: URL) -> Int {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return 0
        }

        return fileSize
    }

    private func modificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }
}
