import Foundation

public struct AppBundleConfig: Equatable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let executableName: String
    public let iconFileName: String

    public init(
        appName: String,
        bundleIdentifier: String,
        executableName: String,
        iconFileName: String
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.iconFileName = iconFileName
    }

    public var bundleName: String {
        "\(appName).app"
    }

    public static let `default` = AppBundleConfig(
        appName: "问",
        bundleIdentifier: "com.hadesz.wen",
        executableName: "问",
        iconFileName: "AppIcon.icns"
    )
}
