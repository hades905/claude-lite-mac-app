import Testing
@testable import ClaudeLiteCore

struct ModelCatalogTests {
    @Test
    func filtersToCoreClaudeModelsOnlyInUsefulOrder() {
        let models = [
            ClaudeModel(id: "claude-2.1", displayName: "Claude 2.1"),
            ClaudeModel(id: "claude-3-7-sonnet-latest", displayName: "Claude 3.7 Sonnet"),
            ClaudeModel(id: "gpt-4.1", displayName: "GPT-4.1"),
            ClaudeModel(id: "claude-3-5-haiku-latest", displayName: "claude-3-5-haiku-latest"),
            ClaudeModel(id: "claude-opus-4-6-thinking", displayName: "Claude Opus 4.6 Thinking"),
            ClaudeModel(id: "claude-sonnet-4-6", displayName: "claude-sonnet-4-6"),
            ClaudeModel(id: "claude-opus-4-7", displayName: "Claude Opus 4.7"),
            ClaudeModel(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4"),
            ClaudeModel(id: "claude-opus-4-20250514", displayName: "Claude Opus 4"),
            ClaudeModel(id: "claude-opus-4-6", displayName: "claude-opus-4-6"),
            ClaudeModel(id: "claude-3-5-sonnet-latest", displayName: "claude-3-5-sonnet-latest"),
            ClaudeModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")
        ]

        let filtered = ModelCatalog.coreClaudeModels(from: models)

        #expect(filtered.map(\.id) == [
            "claude-opus-4-7",
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-opus-4-20250514",
            "claude-sonnet-4-20250514",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest"
        ])
        #expect(filtered.map(\.displayName) == [
            "Claude 4.7 Opus",
            "Claude 4.6 Opus",
            "Claude 4.6 Sonnet",
            "Claude 4 Opus",
            "Claude 4 Sonnet",
            "Claude 3.5 Sonnet",
            "Claude 3.5 Haiku"
        ])
    }

    @Test
    func groupsCoreClaudeModelsByVersion() {
        let models = [
            ClaudeModel(id: "claude-3-5-haiku-latest", displayName: "claude-3-5-haiku-latest"),
            ClaudeModel(id: "claude-sonnet-4-6", displayName: "claude-sonnet-4-6"),
            ClaudeModel(id: "claude-opus-4-7", displayName: "claude-opus-4-7")
        ]

        let sections = ModelCatalog.coreClaudeSections(from: models)

        #expect(sections.map(\.title) == ["Claude 4.7", "Claude 4.6", "Claude 3.5"])
        #expect(sections.map { $0.models.map(\.id) } == [
            ["claude-opus-4-7"],
            ["claude-sonnet-4-6"],
            ["claude-3-5-haiku-latest"]
        ])
    }

    @Test
    func choosesOnePreferredIDForEachCoreSlot() {
        let models = [
            ClaudeModel(id: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet 20241022"),
            ClaudeModel(id: "claude-3-5-sonnet-latest", displayName: "Claude 3.5 Sonnet Latest"),
            ClaudeModel(id: "claude-sonnet-4-0", displayName: "Claude Sonnet 4.0"),
            ClaudeModel(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4")
        ]

        let filtered = ModelCatalog.coreClaudeModels(from: models)

        #expect(filtered.map(\.id) == [
            "claude-sonnet-4-20250514",
            "claude-3-5-sonnet-latest"
        ])
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

    @Test
    func fallsBackToClaude46OpusWhenNoStoredOrBootstrapDefaultExists() {
        let models = [
            ClaudeModel(id: "claude-opus-4-7", displayName: "Claude 4.7 Opus"),
            ClaudeModel(id: "claude-opus-4-6", displayName: "Claude 4.6 Opus"),
            ClaudeModel(id: "claude-sonnet-4-6", displayName: "Claude 4.6 Sonnet")
        ]

        let selection = ModelCatalog.resolveSelection(
            available: models,
            storedSelection: nil,
            bootstrapDefault: nil
        )

        #expect(selection?.id == "claude-opus-4-6")
    }
}
