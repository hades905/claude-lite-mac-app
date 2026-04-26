import Foundation

public final class NoopSecureStore: SecureStoring {
    public init() {}

    public func readModelAPIKey() throws -> String? {
        nil
    }

    public func saveModelAPIKey(_ apiKey: String) throws {}

    public func readUserAPIKey() throws -> String? {
        nil
    }

    public func saveUserAPIKey(_ apiKey: String) throws {}
}

public final class KeychainSecureStore: SecureStoring {
    private let fallbackStore = NoopSecureStore()

    public init(service: String) {}

    public func readModelAPIKey() throws -> String? {
        try fallbackStore.readModelAPIKey()
    }

    public func saveModelAPIKey(_ apiKey: String) throws {
        try fallbackStore.saveModelAPIKey(apiKey)
    }

    public func readUserAPIKey() throws -> String? {
        try fallbackStore.readUserAPIKey()
    }

    public func saveUserAPIKey(_ apiKey: String) throws {
        try fallbackStore.saveUserAPIKey(apiKey)
    }
}

public enum SecureStoreError: Error {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case decodeFailed
}
