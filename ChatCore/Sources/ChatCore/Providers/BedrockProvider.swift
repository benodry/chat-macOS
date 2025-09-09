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
    public init(configuration: Configuration, session: URLSession = .shared) { self.config = configuration; self.session = session }
    public func capabilities() -> ProviderCapabilities { capabilitiesValue }
    public func listModels() async throws -> [ModelInfo] { [ModelInfo(modelId: config.modelId, displayName: config.modelId, provider: kind, capabilities: capabilities())] }
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
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Expect each line as {"delta":"text"} or {"completed":true}
            struct DeltaObj: Codable { let delta: String?; let completed: Bool? }
            if let data = trimmed.data(using: .utf8), let decoded = try? decoder.decode(DeltaObj.self, from: data) {
                if let piece = decoded.delta, !piece.isEmpty {
                    assistant.content += piece
                    let d = accumulator.delta(new: assistant.content)
                    if !d.isEmpty { stream(.token(d)) }
                }
                if decoded.completed == true { break }
            }
        }
        stream(.completed)
        return assistant
    }
}