import Foundation
import Testing

struct LauncherCommandTests {
    @Test
    func latestLauncherRunsAppFromSourcePackage() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let launcherURL = projectRoot.appendingPathComponent("Claude Lite Latest.command")

        let launcher = try String(contentsOf: launcherURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: launcherURL.path))
        #expect(launcher.contains("PROJECT_DIR="))
        #expect(launcher.contains("Package.swift"))
        #expect(launcher.contains("cd \"$PROJECT_DIR\""))
        #expect(launcher.contains("\"$PROJECT_DIR/scripts/package-app.sh\""))
        #expect(launcher.contains("find \"$PROJECT_DIR/dist\" -maxdepth 1 -name '*.app'"))
        #expect(launcher.contains("open \"$APP_PATH\""))
        #expect(!launcher.contains("swift run --package-path \"$PROJECT_DIR\" ClaudeLiteMacApp"))
    }
}
