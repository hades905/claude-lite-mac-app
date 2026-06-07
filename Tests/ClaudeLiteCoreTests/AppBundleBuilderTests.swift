import Foundation
import Testing
@testable import ClaudeLiteCore

struct AppBundleBuilderTests {
    @Test
    func bundleConfigUsesApprovedNames() {
        let config = AppBundleConfig.default

        #expect(config.appName == "问")
        #expect(config.bundleName == "问.app")
        #expect(config.executableName == "问")
        #expect(config.iconFileName == "AppIcon.icns")
    }

    @Test
    func builderCreatesStandardAppStructure() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let bundleURL = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output
        )

        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Info.plist").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/MacOS/问").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path(percentEncoded: false)))
    }

    @Test
    func builderCopiesBootstrapConfigurationIntoAppResources() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        let bootstrapDirectory = tempDir.appending(path: ".local", directoryHint: .isDirectory)
        let bootstrapConfiguration = bootstrapDirectory.appending(path: "tuzi-config.json")
        let json = """
        {
          "modelApiKey": "test-model-key",
          "userApiKey": "test-user-key",
          "defaultModel": "claude-opus-4-7",
          "baseURL": "https://api.tu-zi.com"
        }
        """
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)
        try FileManager.default.createDirectory(at: bootstrapDirectory, withIntermediateDirectories: true)
        try json.write(to: bootstrapConfiguration, atomically: true, encoding: .utf8)

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let bundleURL = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output,
            bootstrapConfigurationURL: bootstrapConfiguration
        )

        let copiedConfiguration = bundleURL.appendingPathComponent("Contents/Resources/.local/tuzi-config.json")

        #expect(FileManager.default.fileExists(atPath: copiedConfiguration.path(percentEncoded: false)))
        #expect(try String(contentsOf: copiedConfiguration, encoding: .utf8) == json)
    }

    @Test
    func builderCopiesBootstrapConfigurationIntoResourceBundles() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        let siblingBundle = tempDir.appending(path: "ClaudeLiteMacApp_ClaudeLiteCore.bundle", directoryHint: .isDirectory)
        let bootstrapConfiguration = tempDir.appending(path: "tuzi-config.json")
        let json = """
        {
          "modelApiKey": "test-model-key",
          "userApiKey": "test-user-key",
          "defaultModel": "claude-opus-4-7",
          "baseURL": "https://api.tu-zi.com"
        }
        """
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)
        try FileManager.default.createDirectory(at: siblingBundle, withIntermediateDirectories: true)
        try Data("rendering-assets".utf8).write(to: siblingBundle.appending(path: "manifest.txt"))
        try json.write(to: bootstrapConfiguration, atomically: true, encoding: .utf8)

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let bundleURL = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output,
            bootstrapConfigurationURL: bootstrapConfiguration
        )

        let resourcesBundleConfiguration = bundleURL
            .appendingPathComponent("Contents/Resources/ClaudeLiteMacApp_ClaudeLiteCore.bundle/.local/tuzi-config.json")
        let appRootBundleConfiguration = bundleURL
            .appendingPathComponent("ClaudeLiteMacApp_ClaudeLiteCore.bundle/.local/tuzi-config.json")

        #expect(try String(contentsOf: resourcesBundleConfiguration, encoding: .utf8) == json)
        #expect(try String(contentsOf: appRootBundleConfiguration, encoding: .utf8) == json)
    }

    @Test
    func builderReplacesExistingBundleAtNonASCIPath() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let firstBuild = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output
        )

        try Data("updated".utf8).write(to: executable)
        let secondBuild = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output
        )

        let rebuiltExecutable = secondBuild.appendingPathComponent("Contents/MacOS/问")
        let rebuiltData = try Data(contentsOf: rebuiltExecutable)

        #expect(firstBuild == secondBuild)
        #expect(String(decoding: rebuiltData, as: UTF8.self) == "updated")
    }

    @Test
    func builderCopiesSiblingResourceBundlesIntoAppResources() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        let siblingBundle = tempDir.appending(path: "ClaudeLiteCore_ClaudeLiteCore.bundle", directoryHint: .isDirectory)
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)
        try FileManager.default.createDirectory(at: siblingBundle, withIntermediateDirectories: true)
        try Data("rendering-assets".utf8).write(to: siblingBundle.appending(path: "manifest.txt"))

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let bundleURL = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output
        )

        let copiedBundle = bundleURL.appendingPathComponent("Contents/Resources/ClaudeLiteCore_ClaudeLiteCore.bundle")
        let copiedManifest = copiedBundle.appendingPathComponent("manifest.txt")

        #expect(FileManager.default.fileExists(atPath: copiedBundle.path(percentEncoded: false)))
        #expect(String(decoding: try Data(contentsOf: copiedManifest), as: UTF8.self) == "rendering-assets")
    }

    @Test
    func builderCopiesSiblingResourceBundlesToSwiftPMExecutableLookupLocation() throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let executable = tempDir.appending(path: "ClaudeLiteMacApp")
        let icon = tempDir.appending(path: "AppIcon.icns")
        let siblingBundle = tempDir.appending(path: "ClaudeLiteMacApp_ClaudeLiteCore.bundle", directoryHint: .isDirectory)
        try Data("bin".utf8).write(to: executable)
        try Data("icon".utf8).write(to: icon)
        try FileManager.default.createDirectory(at: siblingBundle, withIntermediateDirectories: true)
        try Data("rendering-assets".utf8).write(to: siblingBundle.appending(path: "manifest.txt"))

        let output = tempDir.appending(path: "dist")
        let builder = AppBundleBuilder(fileManager: .default)
        let bundleURL = try builder.build(
            config: .default,
            executableURL: executable,
            iconURL: icon,
            outputDirectory: output
        )

        let copiedBundle = bundleURL.appendingPathComponent("ClaudeLiteMacApp_ClaudeLiteCore.bundle")
        let copiedManifest = copiedBundle.appendingPathComponent("manifest.txt")

        #expect(FileManager.default.fileExists(atPath: copiedBundle.path(percentEncoded: false)))
        #expect(String(decoding: try Data(contentsOf: copiedManifest), as: UTF8.self) == "rendering-assets")
    }
}
