import Foundation

/// Google Gemini API provider (models.* endpoint v1beta streaming compliant subset).
public final class GeminiProvider: ChatProvider {
    public struct Configuration {
        public let apiKey: String
        public let model: String
        public let baseURL: URL
        public init(apiKey: String, model: String, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
        }
    }
    public var kind: ProviderKind { .gemini }
    private let config: Configuration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let capabilitiesValue = ProviderCapabilities(supportsTools: false, supportsReasoning: true, supportsStreaming: true, maxContextTokens: nil)
    public init(configuration: Configuration, session: URLSession = .shared) { self.config = configuration; self.session = session }
    public func capabilities() -> ProviderCapabilities { capabilitiesValue }
    public func listModels() async throws -> [ModelInfo] { [ModelInfo(modelId: config.model, displayName: config.model, provider: kind, capabilities: capabilities())] }
    // Exposed for tests: parse a single streaming JSON line returning concatenated text (if any)
    struct StreamResp: Codable { struct Candidate: Codable { struct Content: Codable { struct Part: Codable { let text: String? } let parts: [Part] } let content: Content } let candidates: [Candidate]? }
    static func extractText(from line: String, decoder: JSONDecoder) -> String {
        guard let data = line.data(using: .utf8), let decoded = try? decoder.decode(StreamResp.self, from: data) else { return "" }
        return decoded.candidates?.first?.content.parts.compactMap { $0.text }.joined() ?? ""
    }
    public func send(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        // Gemini (v1beta) generateContent streaming endpoint: POST /v1beta/models/{model}:streamGenerateContent?key=API_KEY
        let path = "/v1beta/models/\(model.modelId):streamGenerateContent?key=\(config.apiKey)"
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Part: Codable { let text: String }
        struct Content: Codable { let role: String; let parts: [Part] }
        struct GenerationConfigWrapper: Codable { let temperature: Double?; let maxOutputTokens: Int?; let topP: Double? }
        struct Payload: Codable { let contents: [Content]; let generationConfig: GenerationConfigWrapper? }
        let contents: [Content] = messages.map { m in Content(role: m.role == .assistant ? "model" : m.role.rawValue, parts: [Part(text: m.content)]) }
        let genCfg = GenerationConfigWrapper(temperature: gen.temperature, maxOutputTokens: gen.maxTokens, topP: gen.topP)
        let payload = Payload(contents: contents, generationConfig: genCfg)
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ProviderError.network("Gemini bad status") }
        var assistant = ChatMessage(role: .assistant, content: "")
        var accumulator = DeltaAccumulator()
        for try await rawLine in bytes.lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let piece = GeminiProvider.extractText(from: trimmed, decoder: decoder)
            if !piece.isEmpty {
                assistant.content += piece
                let delta = accumulator.delta(new: assistant.content)
                if !delta.isEmpty { stream(.token(delta)) }
            }
        }
        stream(.completed)
        return assistant
    }
}
