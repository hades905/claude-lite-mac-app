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
        #expect(launcher.contains("SOURCE_CONFIG=\"$PROJECT_DIR/.local/tuzi-config.json\""))
        #expect(launcher.contains("APP_SUPPORT_CONFIG=\"$HOME/Library/Application Support/ClaudeLiteMacApp/.local/tuzi-config.json\""))
        #expect(launcher.contains("chmod 600 \"$APP_SUPPORT_CONFIG\""))
        #expect(!launcher.contains("swift run --package-path \"$PROJECT_DIR\" ClaudeLiteMacApp"))
    }

    @Test
    func packageScriptReusesPersistentIconAsset() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageScriptURL = projectRoot.appendingPathComponent("scripts/package-app.sh")
        let persistentIconURL = projectRoot.appendingPathComponent("Assets/AppIcon.icns")

        let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: persistentIconURL.path))
        #expect(packageScript.contains("ICON_PATH=\"$ROOT_DIR/Assets/AppIcon.icns\""))
        #expect(packageScript.contains("if [[ ! -f \"$ICON_PATH\" ]]; then"))
        #expect(!packageScript.contains("swift scripts/generate-icon.swift\n\nPACKAGER_ARGS"))
    }

    @Test
    func packageScriptDoesNotBundleLocalAPIKeysByDefault() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageScriptURL = projectRoot.appendingPathComponent("scripts/package-app.sh")

        let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

        #expect(!packageScript.contains(".local/tuzi-config.json"))
        #expect(!packageScript.contains("--bootstrap-config"))
    }
}
