import Foundation

/// High-level orchestrator that glues together a ChatProvider and ConversationStore.
/// It owns transient streaming state and returns updated conversation objects.
public final class ChatEngine {
    private let provider: ChatProvider
    private let store: ConversationStore?
    private var activeConversation: ChatConversation?
    public init(provider: ChatProvider, store: ConversationStore? = nil) {
        self.provider = provider
        self.store = store
    }
    public func loadConversation(_ convo: ChatConversation) { self.activeConversation = convo }
    public func currentConversation() -> ChatConversation? { activeConversation }
    /// Sends user text, creating a conversation if none exists. Returns final assistant message.
    @discardableResult
    public func sendUserMessage(_ content: String, model: ModelInfo, config: GenerationConfig = GenerationConfig(), stream: @escaping (TokenEvent)->Void) async throws -> ChatMessage {
        var conv: ChatConversation
        if var existing = activeConversation {
            let user = ChatMessage(role: .user, content: content)
            existing.messages.append(user)
            existing.updatedAt = Date()
            activeConversation = existing
            conv = existing
        } else {
            let user = ChatMessage(role: .user, content: content)
            conv = ChatConversation(provider: provider.kind, modelId: model.modelId, title: TitleHeuristics.title(from: content), messages: [user])
            activeConversation = conv
            try store?.create(conv)
        }
        try store?.save(conv)
        let finalAssistant = try await provider.send(messages: conv.messages, model: model, config: config) { event in
            stream(event)
        }
        // Append assistant
        if var updated = activeConversation {
            updated.messages.append(finalAssistant)
            updated.updatedAt = Date()
            activeConversation = updated
            try store?.save(updated)
        }
        return finalAssistant
    }
    // content title logic moved to TitleHeuristics
}