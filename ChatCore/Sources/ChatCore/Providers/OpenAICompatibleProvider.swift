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
    // Function/tool call detection (OpenAI: choices[].delta.tool_calls)
    private let capabilitiesValue: ProviderCapabilities = .init(supportsTools: true, supportsReasoning: false, supportsStreaming: true, maxContextTokens: nil)
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
        // Accumulate tool call arguments until complete JSON to emit TokenEvent.toolCall
        var toolCallBuffers: [String: (name: String, args: String)] = [:]
        var accumulator = DeltaAccumulator()
        for try await lineData in bytes.lines {
            let line = lineData.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line == "data: [DONE]" { break }
            if line.hasPrefix("data:") {
                let jsonPart = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = jsonPart.data(using: .utf8) else { continue }
                if let parsed = try? decodeStreamingPayload(data: data) {
                    if !parsed.deltaContent.isEmpty {
                        assistant.content += parsed.deltaContent
                        let emitted = accumulator.delta(new: assistant.content)
                        if !emitted.isEmpty { stream(.token(emitted)) }
                    }
                    // Process tool call partials
                    for tc in parsed.toolCallPartials {
                        var buffer = toolCallBuffers[tc.id] ?? (tc.name, "")
                        buffer.args += tc.argumentsFragment
                        toolCallBuffers[tc.id] = buffer
                        // Attempt to detect complete JSON (naive braces balance)
                        if isLikelyCompleteJSON(buffer.args) {
                            let fullArgs = buffer.args.trimmingCharacters(in: .whitespacesAndNewlines)
                            // Emit tool call event
                            let call = ToolCall(name: buffer.name, argumentsJSON: fullArgs)
                            stream(.toolCall(call))
                            toolCallBuffers.removeValue(forKey: tc.id)
                        }
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
                let tool_calls: [ToolCallChunk]? // OpenAI style
            }
            let delta: Delta
        }
        let choices: [Choice]
    }
    private struct ToolCallChunk: Codable { let id: String?; let type: String?; let function: FunctionChunk? }
    private struct FunctionChunk: Codable { let name: String?; let arguments: String? }
    struct ToolCallPartial { let id: String; let name: String; let argumentsFragment: String }
    private func decodeStreamingPayload(data: Data) throws -> (deltaContent: String, toolCallPartials: [ToolCallPartial]) {
        let decoded = try jsonDecoder.decode(StreamingResponse.self, from: data)
        var content = ""
        var partials: [ToolCallPartial] = []
        for c in decoded.choices {
            if let d = c.delta.content { content += d }
            if let tcs = c.delta.tool_calls {
                for chunk in tcs {
                    guard let fid = chunk.id, let fname = chunk.function?.name, let frag = chunk.function?.arguments else { continue }
                    partials.append(ToolCallPartial(id: fid, name: fname, argumentsFragment: frag))
                }
            }
        }
        return (content, partials)
    }
    private func isLikelyCompleteJSON(_ s: String) -> Bool {
        var balance = 0
        var inString = false
        var prev: Character = " "
        for ch in s {
            if ch == "\"", prev != "\\" { inString.toggle() }
            if !inString {
                if ch == "{" { balance += 1 }
                else if ch == "}" { balance -= 1 }
            }
            prev = ch
        }
        return balance == 0 && s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") && s.contains("}")
    }
}