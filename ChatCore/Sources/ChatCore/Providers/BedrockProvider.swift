import Foundation

/// AWS Bedrock provider (using InvokeModelWithResponseStream for streaming-compatible output).
/// Assumes caller configures a lightweight HTTP gateway that signs requests; direct SigV4 signing not implemented here.
public final class BedrockProvider: ChatProvider {
    public struct Configuration {
        public let modelId: String
        public let endpoint: URL // Gateway endpoint that forwards to Bedrock
        public init(modelId: String, endpoint: URL) { self.modelId = modelId; self.endpoint = endpoint }
    }
    public var kind: ProviderKind { .bedrock }
    private let config: Configuration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let capabilitiesValue = ProviderCapabilities(supportsTools: false, supportsReasoning: false, supportsStreaming: true, maxContextTokens: nil)
    // Cache for model listing (simple, 5 min)
    private var cachedModels: [ModelInfo]? = nil
    private var lastFetch: Date? = nil
    public init(configuration: Configuration, session: URLSession = .shared) { self.config = configuration; self.session = session }
    public func capabilities() -> ProviderCapabilities { capabilitiesValue }
    public func listModels() async throws -> [ModelInfo] {
        if let cached = cachedModels, let last = lastFetch, Date().timeIntervalSince(last) < 300 { return cached }
        // Attempt gateway enumeration: GET /models -> [{"modelId":"anthropic.claude-3-haiku", "reasoning":false, "tools":false, "context":200000}]
        var models: [ModelInfo] = []
        do {
            var req = URLRequest(url: config.endpoint.appendingPathComponent("models"))
            req.httpMethod = "GET"
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                struct GatewayModel: Codable { let modelId: String; let reasoning: Bool?; let tools: Bool?; let context: Int? }
                if let decoded = try? JSONDecoder().decode([GatewayModel].self, from: data) {
                    models = decoded.map { gm in
                        let caps = ProviderCapabilities(supportsTools: gm.tools ?? false, supportsReasoning: gm.reasoning ?? false, supportsStreaming: true, maxContextTokens: gm.context)
                        return ModelInfo(modelId: gm.modelId, displayName: gm.modelId, provider: kind, capabilities: caps)
                    }
                }
            }
        } catch { /* fallback below */ }
        if models.isEmpty {
            // Static fallback popular Bedrock models (simplified)
            let staticIds = ["anthropic.claude-3-haiku", "anthropic.claude-3-sonnet", "meta.llama3-70b-instruct", "meta.llama3-8b-instruct"]
            models = staticIds.map { id in
                let reasoning = id.contains("sonnet") // rough heuristic
                let caps = ProviderCapabilities(supportsTools: false, supportsReasoning: reasoning, supportsStreaming: true, maxContextTokens: nil)
                return ModelInfo(modelId: id, displayName: id, provider: kind, capabilities: caps)
            }
        }
        models.sort { $0.displayName < $1.displayName }
        cachedModels = models
        lastFetch = Date()
        return models
    }
    struct DeltaObj: Codable { let delta: String?; let completed: Bool? }
    static func parseDelta(line: String, decoder: JSONDecoder) -> DeltaObj? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? decoder.decode(DeltaObj.self, from: data)
    }
    public func send(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        // Expect gateway to accept POST /invoke with JSON payload {modelId, messages, parameters}
        var request = URLRequest(url: config.endpoint.appendingPathComponent("invoke"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct InMessage: Codable { let role: String; let content: String }
        struct Body: Codable { let modelId: String; let messages: [InMessage]; let temperature: Double?; let maxTokens: Int? }
        let body = Body(modelId: config.modelId, messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }, temperature: gen.temperature, maxTokens: gen.maxTokens)
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ProviderError.network("Bedrock gateway bad status") }
        var assistant = ChatMessage(role: .assistant, content: "")
        var accumulator = DeltaAccumulator()
        for try await rawLine in bytes.lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let decoded = BedrockProvider.parseDelta(line: trimmed, decoder: decoder) else { continue }
            if let piece = decoded.delta, !piece.isEmpty {
                assistant.content += piece
                let d = accumulator.delta(new: assistant.content)
                if !d.isEmpty { stream(.token(d)) }
            }
            if decoded.completed == true { break }
        }
        stream(.completed)
        return assistant
    }
}