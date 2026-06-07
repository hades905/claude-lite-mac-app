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
    func packageScriptCleansBuildCachesAfterPackaging() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageScriptURL = projectRoot.appendingPathComponent("scripts/package-app.sh")

        let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

        #expect(packageScript.contains("cleanup_build_cache()"))
        #expect(packageScript.contains("trap cleanup_build_cache EXIT"))
        #expect(packageScript.contains("rm -rf \"$ROOT_DIR/.build\""))
        #expect(packageScript.contains("rm -rf \"$ROOT_DIR/.swiftpm\""))
        #expect(packageScript.contains("rm -rf \"$ROOT_DIR/.build-support\""))
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

    @Test
    func releaseVerificationScriptRunsOfflineSmokeAndSafetyGates() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = projectRoot.appendingPathComponent("scripts/verify-release.sh")

        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("swift run ClaudeLiteSmoke"))
        #expect(script.contains("swift test"))
        #expect(script.contains("scripts/package-app.sh"))
        #expect(script.contains("MAX_APP_BYTES=$((100 * 1024 * 1024))"))
        #expect(script.contains("tuzi-config.json"))
        #expect(script.contains("rg --pcre2"))
        #expect(script.contains("sk-[A-Za-z0-9_-]{12,}"))
        #expect(script.contains("cleanup_build_cache()"))
        #expect(script.contains("trap cleanup_build_cache EXIT"))
        #expect(script.contains("rm -rf \"$ROOT_DIR/.build\""))
        #expect(script.contains("MAX_SMOKE_START_MS=5000"))
        #expect(script.contains("MAX_SMOKE_SEND_MS=5000"))
        #expect(script.contains("MAX_SMOKE_RSS_MB=100"))
        #expect(script.contains("assert_metric_under_limit"))
        #expect(script.contains("SMOKE_OUTPUT=\"$(swift run ClaudeLiteSmoke)\""))
        #expect(script.contains("start_ms"))
        #expect(script.contains("send_ms"))
        #expect(script.contains("rss_mb"))
    }
}
