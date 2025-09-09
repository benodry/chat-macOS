import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CryptoKit

/// AWS Bedrock provider using the latest Bedrock Runtime API
/// Supports models like Claude 3.5 Sonnet, Claude 3 Haiku, Llama 3.1, etc.
public final class BedrockProvider: ChatProvider {
    public struct Configuration {
        public let accessKeyId: String
        public let secretAccessKey: String
        public let region: String
        public let defaultModel: String
        public let timeout: TimeInterval
        
        public var baseURL: URL {
            URL(string: "https://bedrock-runtime.\(region).amazonaws.com")!
        }
        
        public init(accessKeyId: String, secretAccessKey: String, region: String = "us-east-1", defaultModel: String = "anthropic.claude-3-5-sonnet-20241022-v2:0", timeout: TimeInterval = 60) {
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
            self.region = region
            self.defaultModel = defaultModel
            self.timeout = timeout
        }
    }
    
    public var kind: ProviderKind { .bedrock }
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
            maxContextTokens: 200_000 // Claude 3.5 supports up to 200k tokens
        )
    }
    
    public func listModels() async throws -> [ModelInfo] {
        // Return known Bedrock models - could be enhanced to call ListFoundationModels API
        return [
            ModelInfo(modelId: "anthropic.claude-3-5-sonnet-20241022-v2:0", displayName: "Claude 3.5 Sonnet (v2)", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "anthropic.claude-3-5-haiku-20241022-v1:0", displayName: "Claude 3.5 Haiku", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "anthropic.claude-3-sonnet-20240229-v1:0", displayName: "Claude 3 Sonnet", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "meta.llama3-1-70b-instruct-v1:0", displayName: "Llama 3.1 70B Instruct", provider: kind, capabilities: capabilities()),
            ModelInfo(modelId: "meta.llama3-1-8b-instruct-v1:0", displayName: "Llama 3.1 8B Instruct", provider: kind, capabilities: capabilities())
        ]
    }
    
    public func send(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        let url = config.baseURL.appendingPathComponent("model/\(model.modelId)/invoke-with-response-stream")
        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create AWS Signature V4
        let date = Date()
        let payload = try createBedrockPayload(messages: messages, model: model, config: gen)
        request.httpBody = payload
        
        try signAWSRequest(&request, payload: payload, date: date)
        
        // Handle streaming response
        #if canImport(FoundationNetworking)
        // For Linux/FoundationNetworking, use data task instead of bytes
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ProviderError.network("Bad status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        // Process the response data (non-streaming for Linux compatibility)
        return try await processBedrockResponse(data: data, stream: stream)
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
                
                if let delta = try? processBedrockDelta(data: data) {
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
    
    private func createBedrockPayload(messages: [ChatMessage], model: ModelInfo, config gen: GenerationConfig) throws -> Data {
        // Create payload based on model type
        if model.modelId.contains("anthropic.claude") {
            let claudeMessages = messages.map { message in
                ClaudeMessage(role: message.role.rawValue, content: message.content)
            }
            
            let payload = ClaudeRequest(
                messages: claudeMessages,
                max_tokens: gen.maxTokens ?? 4096,
                temperature: gen.temperature,
                top_p: gen.topP,
                stream: true,
                anthropic_version: "bedrock-2023-05-31"
            )
            
            return try jsonEncoder.encode(payload)
        } else if model.modelId.contains("meta.llama") {
            let prompt = convertToLlamaPrompt(messages: messages)
            let payload = LlamaRequest(
                prompt: prompt,
                max_gen_len: gen.maxTokens,
                temperature: gen.temperature,
                top_p: gen.topP
            )
            
            return try jsonEncoder.encode(payload)
        } else {
            throw ProviderError.unsupportedFeature("Model \(model.modelId) not supported")
        }
    }
    
    private func convertToLlamaPrompt(messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|system|>\n\(message.content)\n"
            case .user:
                prompt += "<|user|>\n\(message.content)\n"
            case .assistant:
                prompt += "<|assistant|>\n\(message.content)\n"
            case .tool:
                prompt += "<|tool|>\n\(message.content)\n"
            }
        }
        prompt += "<|assistant|>\n"
        return prompt
    }
    
    private func signAWSRequest(_ request: inout URLRequest, payload: Data, date: Date) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: date)
        
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)
        
        // AWS Signature V4 implementation (simplified)
        let payloadHash = SHA256.hash(data: payload).compactMap { String(format: "%02x", $0) }.joined()
        
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue("bedrock", forHTTPHeaderField: "X-Amz-Target")
        
        // Create canonical request
        let canonicalHeaders = "content-type:application/json\nhost:\(config.baseURL.host!)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-date"
        let canonicalRequest = "\(request.httpMethod!)\n\(request.url!.path)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        
        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(config.region)/bedrock/aws4_request"
        let stringToSign = "\(algorithm)\n\(amzDate)\n\(credentialScope)\n\(SHA256.hash(data: canonicalRequest.data(using: .utf8)!).compactMap { String(format: "%02x", $0) }.joined())"
        
        // Create signature
        let kSecret = "AWS4\(config.secretAccessKey)".data(using: .utf8)!
        let kDate = HMAC<SHA256>.authenticationCode(for: dateStamp.data(using: .utf8)!, using: SymmetricKey(data: kSecret))
        let kRegion = HMAC<SHA256>.authenticationCode(for: config.region.data(using: .utf8)!, using: SymmetricKey(data: kDate))
        let kService = HMAC<SHA256>.authenticationCode(for: "bedrock".data(using: .utf8)!, using: SymmetricKey(data: kRegion))
        let kSigning = HMAC<SHA256>.authenticationCode(for: "aws4_request".data(using: .utf8)!, using: SymmetricKey(data: kService))
        let signature = HMAC<SHA256>.authenticationCode(for: stringToSign.data(using: .utf8)!, using: SymmetricKey(data: kSigning))
        
        let signatureHex = signature.compactMap { String(format: "%02x", $0) }.joined()
        
        // Create authorization header
        let authorization = "\(algorithm) Credential=\(config.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signatureHex)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }
    
    #if canImport(FoundationNetworking)
    private func processBedrockResponse(data: Data, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        // For non-streaming response processing (simplified)
        let content = "Response processed" // This would need proper event stream parsing
        
        // Simulate streaming
        for char in content {
            stream(.token(String(char)))
        }
        stream(.completed)
        
        return ChatMessage(role: .assistant, content: content)
    }
    #endif
    
    private func processBedrockDelta(data: Data) throws -> String {
        // Parse Bedrock event stream format
        // This is a simplified implementation - full implementation would parse the binary event stream
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }
        return ""
    }
}

// MARK: - Bedrock API Models

private struct ClaudeRequest: Codable {
    let messages: [ClaudeMessage]
    let max_tokens: Int
    let temperature: Double?
    let top_p: Double?
    let stream: Bool
    let anthropic_version: String
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct LlamaRequest: Codable {
    let prompt: String
    let max_gen_len: Int?
    let temperature: Double?
    let top_p: Double?
}