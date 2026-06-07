# Claude Lite Mac App V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight single-window macOS Claude client that can verify connectivity, load Claude models, send text messages, persist chat history, remember the selected model, and bootstrap secure key storage from local developer config.

**Architecture:** Use a Swift Package with a testable core library plus a SwiftUI executable app target. Keep network access, persistence, secure storage, and view state in separate modules so the UI stays thin and behavior remains testable without launching the app window.

**Tech Stack:** Swift 6, SwiftUI, Observation, URLSession, Security/Keychain, JSON persistence, Swift Testing

---

## File Structure

- `Package.swift`
  Package definition for the core library, app executable, and tests.
- `Sources/ClaudeLiteCore/Models/*`
  Chat, model, connection, and attachment domain types.
- `Sources/ClaudeLiteCore/Services/*`
  API client, model loading, connection checking, persistence, config bootstrap, and secure storage.
- `Sources/ClaudeLiteCore/ViewModels/ChatViewModel.swift`
  App orchestration for startup, messaging, model switching, and attachment handling.
- `Sources/ClaudeLiteMacApp/*`
  SwiftUI app entry plus the main window and reusable UI sections.
- `Tests/ClaudeLiteCoreTests/*`
  Red-green coverage for filtering, parsing, persistence, and view-model flows.

## Tasks

### Task 1: Bootstrap project structure

- [ ] Write failing tests for model filtering and persisted settings recovery.
- [ ] Run the tests and confirm they fail because the core library does not exist yet.
- [ ] Add the Swift Package, the core target, the app target, and the initial domain models.
- [ ] Re-run the focused tests until they pass.

### Task 2: Add local bootstrap and secure key storage

- [ ] Write failing tests for local config parsing and startup credential import rules.
- [ ] Run the tests and confirm they fail for the expected reasons.
- [ ] Implement a local bootstrap reader for `.local/tuzi-config.json`, plus a secure-store protocol and a Keychain-backed implementation.
- [ ] Re-run the focused tests until they pass.

### Task 3: Implement network layer

- [ ] Write failing tests for Claude model filtering, `/v1/models` parsing, and `/v1/messages` response parsing.
- [ ] Run the tests and confirm they fail before production code exists.
- [ ] Implement the API client, model service, connection service, and chat service using the verified Tuzi response shapes.
- [ ] Re-run the focused tests until they pass.

### Task 4: Implement persistence and startup recovery

- [ ] Write failing tests for saving and restoring messages, attachments, selected model, and last known connection state.
- [ ] Run the tests and confirm they fail for missing persistence behavior.
- [ ] Implement JSON-backed stores in the app support directory and wire them into the startup path.
- [ ] Re-run the focused tests until they pass.

### Task 5: Implement app state coordination

- [ ] Write failing tests for startup flow, manual connection checks, successful sends, failed sends, and model fallback behavior.
- [ ] Run the tests and confirm the failures are caused by missing orchestration logic.
- [ ] Implement `ChatViewModel` to coordinate services, state changes, draft clearing, optimistic user messages, assistant replies, and persistence.
- [ ] Re-run the focused tests until they pass.

### Task 6: Implement the SwiftUI shell

- [ ] Build the single-window layout with a top status bar, a scrollable message area, attachment cards, and a bottom composer.
- [ ] Add a Claude-only model picker, a reconnect button, file/image selection actions, and readable empty/loading/error states.
- [ ] Connect the UI to the tested view model without moving business logic into the view layer.

### Task 7: Verify end to end

- [ ] Run `swift test` and confirm all tests pass.
- [ ] Run `swift build` and confirm the package builds successfully.
- [ ] Attempt to launch the app executable and verify startup behavior with the local bootstrap config.
- [ ] Record any remaining gateway limitation around message attachments separately from the working text-chat flow.
