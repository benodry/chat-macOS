import Foundation

public enum TitleHeuristics {
    /// Derive a conversation title from first user message.
    public static func title(from content: String, max: Int = 40) -> String {
        let firstLine = content.split(separator: "\n").first.map(String.init) ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "New Chat" }
        return String(trimmed.prefix(max))
    }
}