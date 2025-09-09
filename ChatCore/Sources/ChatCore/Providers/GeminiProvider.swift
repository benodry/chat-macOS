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
    // Model listing (dynamic). We fetch once per provider instance; simple in‑memory cache.
    private var cachedModels: [ModelInfo]? = nil
    private var lastModelFetch: Date? = nil
    private let modelCacheTTL: TimeInterval = 300
    public func listModels() async throws -> [ModelInfo] {
    if let cached = cachedModels, let last = lastModelFetch, Date().timeIntervalSince(last) < modelCacheTTL {
            return cached
        }
        struct ListResponse: Codable { struct Model: Codable { let name: String; let displayName: String?; let inputTokenLimit: Int?; let supportedGenerationMethods: [String]? }
            let models: [Model]
        }
        var url = config.baseURL.appendingPathComponent("/v1beta/models")
        // Append API key query param
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var q = comps.queryItems ?? []
            q.append(URLQueryItem(name: "key", value: config.apiKey))
            comps.queryItems = q
            url = comps.url ?? url
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            // Fallback to configured single model
            return [ModelInfo(modelId: config.model, displayName: config.model, provider: kind, capabilities: capabilities())]
        }
        guard let decoded = try? decoder.decode(ListResponse.self, from: data) else {
            return [ModelInfo(modelId: config.model, displayName: config.model, provider: kind, capabilities: capabilities())]
        }
        let mapped: [ModelInfo] = decoded.models.compactMap { m in
            // name is like "models/gemini-1.5-flash" -> extract suffix after last '/'
            guard let id = m.name.split(separator: "/").last.map(String.init) else { return nil }
            let reasoning = id.lowercased().contains("pro") || id.lowercased().contains("exp") || id.lowercased().contains("reason")
            let supportsStreaming = m.supportedGenerationMethods?.contains(where: { $0.lowercased().contains("generatecontent") }) ?? true
            let caps = ProviderCapabilities(supportsTools: false, supportsReasoning: reasoning, supportsStreaming: supportsStreaming, maxContextTokens: m.inputTokenLimit)
            return ModelInfo(modelId: id, displayName: m.displayName ?? id, provider: kind, capabilities: caps)
        }.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        if !mapped.isEmpty { cachedModels = mapped; lastModelFetch = Date(); return mapped }
        return [ModelInfo(modelId: config.model, displayName: config.model, provider: kind, capabilities: capabilities())]
    }
    // Exposed for tests: parse a single streaming JSON line returning concatenated text (if any)
    struct StreamResp: Codable {
        struct Candidate: Codable {
            struct Content: Codable {
                struct Part: Codable { let text: String? }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]?
    }
    struct ParsedLine { let text: String; let reasoning: String }
    /// Extract user-visible text and reasoning segments from a streaming JSON line.
    /// Heuristic: parts whose text is wrapped in <thinking>...</thinking> or fenced with ```thinking ...``` or prefixed with "Thought:"/"Reasoning:" are treated as reasoning.
    static func extractText(from line: String, decoder: JSONDecoder) -> String { // backward compat in tests
        parseLine(line, decoder: decoder).text
    }
    static func parseLine(_ line: String, decoder: JSONDecoder) -> ParsedLine {
        guard let data = line.data(using: .utf8), let decoded = try? decoder.decode(StreamResp.self, from: data), let parts = decoded.candidates?.first?.content.parts else {
            return ParsedLine(text: "", reasoning: "")
        }
        var normal: [String] = []
        var reasoningSegs: [String] = []
        for p in parts {
            guard let t = p.text, !t.isEmpty else { continue }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if GeminiProvider.isReasoningBlock(trimmed) {
                reasoningSegs.append(GeminiProvider.stripReasoningMarkers(trimmed))
            } else {
                normal.append(t)
            }
        }
        return ParsedLine(text: normal.joined(), reasoning: reasoningSegs.joined(separator: "\n"))
    }
    private static func isReasoningBlock(_ s: String) -> Bool {
        if s.hasPrefix("<thinking>") && s.contains("</thinking>") { return true }
        if s.hasPrefix("```thinking") { return true }
        let lower = s.lowercased()
        if lower.hasPrefix("thought:") || lower.hasPrefix("reasoning:") { return true }
        return false
    }
    private static func stripReasoningMarkers(_ s: String) -> String {
        var out = s
        if out.hasPrefix("<thinking>") && out.contains("</thinking>") {
            out = out.replacingOccurrences(of: "<thinking>", with: "")
            out = out.replacingOccurrences(of: "</thinking>", with: "")
        }
        if out.hasPrefix("```thinking") {
            out = out.replacingOccurrences(of: "```thinking", with: "")
            if let range = out.range(of: "```", options: [.backwards]) { out.removeSubrange(range) }
        }
        if out.lowercased().hasPrefix("thought:") { out = String(out.dropFirst("Thought:".count)) }
        if out.lowercased().hasPrefix("reasoning:") { out = String(out.dropFirst("Reasoning:".count)) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let parsed = GeminiProvider.parseLine(trimmed, decoder: decoder)
            if !parsed.reasoning.isEmpty { stream(.reasoning(parsed.reasoning)) }
            if !parsed.text.isEmpty {
                assistant.content += parsed.text
                let delta = accumulator.delta(new: assistant.content)
                if !delta.isEmpty { stream(.token(delta)) }
            }
        }
        stream(.completed)
        return assistant
    }
}
