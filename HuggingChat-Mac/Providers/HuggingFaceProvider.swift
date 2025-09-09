import Foundation
import Combine
import ChatCore

/// Adapter that wraps existing Hugging Face networking & streaming into the generic `ChatProvider` API.
/// Initial scope: single or multi-turn basic chat (no tools) with token streaming.
/// Limitations (to iterate later):
///  - Remote message IDs for prior turns are not back-propagated to existing local messages (only newest assistant message gets remoteId).
///  - Does not yet attempt to map webSearch / reasoning events (TODO Phase 0a enhancement).
final class HuggingFaceProvider: ChatProvider {
    struct HFState { var models: [LLMModel] = [] }
    private var state = HFState()
    private var cancellables = Set<AnyCancellable>()
    private let networking: HFNetworking
    private let conversationStore: ConversationStore?
    public var kind: ProviderKind { .huggingFace }

    /// - Parameters:
    ///   - networking: abstraction over network & streaming.
    ///   - conversationStore: optional local store to mirror remote conversations for unified history UI.
    init(networking: HFNetworking = DefaultHFNetworking(), conversationStore: ConversationStore? = nil) {
        self.networking = networking
        self.conversationStore = conversationStore
    }

    func capabilities() -> ProviderCapabilities { .init(supportsTools: false, supportsReasoning: true, supportsStreaming: true, maxContextTokens: nil) }

    func listModels() async throws -> [ModelInfo] {
        try await withCheckedThrowingContinuation { cont in
            networking.getModels()
                .sink { completion in
                    if case .failure(let err) = completion { cont.resume(throwing: ProviderError.network(err.localizedDescription)) }
                } receiveValue: { [weak self] models in
                    self?.state.models = models
                    let mapped = models.map { m in ModelInfo(modelId: m.id, displayName: m.displayName, provider: .huggingFace, capabilities: self?.capabilities() ?? .basicStreaming) }
                    cont.resume(returning: mapped)
                }
                .store(in: &cancellables)
        }
    }

    func send(messages: [ChatMessage], model: ModelInfo, config: GenerationConfig, stream: @escaping (TokenEvent) -> Void) async throws -> ChatMessage {
        guard let lastUser = messages.last(where: { $0.role == .user }) else { throw ProviderError.internalError("No user message to send") }
        let existingRemoteId = messages.compactMap { $0.remoteId }.last
        guard let hfModel = state.models.first(where: { $0.id == model.modelId }) ?? loadHFModelFromUserDefaults(id: model.modelId) else {
            throw ProviderError.internalError("HF model not cached: \(model.modelId)")
        }
        let remoteConversationId = try await ensureConversation(remoteId: existingRemoteId, model: hfModel)
        var assistantMessage = ChatMessage(role: .assistant, content: "")
        let previousAssistantRemoteId = messages.reversed().first { $0.role == .assistant && $0.remoteId != nil }?.remoteId

        return try await withCheckedThrowingContinuation { cont in
            var accumulator = DeltaAccumulator()
            networking.streamPrompt(conversationId: remoteConversationId, previousAssistantId: previousAssistantRemoteId, input: lastUser.content, webSearch: false)
                .sink { completion in
                    switch completion {
                    case .finished:
                        stream(.completed)
                        self.fetchConversation(conversationId: remoteConversationId) { result in
                            if case .success(let (assistantRemoteId, convo)) = result {
                                assistantMessage.remoteId = assistantRemoteId
                                // Mirror full conversation locally if store provided
                                if let store = self.conversationStore, let normalized = convo.toChatConversation(provider: .huggingFace) {
                                    do { try self.upsert(normalized, store: store) } catch { /* swallow for now */ }
                                }
                            }
                            cont.resume(returning: assistantMessage)
                        }
                    case .failure(let error):
                        stream(.error(error.localizedDescription))
                        cont.resume(throwing: ProviderError.network(error.localizedDescription))
                    }
                } receiveValue: { vm in
                    assistantMessage.content = vm.content
                    let delta = accumulator.delta(new: vm.content)
                    if !delta.isEmpty { stream(.token(delta)) }
                    if let reasoning = vm.reasoning { stream(.reasoning(reasoning)) }
                }
                .store(in: &self.cancellables)
        }
    }

    // MARK: - Helpers
    private func ensureConversation(remoteId: String?, model: LLMModel) async throws -> String {
        if let remoteId { return remoteId }
        return try await withCheckedThrowingContinuation { cont in
            networking.createConversation(model: model)
                .sink { completion in
                    if case .failure(let err) = completion { cont.resume(throwing: ProviderError.network(err.localizedDescription)) }
                } receiveValue: { convo in cont.resume(returning: convo.serverId) }
                .store(in: &cancellables)
        }
    }
    private func fetchConversation(conversationId: String, completion: @escaping (Result<(assistantRemoteId: String?, convo: Conversation), Error>) -> Void) {
        networking.getConversation(id: conversationId)
            .sink { c in if case .failure(let err) = c { completion(.failure(err)) } }
            receiveValue: { convo in
                let lastAssistant = convo.messages.reversed().first { $0.author == .assistant }
                completion(.success((lastAssistant?.id, convo)))
            }
            .store(in: &cancellables)
    }
    private func loadHFModelFromUserDefaults(id: String) -> LLMModel? {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.models), let models = try? JSONDecoder().decode([LLMModel].self, from: data) else { return nil }
        return models.first { $0.id == id }
    }

    private func upsert(_ conversation: ChatConversation, store: ConversationStore) throws {
        if try store.load(id: conversation.id) == nil {
            try store.create(conversation)
        } else {
            try store.save(conversation)
        }
    }
}