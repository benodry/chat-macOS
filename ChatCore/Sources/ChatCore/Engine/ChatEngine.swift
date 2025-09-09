import Foundation

/// High-level orchestrator that glues together a ChatProvider and ConversationStore.
/// It owns transient streaming state and returns updated conversation objects.
public final class ChatEngine {
    private let provider: ChatProvider
    private let store: ConversationStore?
    private var activeConversation: ChatConversation?
    public var toolRegistry: ToolRegistry? = nil
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
        // Prepare partial assistant message for incremental streaming persistence.
        let assistantId = UUID()
        var workingAssistant = ChatMessage(id: assistantId, role: .assistant, content: "", metadata: MessageMetadata())
        // Persist initial empty assistant placeholder
        if let store = store { try? store.upsertPartialAssistant(conversationId: conv.id, message: workingAssistant) }
        let finalAssistant = try await provider.send(messages: conv.messages, model: model, config: config) { event in
            switch event {
            case .token(let delta):
                workingAssistant.content += delta
                if let store = store { try? store.upsertPartialAssistant(conversationId: conv.id, message: workingAssistant) }
            case .reasoning(let r):
                // Accumulate reasoning into metadata (not persisted yet)
                workingAssistant.metadata.reasoning = [workingAssistant.metadata.reasoning, r].compactMap { $0 }.joined(separator: "\n")
                if let store = store { try? store.upsertPartialAssistant(conversationId: conv.id, message: workingAssistant) }
            case .toolCall(let tc):
        // Persist tool call as a synthetic tool message? For now attach to assistant metadata.
        workingAssistant.metadata.toolCalls.append(tc)
        if let store = store { try? store.upsertPartialAssistant(conversationId: conv.id, message: workingAssistant) }
        // Execute tool call immediately if registry available
                Task { [weak self] in
                    guard let self, let reg = toolRegistry else { return }
                    if let result = try? await reg.invoke(name: tc.name, argumentsJSON: tc.argumentsJSON) {
                        let tr = ToolResult(toolCallId: tc.id, outputJSON: result)
            // Attach result to metadata
            workingAssistant.metadata.toolResults.append(tr)
            if let store = store { try? store.upsertPartialAssistant(conversationId: conv.id, message: workingAssistant) }
            // Stream result event
                        stream(.toolResult(tr))
                        // Optionally persist interim tool result inside assistant metadata in future
                    }
                }
            default: break
            }
            stream(event)
        }
        // Append assistant
        if var updated = activeConversation {
            // Replace last partial with finalized assistant (include metadata)
            if let idx = updated.messages.lastIndex(where: { $0.id == assistantId }) {
                updated.messages[idx] = finalAssistant
            } else {
                updated.messages.append(finalAssistant)
            }
            updated.updatedAt = Date()
            activeConversation = updated
            try store?.save(updated)
        }
        return finalAssistant
    }
    // content title logic moved to TitleHeuristics
}