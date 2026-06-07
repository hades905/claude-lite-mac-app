import Foundation

public struct ClaudeModelSection: Equatable, Identifiable, Sendable {
    public let title: String
    public let models: [ClaudeModel]

    public var id: String {
        title
    }

    public init(title: String, models: [ClaudeModel]) {
        self.title = title
        self.models = models
    }
}

public enum ModelCatalog {
    private struct CoreModelSpec {
        let preferredIDs: [String]
        let displayName: String
        let sectionTitle: String

        func matches(_ modelID: String) -> Bool {
            preferredIDs.contains(modelID.lowercased())
        }
    }

    private static let coreModelSpecs = [
        CoreModelSpec(
            preferredIDs: ["claude-opus-4-7"],
            displayName: "Claude 4.7 Opus",
            sectionTitle: "Claude 4.7"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-opus-4-6"],
            displayName: "Claude 4.6 Opus",
            sectionTitle: "Claude 4.6"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-sonnet-4-6"],
            displayName: "Claude 4.6 Sonnet",
            sectionTitle: "Claude 4.6"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-opus-4-20250514", "claude-opus-4-0"],
            displayName: "Claude 4 Opus",
            sectionTitle: "Claude 4"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-sonnet-4-20250514", "claude-sonnet-4-0"],
            displayName: "Claude 4 Sonnet",
            sectionTitle: "Claude 4"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-3-5-sonnet-latest", "claude-3-5-sonnet-20241022", "claude-3-5-sonnet-20240620"],
            displayName: "Claude 3.5 Sonnet",
            sectionTitle: "Claude 3.5"
        ),
        CoreModelSpec(
            preferredIDs: ["claude-3-5-haiku-latest", "claude-3-5-haiku-20241022"],
            displayName: "Claude 3.5 Haiku",
            sectionTitle: "Claude 3.5"
        )
    ]

    private static let coreSectionTitles = [
        "Claude 4.7",
        "Claude 4.6",
        "Claude 4",
        "Claude 3.5"
    ]
    private static let defaultModelID = "claude-opus-4-6"

    public static func claudeOnly(from models: [ClaudeModel]) -> [ClaudeModel] {
        coreClaudeModels(from: models)
    }

    public static func coreClaudeModels(from models: [ClaudeModel]) -> [ClaudeModel] {
        var modelsByID: [String: ClaudeModel] = [:]
        for model in models {
            modelsByID[model.id.lowercased()] = model
        }

        return coreModelSpecs.compactMap { spec in
            guard let source = spec.preferredIDs.lazy.compactMap({ modelsByID[$0] }).first else {
                return nil
            }

            return ClaudeModel(id: source.id, displayName: spec.displayName)
        }
    }

    public static func coreClaudeSections(from models: [ClaudeModel]) -> [ClaudeModelSection] {
        let coreModels = coreClaudeModels(from: models)

        return coreSectionTitles.compactMap { sectionTitle in
            let sectionModels = coreModels.filter { model in
                spec(for: model.id)?.sectionTitle == sectionTitle
            }

            guard !sectionModels.isEmpty else {
                return nil
            }

            return ClaudeModelSection(title: sectionTitle, models: sectionModels)
        }
    }

    public static func resolveSelection(
        available: [ClaudeModel],
        storedSelection: String?,
        bootstrapDefault: String?
    ) -> ClaudeModel? {
        if let storedSelection, let stored = available.first(where: { $0.id == storedSelection }) {
            return stored
        }

        if let bootstrapDefault, let bootstrap = available.first(where: { $0.id == bootstrapDefault }) {
            return bootstrap
        }

        if let defaultModel = available.first(where: { $0.id == defaultModelID }) {
            return defaultModel
        }

        return available.first
    }

    private static func spec(for modelID: String) -> CoreModelSpec? {
        coreModelSpecs.first { $0.matches(modelID) }
    }
}
