# SwiftStreamingMarkdown macOS Spike

Date: 2026-06-13

## Purpose

Validate whether Microsoft's `SwiftStreamingMarkdown` can be introduced into the Claude Lite macOS app without breaking the existing goals: lightweight startup, low memory, safe local rendering, complete Markdown behavior, and a package footprint well below 100 MB.

## Probe 1: Direct Upstream Dependency

Temporary package:

```swift
.package(url: "https://github.com/microsoft/SwiftStreamingMarkdown.git", branch: "main")
```

Result: failed during SwiftPM package validation.

Key failure:

```text
the library 'SwiftStreamingMarkdown' requires macos 10.13,
but depends on the product 'Equatable' which requires macos 10.15

the library 'SwiftStreamingMarkdown' requires macos 10.13,
but depends on the product 'HighlightSwift' which requires macos 13.0

the library 'SwiftStreamingMarkdown' requires macos 10.13,
but depends on the product 'iosMath' which requires macos 11.0
```

Interpretation: the upstream package is iOS-first and does not currently declare a coherent macOS platform for this app.

## Probe 2: Local Manifest Patch

Temporary local-only patch:

```swift
platforms: [.iOS(.v16), .macOS(.v14)]
```

Result: package validation advanced, then failed in `HighlightSwift`.

Key failure:

```text
external macro implementation type 'SwiftUIMacros.EntryMacro' could not be found
external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found
```

Interpretation: `HighlightSwift` needs a SwiftPM-compatible macOS patch or a newer compatible revision before the dependency chain can compile reliably.

## Probe 3: Local HighlightSwift Patch

Temporary local-only patch:

- Replaced `@Entry` with a traditional `EnvironmentKey`.
- Removed the `#Preview` block from the command-line package build path.

Result: the build advanced into `SwiftStreamingMarkdown`, then failed on UIKit imports.

Key failure:

```text
Sources/MarkdownText/Citation/InlineAttachmentData.swift: no such module 'UIKit'
```

Follow-up scan found UIKit coupling across the package:

- `UIFont`
- `UIColor`
- `UIImage`
- `UIViewRepresentable`
- `UITextView`
- `UIPasteboard`
- `UIApplication`
- `UIMenu`
- `UIAction`

Interpretation: current upstream cannot be used directly in a native macOS Swift Package app. A real integration needs upstream macOS support or a compatibility fork that ports UIKit-backed pieces to AppKit/SwiftUI equivalents.

## Decision

Do not add `SwiftStreamingMarkdown` to `Package.swift` yet.

The main app already has a safe renderer selection boundary. Keep that boundary and continue with a separate compatibility fork/spike until the dependency can compile standalone for macOS 14.

## Next Step

Create a local compatibility spike outside the main app:

1. Add macOS platform declaration.
2. Patch or update `HighlightSwift`.
3. Gate UIKit-only citation/context-menu/paragraph UIKit code behind iOS checks or port it to AppKit.
4. Build standalone.
5. Only after standalone success, measure app bundle size and runtime impact inside Claude Lite.
