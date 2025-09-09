import Foundation

/// Basic OpenAI-compatible provider (chat/completions) with optional streaming.
/// Streaming implemented via SSE-like incremental lines beginning with 'data:'
public final class OpenAICompatibleProvider: ChatProvider {
    public struct Configuration {
        public let baseURL: URL
        public let apiKey: String
        public let defaultModel: String
        public let timeout: TimeInterval
        public init(baseURL: URL, apiKey: String, defaultModel: String, timeout: TimeInterval = 60) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.defaultModel = defaultModel
            self.timeout = timeout
        }
    }
    public var kind: ProviderKind { .openAI }
    private let config: Configuration
    private let session: URLSession
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    // TODO: Detect function/tool calls in streaming delta (OpenAI: choices[].delta.tool_calls)
    private let capabilitiesValue: ProviderCapabilities = .init(supportsTools: false, supportsReasoning: false, supportsStreaming: true, maxContextTokens: nil)
    public init(configuration: Configuration, session: URLSession = .shared) {
        self.config = configuration
        self.session = session
    }
    public func capabilities() -> ProviderCapabilities { capabilitiesValue }

    public func listModels() async throws -> [ModelInfo] {
        // Minimal: return only configured default model. Future: call /v1/models
        return [ModelInfo(modelId: config.defaultModel, displayName: config.defaultModel, provider: kind, capabilities: capabilities())]
    }

    public func send(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        let url = self.config.baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url, timeoutInterval: self.config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(self.config.apiKey)", forHTTPHeaderField: "Authorization")
        struct Msg: Codable { let role: String; let content: String }
        struct Payload: Codable {
            let model: String
            let messages: [Msg]
            let stream: Bool
            let temperature: Double?
            let max_tokens: Int?
            let top_p: Double?
        }
        let payload = Payload(
            model: model.modelId,
            messages: messages.map { Msg(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: gen.temperature,
            max_tokens: gen.maxTokens,
            top_p: gen.topP
        )
        request.httpBody = try jsonEncoder.encode(payload)

        // Streaming via bytes
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ProviderError.network("Bad status code")
        }
        var assistant = ChatMessage(role: .assistant, content: "")
        var accumulator = DeltaAccumulator()
        for try await lineData in bytes.lines {
            let line = lineData.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line == "data: [DONE]" { break }
            if line.hasPrefix("data:") {
                let jsonPart = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = jsonPart.data(using: .utf8) else { continue }
                if let delta = try? decodeDelta(data: data) {
                    if !delta.isEmpty {
                        assistant.content += delta
                        let emitted = accumulator.delta(new: assistant.content)
                        if !emitted.isEmpty { stream(.token(emitted)) }
                    }
                }
            }
        }
        stream(.completed)
        return assistant
    }

    private struct StreamingResponse: Codable {
        struct Choice: Codable {
            struct Delta: Codable {
                let content: String?
                // Placeholder for future tool call parsing
                // let tool_calls: [ToolCallPayload]? // map into TokenEvent.toolCall
            }
            let delta: Delta
        }
        let choices: [Choice]
    }
    private func decodeDelta(data: Data) throws -> String {
        let decoded = try jsonDecoder.decode(StreamingResponse.self, from: data)
        return decoded.choices.compactMap { $0.delta.content }.joined()
    }
}