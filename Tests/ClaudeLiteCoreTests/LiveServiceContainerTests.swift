import Foundation
import Testing
@testable import ClaudeLiteCore

struct LiveServiceContainerTests {
    @Test
    func liveStartupLogsStoragePruneResultWithoutPaths() throws {
        let appSupportURL = try TestSupport.makeTemporaryDirectory()
        let protectedSessionURL = appSupportURL.appending(path: "session.json")
        let oldCacheURL = appSupportURL.appending(path: "Cache/old-render.bin")

        try writeFile(protectedSessionURL, byteCount: 4_000, age: 100)
        try writeFile(oldCacheURL, byteCount: 40_000, age: 90)

        _ = LiveServiceContainer.live(appSupportURL: appSupportURL, storageLimitBytes: 12_000)

        let logURL = appSupportURL.appending(path: "Logs/claude-lite.log")
        let log = try String(contentsOf: logURL, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: protectedSessionURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: oldCacheURL.path(percentEncoded: false)))
        #expect(log.contains("event=storage_prune_completed"))
        #expect(log.contains("beforeBytes="))
        #expect(log.contains("afterBytes="))
        #expect(log.contains("removedBytes="))
        #expect(log.contains("removedFileCount=1"))
        #expect(!log.contains("old-render.bin"))
        #expect(!log.contains(appSupportURL.path(percentEncoded: false)))
    }

    @Test
    func packagedAppBootstrapSearchRootsUseBundledResourcesOnly() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let appSupportURL = URL(fileURLWithPath: "/Users/hadesz/Library/Application Support/ClaudeLiteMacApp", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: appBundleURL,
            resourceURL: resourcesURL,
            appSupportURL: appSupportURL
        )

        #expect(roots == [appSupportURL, resourcesURL])
    }

    @Test
    func packagedExecutableBootstrapSearchRootsUseBundledResourcesOnly() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/问")
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let appSupportURL = URL(fileURLWithPath: "/Users/hadesz/Library/Application Support/ClaudeLiteMacApp", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: executableURL,
            resourceURL: resourcesURL,
            appSupportURL: appSupportURL
        )

        #expect(roots == [appSupportURL, resourcesURL])
    }

    @Test
    func packagedExecutablePathFindsResourcesWhenBundleMetadataIsNotUseful() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let executableURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/MacOS/问")
        let unrelatedBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/MacOS")
        let resourcesURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/Resources", isDirectory: true)
        let appSupportURL = URL(fileURLWithPath: "/Users/hadesz/Library/Application Support/ClaudeLiteMacApp", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: unrelatedBundleURL,
            resourceURL: nil,
            executableURL: executableURL,
            appSupportURL: appSupportURL
        )

        #expect(roots == [appSupportURL, resourcesURL])
    }

    @Test
    func packagedModuleResourceBundleIsPreferredForBootstrapSearch() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let appResourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let moduleResourcesURL = appResourcesURL.appendingPathComponent("ClaudeLiteMacApp_ClaudeLiteCore.bundle", isDirectory: true)
        let appSupportURL = URL(fileURLWithPath: "/Users/hadesz/Library/Application Support/ClaudeLiteMacApp", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: appBundleURL,
            resourceURL: appResourcesURL,
            moduleResourceURL: moduleResourcesURL,
            appSupportURL: appSupportURL
        )

        #expect(roots == [appSupportURL, moduleResourcesURL])
    }

    @Test
    func swiftRunBootstrapSearchRootsStillIncludeCurrentDirectory() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let executableURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/.build/arm64-apple-macosx/release/ClaudeLiteMacApp")

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: executableURL
        )

        #expect(roots.first == currentDirectory)
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
}
