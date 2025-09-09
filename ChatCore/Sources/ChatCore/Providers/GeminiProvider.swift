import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Google Gemini API provider using the latest Gemini API v1beta
/// Supports models like gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash-exp
public final class GeminiProvider: ChatProvider {
    public struct Configuration {
        public let apiKey: String
        public let baseURL: URL
        public let defaultModel: String
        public let timeout: TimeInterval
        
        public init(apiKey: String, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!, defaultModel: String = "gemini-1.5-flash", timeout: TimeInterval = 60) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.defaultModel = defaultModel
            self.timeout = timeout
        }
    }
    
    public var kind: ProviderKind { .gemini }
    private let config: Configuration
    private let session: URLSession
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    
    public init(configuration: Configuration, session: URLSession = .shared) {
        self.config = configuration
        self.session = session
    }
    
    public func capabilities() -> ProviderCapabilities {
        return ProviderCapabilities(
            supportsTools: true,
            supportsReasoning: true,
            supportsStreaming: true,
            maxContextTokens: 1_048_576 // Gemini 1.5 supports up to 1M tokens
        )
    }
    
    public func listModels() async throws -> [ModelInfo] {
        // Return known Gemini models - could be enhanced to call /v1beta/models API
        return [
            ModelInfo(modelId: "gemini-2.0-flash-exp", displayName: "Gemini 2.0 Flash (Experimental)", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "gemini-1.5-pro", displayName: "Gemini 1.5 Pro", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "gemini-1.5-flash", displayName: "Gemini 1.5 Flash", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "gemini-1.5-flash-8b", displayName: "Gemini 1.5 Flash 8B", provider: kind, capabilities: capabilities())
        ]
    }
    
    public func send(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        let url = self.config.baseURL.appendingPathComponent("v1beta/models/\(model.modelId):streamGenerateContent")
        var request = URLRequest(url: url, timeoutInterval: self.config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        // Convert messages to Gemini format
        let geminiMessages = convertToGeminiFormat(messages: messages)
        
        let payload = GeminiRequest(
            contents: geminiMessages,
            generationConfig: GeminiGenerationConfig(
                temperature: gen.temperature,
                maxOutputTokens: gen.maxTokens,
                topP: gen.topP,
                topK: gen.topK
            )
        )
        
        request.httpBody = try jsonEncoder.encode(payload)
        
        // Handle streaming response
        #if canImport(FoundationNetworking)
        // For Linux/FoundationNetworking, use data task instead of bytes
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ProviderError.network("Bad status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        // Process the response data (non-streaming for Linux compatibility)
        return try await processGeminiResponse(data: data, stream: stream)
        #else
        // For macOS, use streaming bytes
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ProviderError.network("Bad status code: \(http.statusCode)")
        }
        
        var assistant = ChatMessage(role: .assistant, content: "")
        var accumulator = DeltaAccumulator()
        
        for try await lineData in bytes.lines {
            let line = lineData.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            
            if line.hasPrefix("data: ") {
                let jsonPart = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                guard let data = jsonPart.data(using: .utf8) else { continue }
                
                if let delta = try? processGeminiDelta(data: data) {
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
        #endif
    }
    
    private func convertToGeminiFormat(messages: [ChatMessage]) -> [GeminiContent] {
        return messages.map { message in
            let role = message.role == .user ? "user" : "model"
            return GeminiContent(
                role: role,
                parts: [GeminiPart(text: message.content)]
            )
        }
    }
    
    #if canImport(FoundationNetworking)
    private func processGeminiResponse(data: Data, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        // For non-streaming response processing
        let response = try jsonDecoder.decode(GeminiResponse.self, from: data)
        let content = response.candidates.first?.content.parts.first?.text ?? ""
        
        // Simulate streaming by sending the content character by character
        for char in content {
            stream(.token(String(char)))
        }
        stream(.completed)
        
        return ChatMessage(role: .assistant, content: content)
    }
    #endif
    
    private func processGeminiDelta(data: Data) throws -> String {
        let response = try jsonDecoder.decode(GeminiResponse.self, from: data)
        return response.candidates.first?.content.parts.first?.text ?? ""
    }
}

// MARK: - Gemini API Models

private struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let topP: Double?
    let topK: Int?
}

private struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Codable {
    let content: GeminiContent
    let finishReason: String?
}