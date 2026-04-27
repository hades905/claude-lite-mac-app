import Foundation
import Testing
@testable import ClaudeLiteCore

struct BootstrapConfigurationTests {
    @Test
    func loadsBootstrapConfigurationFromJSON() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "tuzi-config.json")
        let json = """
        {
          "modelApiKey": "model-key",
          "userApiKey": "user-key",
          "defaultModel": "claude-opus-4-7",
          "baseURL": "https://api.tu-zi.com"
        }
        """

        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try BootstrapConfiguration.load(from: fileURL)

        #expect(configuration.modelAPIKey == "model-key")
        #expect(configuration.userAPIKey == "user-key")
        #expect(configuration.defaultModel == "claude-opus-4-7")
        #expect(configuration.baseURL == URL(string: "https://api.tu-zi.com"))
    }

    @Test
    func localBootstrapLoaderReadsConfigurationUnderNonASCIIRoot() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
            .appending(path: "问.app", directoryHint: .isDirectory)
        let localDirectory = directory.appending(path: ".local", directoryHint: .isDirectory)
        let fileURL = localDirectory.appending(path: "tuzi-config.json")
        let json = """
        {
          "modelApiKey": "model-key",
          "userApiKey": "user-key",
          "defaultModel": "claude-opus-4-7",
          "baseURL": "https://api.tu-zi.com"
        }
        """
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let loader = LocalBootstrapConfigurationLoader(searchRoots: [directory])
        let configuration = try loader.loadBootstrapConfiguration()

        #expect(configuration?.modelAPIKey == "model-key")
        #expect(configuration?.defaultModel == "claude-opus-4-7")
    }
}
