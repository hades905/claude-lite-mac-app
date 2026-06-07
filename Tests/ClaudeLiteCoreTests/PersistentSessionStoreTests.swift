import Foundation
import Testing
@testable import ClaudeLiteCore

struct PersistentSessionStoreTests {
    @Test
    func savesAndRestoresSessionSnapshot() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let store = PersistentSessionStore(fileURL: directory.appending(path: "session.json"))
        let snapshot = SessionSnapshot(
            messages: [
                ChatMessage.user(
                    text: "Hello",
                    attachments: [ChatAttachment(name: "spec.md", kind: .file)]
                ),
                ChatMessage.assistant(text: "Hi there")
            ],
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        try store.save(snapshot)
        let restored = try store.load()

        #expect(restored == snapshot)
    }

    @Test
    func savesSessionSnapshotAsCompactJSON() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL)
        let snapshot = SessionSnapshot(
            messages: [
                ChatMessage.user(text: "Hello"),
                ChatMessage.assistant(text: "Hi there")
            ],
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        try store.save(snapshot)

        let savedJSON = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!savedJSON.contains("\n  "))
        #expect(savedJSON.split(separator: "\n").count == 1)
        #expect(try store.load() == snapshot)
    }

    @Test
    func saveTrimsOversizedSnapshotBeforeWriting() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL, maxSessionFileBytes: 80_000)
        let oversizedText = String(repeating: "private conversation ", count: 6_000)
        let snapshot = SessionSnapshot(
            messages: [
                ChatMessage.user(text: oversizedText)
            ],
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        try store.save(snapshot)

        let savedSize = try #require(fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let restored = try store.load()
        #expect(savedSize <= 80_000)
        #expect(restored.messages.count == 1)
        #expect(restored.messages.first?.text.count ?? 0 <= SessionSnapshotTrimmer.defaultMaxMessageTextCharacters)
    }

    @Test
    func saveRespectsConfiguredSessionFileLimit() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL, maxSessionFileBytes: 8_000)
        let snapshot = SessionSnapshot(
            messages: (0..<200).map { index in
                ChatMessage.user(text: "message-\(index) " + String(repeating: "private ", count: 1_000))
            },
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        try store.save(snapshot)

        let savedSize = try #require(fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let restored = try store.load()
        #expect(savedSize <= 8_000)
        #expect(restored.messages.count > 0)
        #expect(restored.messages.count < snapshot.messages.count)
        #expect(restored.selectedModelID == "claude-opus-4-7")
        #expect(restored.lastConnectionStatus == .connected)
    }

    @Test
    func savedSessionDoesNotPersistAttachmentLocalFilePath() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL)
        let privateAttachmentURL = URL(fileURLWithPath: "/Users/private/Documents/secret-plan.png")
        let snapshot = SessionSnapshot(
            messages: [
                ChatMessage.user(
                    text: "see attached",
                    attachments: [
                        ChatAttachment(
                            name: "secret-plan.png",
                            kind: .image,
                            localURL: privateAttachmentURL
                        )
                    ]
                )
            ],
            selectedModelID: "claude-opus-4-7",
            lastConnectionStatus: .connected
        )

        try store.save(snapshot)

        let savedJSON = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!savedJSON.contains("/Users/private/Documents"))
        #expect(!savedJSON.contains("secret-plan.png/"))

        let restored = try store.load()
        let restoredAttachment = try #require(restored.messages.first?.attachments.first)
        #expect(restoredAttachment.name == "secret-plan.png")
        #expect(restoredAttachment.kind == .image)
        #expect(restoredAttachment.localURL == nil)
    }

    @Test
    func loadsLegacySnapshotWithoutMessageStatus() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL)
        let legacySnapshot = """
        {
          "lastConnectionStatus" : "connected",
          "messages" : [
            {
              "attachments" : [],
              "createdAt" : 0,
              "id" : "00000000-0000-0000-0000-000000000001",
              "role" : "assistant",
              "text" : "legacy reply"
            }
          ],
          "selectedModelID" : "claude-opus-4-7"
        }
        """

        try legacySnapshot.write(to: fileURL, atomically: true, encoding: .utf8)
        let restored = try store.load()

        #expect(restored.messages.count == 1)
        #expect(restored.messages.first?.status == .sent)
        #expect(restored.messages.first?.text == "legacy reply")
    }

    @Test
    func corruptedSessionLoadsEmptySnapshotAndClearsBadFile() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL)

        try "{ not valid json".write(to: fileURL, atomically: true, encoding: .utf8)

        let restored = try store.load()

        #expect(restored == .empty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test
    func oversizedSessionLoadsEmptySnapshotAndClearsLargeFile() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let fileURL = directory.appending(path: "session.json")
        let store = PersistentSessionStore(fileURL: fileURL)

        let oversizedData = Data(repeating: UInt8(ascii: "x"), count: PersistentSessionStore.defaultMaxSessionFileBytes + 1)
        try oversizedData.write(to: fileURL)

        let restored = try store.load()

        #expect(restored == .empty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }
}
