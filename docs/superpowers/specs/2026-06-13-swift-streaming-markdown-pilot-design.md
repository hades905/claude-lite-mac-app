# SwiftStreamingMarkdown Pilot Design

## Context

Claude Lite currently renders Markdown in a `WKWebView` using bundled local copies of `marked` and MathJax. The existing path is already covered by tests for headings, lists, tables, fenced code, LaTeX, unsafe HTML stripping, remote image blocking, auto height updates, and unclipped long answers. It also keeps rendering resources offline and avoids loading user content from the network.

Microsoft's `SwiftStreamingMarkdown` is a new MIT-licensed SwiftUI package focused on streaming Markdown for chat and LLM interfaces. Its current public README describes support for a CommonMark/GitHub-style core subset, LaTeX, theming, and event tracking, with a release around v0.1.0. The README also lists unsupported or incomplete areas such as Markdown images, task lists, footnotes, and Mermaid. The package is expected to add about 3 MB to the app download size.

A macOS dependency probe on June 13, 2026 found that the upstream package cannot be added directly to this macOS app yet. The upstream package manifest declares only iOS as a supported platform, while SwiftPM reports the library as requiring macOS 10.13 and its dependencies require higher macOS versions: `Equatable` requires macOS 10.15, `HighlightSwift` requires macOS 13.0, and `iosMath` requires macOS 11.0. The direct probe failed before compiling app code.

A second local-only probe patched `SwiftStreamingMarkdown` to declare `.macOS(.v14)` and patched `HighlightSwift` to avoid SwiftUI package macro failures from `@Entry` and `#Preview`. That probe advanced further, but then failed inside `SwiftStreamingMarkdown` because the library imports UIKit and uses many UIKit-only types, including `UIFont`, `UIColor`, `UIImage`, `UIViewRepresentable`, `UITextView`, `UIPasteboard`, `UIApplication`, `UIMenu`, and `UIAction`. This means a real macOS integration needs more than a package manifest tweak. It requires either upstream macOS support or a maintained compatibility fork that ports UIKit-backed rendering pieces to AppKit/SwiftUI equivalents.

Because the app goal prioritizes low memory, fast startup, privacy, complete Markdown behavior, and a permanent 100 MB size ceiling, this should be treated as a measured pilot rather than a full renderer replacement.

## Goals

- Improve the experience for actively arriving assistant replies by reducing repeated full-document WebView reloads and making text growth feel smoother.
- Preserve the current stable renderer for completed messages and unsupported Markdown cases.
- Keep all rendering offline and prevent remote image, script, file URL, and unsafe HTML execution regressions.
- Measure real impact before expanding the pilot: app size, launch/offline smoke memory, render latency, scroll smoothness, and Markdown feature coverage.
- Keep a simple rollback path through a single renderer selection boundary.

## Non-Goals

- Do not replace the current `WKWebView` renderer in one step.
- Do not remove the existing `marked` or MathJax assets during the pilot.
- Do not enable remote image loading or raw HTML execution.
- Do not make `SwiftStreamingMarkdown` the default until feature and safety parity is proven.
- Do not call live paid models for validation; use offline smoke and deterministic render fixtures.

## Recommended Approach

Add an experimental renderer adapter behind a local selection boundary.

The default renderer remains the current `MarkdownMessageView` WebView path. A new experimental path may use `SwiftStreamingMarkdown` only for the latest assistant message while it is pending or streaming. After the assistant reply finishes, the message should be rendered by the existing stable renderer unless the pilot has proven parity for that message's Markdown features.

This isolates the main expected benefit, smoother incremental assistant text, while limiting risk to the smallest visible surface.

## Renderer Selection

Introduce a small internal decision point, for example `MarkdownRendererMode`:

- `stableWebView`: current behavior and the default.
- `streamingExperimental`: only eligible for pending assistant replies when the content is considered safe for the experimental subset.

The selection should be local, testable, and easy to disable. It should not require changing conversation storage, message models, API clients, or package scripts beyond the optional dependency wiring.

Experimental rendering should fall back to `stableWebView` when content includes:

- Markdown image syntax or restored image attachment chips.
- Task lists.
- Footnotes.
- Mermaid fences.
- Raw HTML blocks or inline HTML.
- Any feature the pilot cannot prove equivalent in tests.

## Safety Requirements

The pilot must keep the existing security posture:

- No remote image fetching.
- No JavaScript execution from message content.
- No local file path exposure.
- No conversation text or API key in diagnostics.
- No persistent WebKit-style website storage for experimental content.
- No logging of raw Markdown content or rendered output.

Any analytics or event tracking hooks offered by `SwiftStreamingMarkdown` must be disabled or wired only to existing safe diagnostics counters. Diagnostics may record counts, renderer mode, duration, and fallback reason, but not user text.

## Compatibility Matrix

The first implementation plan must include deterministic fixtures for:

- Headings, paragraphs, bold, italic, inline code.
- Bulleted and numbered lists.
- Tables.
- Fenced code blocks.
- Block quotes.
- Inline and display LaTeX.
- Unsafe HTML and script-like input.
- Remote image Markdown.
- Task list syntax.
- Footnote syntax.
- Mermaid fenced block.
- Chinese and mixed-language Markdown.

For each fixture, record whether the experimental renderer is allowed or must fall back. A fixture that falls back is acceptable during the pilot. A fixture that renders experimentally must match the stable renderer's visible meaning and safety rules.

## Measurement Plan

Add lightweight, non-secret diagnostics around rendering:

- Renderer selected: stable or experimental.
- Fallback reason as a fixed enum.
- Markdown length bucket, not raw text.
- Render duration bucket.
- Height update count.

Validation gates:

- `swift test --filter Markdown`
- `swift test --filter ChatViewModelTests`
- `./scripts/verify-release.sh`
- App bundle size comparison before and after adding the dependency.
- Offline smoke must keep the default model at `claude-opus-4-6`.
- Secret scan and bundled config checks must remain clean.

The pilot should be rejected or kept disabled by default if the app size increase is larger than expected, launch/offline smoke memory noticeably regresses, or any safety fixture loses protection.

## Implementation Phases

### Phase 1: Design and Baseline

Document the pilot, collect current renderer behavior, and add baseline tests where gaps exist. Do not add the dependency yet.

### Phase 2: Selection Boundary

Create a renderer mode decision layer while keeping both branches pointed at the stable renderer. Add tests for fallback decisions and diagnostics shape.

### Phase 3: Dependency Spike

Add `SwiftStreamingMarkdown` on a short-lived branch or clearly labeled commit. If upstream still fails macOS platform validation, use a narrow patch branch that changes only package platform declarations needed to test macOS 14 compatibility. Measure Package resolution, app size, offline smoke memory, and build time. Keep the feature disabled by default.

Current Phase 3 finding: direct upstream dependency is not macOS-buildable. A manifest-only patch is also insufficient because the package currently has UIKit-coupled source files. The next spike should not touch the main app dependency graph until a macOS-compatible fork or upstream branch can compile as a standalone probe.

### Phase 4: Experimental Pending Reply Renderer

Wire the package only for eligible pending assistant replies. Preserve stable rendering for completed messages and all unsupported fixtures.

### Phase 5: Decision

Keep, expand, or remove the dependency based on measured evidence. Expansion requires parity tests and the full release verification gate.

## Rollback Plan

Rollback must be one commit or one feature flag change:

- Disable `streamingExperimental` selection.
- Remove the package dependency if the spike is rejected.
- Keep existing `MarkdownMessageView` and `MarkdownHTMLDocument` untouched until replacement is proven.

## Open Decision

Phase 2 has been completed by adding the renderer selection boundary and fallback tests without introducing the dependency. Phase 3 has proven that the current upstream package cannot be linked into this macOS app without additional compatibility work. The recommended next implementation step is to create a tiny macOS compatibility fork/spike outside the main app that replaces or gates UIKit-only code, then re-run the standalone probe. The main app should keep the stable renderer and selection boundary until that standalone probe compiles.
