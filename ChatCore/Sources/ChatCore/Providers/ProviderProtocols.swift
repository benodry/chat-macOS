import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Hashable {
    case huggingFace
    case openAI
    case gemini
    case bedrock
    case local
}

public struct ProviderCapabilities: Codable, Hashable {
    public let supportsTools: Bool
    public let supportsReasoning: Bool
    public let supportsStreaming: Bool
    public let maxContextTokens: Int?
    public init(supportsTools: Bool, supportsReasoning: Bool, supportsStreaming: Bool, maxContextTokens: Int? = nil) {
        self.supportsTools = supportsTools
        self.supportsReasoning = supportsReasoning
        self.supportsStreaming = supportsStreaming
        self.maxContextTokens = maxContextTokens
    }
    public static let basicStreaming = ProviderCapabilities(supportsTools: false, supportsReasoning: false, supportsStreaming: true, maxContextTokens: nil)
}

public protocol ChatProvider {
    var kind: ProviderKind { get }
    func capabilities() -> ProviderCapabilities
    func listModels() async throws -> [ModelInfo]
    /// Returns the final assistant message produced.
    func send(messages: [ChatMessage], model: ModelInfo, config: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage
}

public enum ProviderError: Error, CustomStringConvertible {
    case unsupportedFeature(String)
    case network(String)
    case decoding(String)
    case internalError(String)
    case cancelled
    public var description: String {
        switch self {
        case .unsupportedFeature(let s): return "Unsupported feature: \(s)"
        case .network(let s): return "Network error: \(s)"
        case .decoding(let s): return "Decoding error: \(s)"
        case .internalError(let s): return "Internal error: \(s)"
        case .cancelled: return "Cancelled"
        }
    }
}

public final class MockProvider: ChatProvider {
    public init() {}
    public var kind: ProviderKind { .openAI }
    public func capabilities() -> ProviderCapabilities { .basicStreaming }
    public func listModels() async throws -> [ModelInfo] {
        [ModelInfo(modelId: "mock-model", displayName: "Mock Model", provider: kind, capabilities: capabilities())]
    }
    public func send(messages: [ChatMessage], model: ModelInfo, config: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        let userContent = messages.last(where: { $0.role == .user })?.content ?? ""
        for ch in "Echo: \(userContent)" { stream(.token(String(ch))) }
        stream(.completed)
        return ChatMessage(role: .assistant, content: "Echo: \(userContent)")
    }
}
