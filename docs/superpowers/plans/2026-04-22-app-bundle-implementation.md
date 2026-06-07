# 问.app Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a local double-clickable macOS app bundle at `dist/问.app` with the approved cream icon and a repeatable packaging command.

**Architecture:** Keep the existing Swift Package app intact and add a small packaging layer on top. The package will gain testable bundle-building utilities, while a packaging command/script will build the release executable, generate the icon set, write bundle metadata, and assemble the `.app`.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, FileManager, PropertyListSerialization, macOS `iconutil`, shell script automation, swift-testing

---

## File Structure

- `Sources/ClaudeLiteCore/Packaging/AppBundleConfig.swift`
  Bundle metadata and output-path rules.
- `Sources/ClaudeLiteCore/Packaging/AppBundleBuilder.swift`
  Creates the `.app` directory structure, writes `Info.plist`, and copies executable/icon files.
- `Sources/ClaudeLitePackager/main.swift`
  Small CLI entrypoint to assemble `dist/问.app`.
- `scripts/package-app.sh`
  Repeatable build command that builds the release app, generates the icon, and invokes the packager.
- `scripts/generate-icon.swift`
  Creates the approved cream “问” icon PNG set and converts it to `.icns`.
- `Tests/ClaudeLiteCoreTests/AppBundleBuilderTests.swift`
  Red-green coverage for bundle metadata and generated structure.

## Tasks

### Task 1: Add failing tests for bundle metadata

**Files:**
- Create: `Tests/ClaudeLiteCoreTests/AppBundleBuilderTests.swift`
- Create: `Sources/ClaudeLiteCore/Packaging/AppBundleConfig.swift`
- Create: `Sources/ClaudeLiteCore/Packaging/AppBundleBuilder.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppBundleBuilderTests`
Expected: FAIL because `AppBundleConfig` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
public struct AppBundleConfig {
    public static let `default` = AppBundleConfig(
        appName: "问",
        bundleIdentifier: "com.hadesz.wen",
        executableName: "问",
        iconFileName: "AppIcon.icns"
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppBundleBuilderTests`
Expected: PASS for the new metadata test.

### Task 2: Add failing tests for `.app` structure generation

**Files:**
- Modify: `Tests/ClaudeLiteCoreTests/AppBundleBuilderTests.swift`
- Modify: `Sources/ClaudeLiteCore/Packaging/AppBundleBuilder.swift`

- [ ] **Step 1: Write the failing test**

```swift
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

    #expect(FileManager.default.fileExists(atPath: bundleURL.appending(path: "Contents/Info.plist").path()))
    #expect(FileManager.default.fileExists(atPath: bundleURL.appending(path: "Contents/MacOS/问").path()))
    #expect(FileManager.default.fileExists(atPath: bundleURL.appending(path: "Contents/Resources/AppIcon.icns").path()))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppBundleBuilderTests/builderCreatesStandardAppStructure`
Expected: FAIL because the builder logic is missing.

- [ ] **Step 3: Write minimal implementation**

```swift
public final class AppBundleBuilder {
    public func build(...) throws -> URL {
        // create bundle directories
        // write plist
        // copy executable
        // copy icon
        // set executable permissions
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppBundleBuilderTests`
Expected: PASS for both metadata and structure tests.

### Task 3: Add the packager entrypoint

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClaudeLitePackager/main.swift`

- [ ] **Step 1: Add the packager executable target**

```swift
.executable(
    name: "ClaudeLitePackager",
    targets: ["ClaudeLitePackager"]
)
```

- [ ] **Step 2: Implement a CLI that assembles `dist/问.app`**

```swift
let builder = AppBundleBuilder()
let bundleURL = try builder.build(
    config: .default,
    executableURL: executableURL,
    iconURL: iconURL,
    outputDirectory: outputDirectory
)
print(bundleURL.path())
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: PASS with the new packager target included.

### Task 4: Add icon generation command

**Files:**
- Create: `scripts/generate-icon.swift`

- [ ] **Step 1: Implement icon drawing**

```swift
// draw cream rounded square
// draw centered “问”
// export PNGs into an .iconset directory
// run iconutil --convert icns ...
```

- [ ] **Step 2: Verify icon generation**

Run: `swift scripts/generate-icon.swift`
Expected: PASS and output `build-support/AppIcon.icns`.

### Task 5: Add one-command packaging

**Files:**
- Create: `scripts/package-app.sh`
- Modify: `README.md`

- [ ] **Step 1: Write the packaging command**

```bash
#!/bin/zsh
set -euo pipefail

swift build -c release --product ClaudeLiteMacApp
swift build -c release --product ClaudeLitePackager
swift scripts/generate-icon.swift
swift run -c release ClaudeLitePackager
```

- [ ] **Step 2: Document the command**

```markdown
- Build local app bundle: `./scripts/package-app.sh`
```

- [ ] **Step 3: Verify packaging command works**

Run: `./scripts/package-app.sh`
Expected: PASS and create `dist/问.app`.

### Task 6: Verify the final app bundle

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: PASS with all existing and new tests green.

- [ ] **Step 2: Rebuild the package**

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Re-run packaging**

Run: `./scripts/package-app.sh`
Expected: PASS and refresh `dist/问.app`.

- [ ] **Step 4: Launch the packaged app**

Run: `open dist/问.app`
Expected: The app opens as a normal macOS application with the custom “问” icon.
