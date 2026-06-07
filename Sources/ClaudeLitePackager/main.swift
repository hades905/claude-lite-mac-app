import Foundation
import ClaudeLiteCore

enum PackagerError: Error {
    case missingArgument(String)
}

@main
struct ClaudeLitePackager {
    static func main() throws {
        let arguments = CommandLine.arguments
        let executablePath = try value(for: "--executable", in: arguments)
        let iconPath = try value(for: "--icon", in: arguments)
        let outputPath = try value(for: "--output-dir", in: arguments)
        let bootstrapConfigurationPath = try optionalValue(for: "--bootstrap-config", in: arguments)

        let builder = AppBundleBuilder()
        let bundleURL = try builder.build(
            config: .default,
            executableURL: URL(fileURLWithPath: executablePath),
            iconURL: URL(fileURLWithPath: iconPath),
            outputDirectory: URL(fileURLWithPath: outputPath, isDirectory: true),
            bootstrapConfigurationURL: bootstrapConfigurationPath.map(URL.init(fileURLWithPath:))
        )

        print(bundleURL.path(percentEncoded: false))
    }

    private static func value(for flag: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw PackagerError.missingArgument(flag)
        }

        return arguments[index + 1]
    }

    private static func optionalValue(for flag: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        guard arguments.indices.contains(index + 1) else {
            throw PackagerError.missingArgument(flag)
        }

        return arguments[index + 1]
    }
}
