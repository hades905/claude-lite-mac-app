import Foundation
import Darwin

public struct LiveServiceContainer: ClaudeLiteServiceContainer {
    public let bootstrapLoader: BootstrapConfigurationLoading
    public let secureStore: SecureStoring
    public let sessionStore: SessionStoring
    public let modelService: ModelServing
    public let connectionService: ConnectionServing
    public let chatService: ChatServing
    public let logger: AppLogging

    public init(
        bootstrapLoader: BootstrapConfigurationLoading,
        secureStore: SecureStoring,
        sessionStore: SessionStoring,
        modelService: ModelServing,
        connectionService: ConnectionServing,
        chatService: ChatServing,
        logger: AppLogging
    ) {
        self.bootstrapLoader = bootstrapLoader
        self.secureStore = secureStore
        self.sessionStore = sessionStore
        self.modelService = modelService
        self.connectionService = connectionService
        self.chatService = chatService
        self.logger = logger
    }

    public static func live(
        appSupportURL: URL? = nil,
        storageLimitBytes: Int = AppSupportStoragePruner.defaultMaxTotalBytes
    ) -> LiveServiceContainer {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let appSupport = appSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "ClaudeLiteMacApp", directoryHint: .isDirectory)
        let logger = RotatingAppLogger(directoryURL: appSupport.appending(path: "Logs", directoryHint: .isDirectory))
        logStoragePrune(
            directoryURL: appSupport,
            maxTotalBytes: storageLimitBytes,
            logger: logger
        )
        let sessionStore = PersistentSessionStore(fileURL: appSupport.appending(path: "session.json"))
        let mainBundle = Bundle.main
        let bootstrapLoader = LocalBootstrapConfigurationLoader(
            searchRoots: defaultBootstrapSearchRoots(
                currentDirectory: currentDirectory,
                bundleURL: mainBundle.bundleURL,
                resourceURL: mainBundle.resourceURL,
                executableURL: currentExecutableURL(),
                moduleResourceURL: Bundle.module.resourceURL,
                appSupportURL: appSupport
            )
        )
        let secureStore = NoopSecureStore()
        let apiClient = TuziAPIClient()
        let modelService = LiveModelService(apiClient: apiClient)
        let connectionService = LiveConnectionService(apiClient: apiClient)
        let chatService = LiveChatService(apiClient: apiClient)

        return LiveServiceContainer(
            bootstrapLoader: bootstrapLoader,
            secureStore: secureStore,
            sessionStore: sessionStore,
            modelService: modelService,
            connectionService: connectionService,
            chatService: chatService,
            logger: logger
        )
    }

    private static func logStoragePrune(
        directoryURL: URL,
        maxTotalBytes: Int,
        logger: AppLogging
    ) {
        do {
            let result = try AppSupportStoragePruner.prune(
                directoryURL: directoryURL,
                maxTotalBytes: maxTotalBytes
            )
            try? logger.record(
                event: "storage_prune_completed",
                metadata: [
                    "beforeBytes": "\(result.beforeBytes)",
                    "afterBytes": "\(result.afterBytes)",
                    "removedBytes": "\(result.removedBytes)",
                    "removedFileCount": "\(result.removedFileCount)"
                ]
            )
        } catch {
            try? logger.record(
                event: "storage_prune_failed",
                metadata: ["error": String(describing: type(of: error))]
            )
        }
    }

    static func defaultBootstrapSearchRoots(
        currentDirectory: URL,
        bundleURL: URL,
        resourceURL: URL? = nil,
        executableURL: URL? = nil,
        moduleResourceURL: URL? = nil,
        appSupportURL: URL? = nil
    ) -> [URL] {
        if let appResourceURL = packagedAppResourceURL(
            bundleURL: bundleURL,
            resourceURL: resourceURL,
            executableURL: executableURL,
            moduleResourceURL: moduleResourceURL
        ) {
            if let appSupportURL {
                return [appSupportURL, appResourceURL]
            }

            return [appResourceURL]
        }

        var roots: [URL] = [currentDirectory]
        let bundleParent = bundleURL.deletingLastPathComponent()
        let bundleGrandparent = bundleParent.deletingLastPathComponent()

        for candidate in [bundleParent, bundleGrandparent] where !roots.contains(candidate) {
            roots.append(candidate)
        }

        return roots
    }

    private static func packagedAppResourceURL(
        bundleURL: URL,
        resourceURL: URL?,
        executableURL: URL?,
        moduleResourceURL: URL?
    ) -> URL? {
        if let moduleResourceURL, isInsideAppBundle(moduleResourceURL) {
            return moduleResourceURL
        }

        if let resourceURL, isInsideAppBundle(resourceURL) {
            return resourceURL
        }

        if isInsideAppBundle(bundleURL), let resourceURL {
            return resourceURL
        }

        guard let executableURL else {
            return nil
        }

        return resourceURLFromPackagedExecutable(executableURL)
    }

    private static func resourceURLFromPackagedExecutable(_ executableURL: URL) -> URL? {
        let components = executableURL.standardizedFileURL.pathComponents
        guard
            let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }),
            components.indices.contains(appIndex + 2),
            components[appIndex + 1] == "Contents",
            components[appIndex + 2] == "MacOS"
        else {
            return nil
        }

        let appPath = NSString.path(withComponents: Array(components[...appIndex]))
        return URL(fileURLWithPath: appPath, isDirectory: true)
            .appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    private static func isInsideAppBundle(_ url: URL) -> Bool {
        url.pathComponents.contains { $0.hasSuffix(".app") }
    }

    private static func currentExecutableURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return nil
        }

        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<endIndex].map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

public struct LiveModelService: ModelServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func fetchClaudeModels(apiKey: String) async throws -> [ClaudeModel] {
        ModelCatalog.coreClaudeModels(from: try await apiClient.fetchModels(apiKey: apiKey))
    }
}

public struct LiveConnectionService: ConnectionServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func checkConnection(apiKey: String?) async -> ConnectionStatus {
        guard let apiKey, !apiKey.isEmpty else {
            return .authFailed
        }

        do {
            _ = try await apiClient.fetchModels(apiKey: apiKey)
            return .connected
        } catch TuziAPIError.unauthorized {
            return .authFailed
        } catch {
            return .disconnected
        }
    }
}

public struct LiveChatService: ChatServing {
    private let apiClient: TuziAPIClient

    public init(apiClient: TuziAPIClient) {
        self.apiClient = apiClient
    }

    public func sendMessage(
        conversation: [ChatMessage],
        modelID: String,
        apiKey: String
    ) async throws -> ChatMessage {
        try await apiClient.sendMessage(conversation: conversation, modelID: modelID, apiKey: apiKey)
    }
}
