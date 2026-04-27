import Foundation
import Testing
@testable import ClaudeLiteCore

struct LiveServiceContainerTests {
    @Test
    func packagedAppBootstrapSearchRootsUseBundledResourcesOnly() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: appBundleURL,
            resourceURL: resourcesURL
        )

        #expect(roots == [resourcesURL])
    }

    @Test
    func packagedExecutableBootstrapSearchRootsUseBundledResourcesOnly() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/问")
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: executableURL,
            resourceURL: resourcesURL
        )

        #expect(roots == [resourcesURL])
    }

    @Test
    func packagedExecutablePathFindsResourcesWhenBundleMetadataIsNotUseful() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let executableURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/MacOS/问")
        let unrelatedBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/MacOS")
        let resourcesURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app/Contents/Resources", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: unrelatedBundleURL,
            resourceURL: nil,
            executableURL: executableURL
        )

        #expect(roots == [resourcesURL])
    }

    @Test
    func packagedModuleResourceBundleIsPreferredForBootstrapSearch() {
        let currentDirectory = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app")
        let appBundleURL = URL(fileURLWithPath: "/Users/hadesz/Desktop/claude-lite-mac-app/dist/问.app")
        let appResourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let moduleResourcesURL = appResourcesURL.appendingPathComponent("ClaudeLiteMacApp_ClaudeLiteCore.bundle", isDirectory: true)

        let roots = LiveServiceContainer.defaultBootstrapSearchRoots(
            currentDirectory: currentDirectory,
            bundleURL: appBundleURL,
            resourceURL: appResourcesURL,
            moduleResourceURL: moduleResourcesURL
        )

        #expect(roots == [moduleResourcesURL])
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
}
