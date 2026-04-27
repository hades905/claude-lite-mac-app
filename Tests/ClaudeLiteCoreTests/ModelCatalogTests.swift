import Testing
@testable import ClaudeLiteCore

struct ModelCatalogTests {
    @Test
    func filtersToClaudeModelsOnly() {
        let models = [
            ClaudeModel(id: "gpt-4.1", displayName: "GPT-4.1"),
            ClaudeModel(id: "claude-sonnet-4", displayName: "Claude Sonnet 4"),
            ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7"),
            ClaudeModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")
        ]

        let filtered = ModelCatalog.claudeOnly(from: models)

        #expect(filtered.map(\.id) == ["claude-sonnet-4", "claude-opus-4-7"])
    }

    @Test
    func prefersStoredDefaultModelWhenStillAvailable() {
        let models = [
            ClaudeModel(id: "claude-sonnet-4", displayName: "Claude Sonnet 4"),
            ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7")
        ]

        let selection = ModelCatalog.resolveSelection(
            available: models,
            storedSelection: "claude-opus-4-7",
            bootstrapDefault: "claude-sonnet-4"
        )

        #expect(selection?.id == "claude-opus-4-7")
    }
}
