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
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Each line should be a JSON object with candidates[0].content.parts[].text fragments
            struct StreamResp: Codable { struct Candidate: Codable { struct Content: Codable { struct Part: Codable { let text: String? } let parts: [Part] } let content: Content } let candidates: [Candidate]? }
            guard let data = trimmed.data(using: .utf8), let decoded = try? decoder.decode(StreamResp.self, from: data) else { continue }
            if let piece = decoded.candidates?.first?.content.parts.compactMap({ $0.text }).joined(), !piece.isEmpty {
                assistant.content += piece
                let delta = accumulator.delta(new: assistant.content)
                if !delta.isEmpty { stream(.token(delta)) }
            }
        }
        stream(.completed)
        return assistant
    }
}
