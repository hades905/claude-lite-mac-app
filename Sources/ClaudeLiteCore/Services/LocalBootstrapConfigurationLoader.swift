import Foundation

public struct LocalBootstrapConfigurationLoader: BootstrapConfigurationLoading {
    private let searchRoots: [URL]

    public init(searchRoots: [URL]) {
        self.searchRoots = searchRoots
    }

    public func loadBootstrapConfiguration() throws -> BootstrapConfiguration? {
        for root in searchRoots {
            let fileURL = root.appending(path: ".local/tuzi-config.json")
            if FileManager.default.fileExists(atPath: fileURL.path()) {
                return try BootstrapConfiguration.load(from: fileURL)
            }
        }

        return nil
    }
}
