import Foundation

public final class AppBundleBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func build(
        config: AppBundleConfig,
        executableURL: URL,
        iconURL: URL,
        outputDirectory: URL
    ) throws -> URL {
        let bundleURL = fileURL(appending: config.bundleName, to: outputDirectory, isDirectory: true)
        let contentsURL = fileURL(appending: "Contents", to: bundleURL, isDirectory: true)
        let macOSURL = fileURL(appending: "MacOS", to: contentsURL, isDirectory: true)
        let resourcesURL = fileURL(appending: "Resources", to: contentsURL, isDirectory: true)
        let finalExecutableURL = fileURL(appending: config.executableName, to: macOSURL, isDirectory: false)
        let finalIconURL = fileURL(appending: config.iconFileName, to: resourcesURL, isDirectory: false)
        let plistURL = fileURL(appending: "Info.plist", to: contentsURL, isDirectory: false)

        if fileManager.fileExists(atPath: bundleURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: bundleURL)
        }

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        try fileManager.copyItem(at: executableURL, to: finalExecutableURL)
        try fileManager.copyItem(at: iconURL, to: finalIconURL)
        try copySiblingBundles(near: executableURL, to: resourcesURL, appBundleURL: bundleURL)
        try writePlist(config: config, to: plistURL)
        try setExecutablePermissions(at: finalExecutableURL)

        return bundleURL
    }

    private func writePlist(config: AppBundleConfig, to plistURL: URL) throws {
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": config.executableName,
            "CFBundleIconFile": config.iconFileName,
            "CFBundleIdentifier": config.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": config.appName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    private func setExecutablePermissions(at url: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755
        ]
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path(percentEncoded: false))
    }

    private func copySiblingBundles(near executableURL: URL, to resourcesURL: URL, appBundleURL: URL) throws {
        let buildDirectory = executableURL.deletingLastPathComponent()
        let siblingURLs = try fileManager.contentsOfDirectory(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        )

        for siblingURL in siblingURLs where siblingURL.pathExtension == "bundle" {
            let resourcesDestinationURL = fileURL(
                appending: siblingURL.lastPathComponent,
                to: resourcesURL,
                isDirectory: true
            )
            let appRootDestinationURL = fileURL(
                appending: siblingURL.lastPathComponent,
                to: appBundleURL,
                isDirectory: true
            )
            try fileManager.copyItem(at: siblingURL, to: resourcesDestinationURL)
            try fileManager.copyItem(at: siblingURL, to: appRootDestinationURL)
        }
    }

    private func fileURL(appending component: String, to baseURL: URL, isDirectory: Bool) -> URL {
        let path = (baseURL.path(percentEncoded: false) as NSString).appendingPathComponent(component)
        return URL(fileURLWithPath: path, isDirectory: isDirectory)
    }
}
