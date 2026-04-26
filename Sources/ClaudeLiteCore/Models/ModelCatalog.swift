import Foundation

public enum ModelCatalog {
    public static func claudeOnly(from models: [ClaudeModel]) -> [ClaudeModel] {
        models.filter { $0.id.localizedCaseInsensitiveContains("claude") }
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

        return available.first
    }
}
