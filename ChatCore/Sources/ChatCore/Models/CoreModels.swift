import Foundation

public enum ChatRole: String, Codable {
    case user, assistant, system, tool
}

public struct MessageMetadata: Codable, Hashable {
    public var toolCalls: [ToolCall] = []
    public var toolResults: [ToolResult] = []
    public var reasoning: String? = nil
    public init(toolCalls: [ToolCall] = [], toolResults: [ToolResult] = []) {
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable {
    public let id: UUID
    public var remoteId: String?
    public var role: ChatRole
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: MessageMetadata
    
    public init(id: UUID = UUID(), remoteId: String? = nil, role: ChatRole, content: String, createdAt: Date = Date(), updatedAt: Date = Date(), metadata: MessageMetadata = MessageMetadata()) {
        self.id = id
        self.remoteId = remoteId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct ChatConversation: Codable, Identifiable, Hashable {
    public let id: UUID
    public var remoteId: String?
    public var provider: ProviderKind
    public var modelId: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]
    
    public init(id: UUID = UUID(), remoteId: String? = nil, provider: ProviderKind, modelId: String, title: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.remoteId = remoteId
        self.provider = provider
        self.modelId = modelId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public struct GenerationConfig: Codable, Hashable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var reasoningBudget: Int?
    public init(temperature: Double? = nil, maxTokens: Int? = nil, topP: Double? = nil, topK: Int? = nil, presencePenalty: Double? = nil, frequencyPenalty: Double? = nil, reasoningBudget: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.reasoningBudget = reasoningBudget
    }
}

public enum TokenEvent: Hashable {
    case token(String)
    case reasoning(String)
    case webSearchUpdate(String)
    case webSearchSources([String]) // simplified; map real source model later
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case completed
    case error(String)
}

public struct ModelInfo: Codable, Hashable, Identifiable {
    public var id: String { modelId }
    public let modelId: String
    public let displayName: String
    public let provider: ProviderKind
    public let capabilities: ProviderCapabilities
    public init(modelId: String, displayName: String, provider: ProviderKind, capabilities: ProviderCapabilities) {
        self.modelId = modelId
        self.displayName = displayName
        self.provider = provider
        self.capabilities = capabilities
    }
}

public struct ToolCall: Codable, Hashable, Identifiable {
    public var id: String { name + "_" + (argumentsHash) }
    public let name: String
    public let argumentsJSON: String
    private var argumentsHash: String { String(argumentsJSON.hashValue) }
    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ToolResult: Codable, Hashable, Identifiable {
    public var id: String { toolCallId }
    public let toolCallId: String
    public let outputJSON: String
    public init(toolCallId: String, outputJSON: String) {
        self.toolCallId = toolCallId
        self.outputJSON = outputJSON
    }
}
