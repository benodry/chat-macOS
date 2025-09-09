import Foundation
import Combine

/// Protocol abstraction over existing static NetworkService / streaming logic so the provider can be unit tested.
protocol HFNetworking {
    func getModels() -> AnyPublisher<[LLMModel], HFError>
    func createConversation(model: LLMModel) -> AnyPublisher<Conversation, HFError>
    func getConversation(id: String) -> AnyPublisher<Conversation, HFError>
    func streamPrompt(conversationId: String, previousAssistantId: String?, input: String, webSearch: Bool) -> AnyPublisher<MessageViewModel, HFError>
}

final class DefaultHFNetworking: HFNetworking {
    func getModels() -> AnyPublisher<[LLMModel], HFError> { NetworkService.getModels() }
    func createConversation(model: LLMModel) -> AnyPublisher<Conversation, HFError> { NetworkService.createConversation(base: model) }
    func getConversation(id: String) -> AnyPublisher<Conversation, HFError> { NetworkService.getConversation(id: id) }
    func streamPrompt(conversationId: String, previousAssistantId: String?, input: String, webSearch: Bool) -> AnyPublisher<MessageViewModel, HFError> {
        let assistantVM = MessageViewModel(author: .assistant, content: "")
        let handler = SendPromptHandler(conversationId: conversationId, messageVM: assistantVM)
        let body = PromptRequestBody(id: previousAssistantId, inputs: input, webSearch: webSearch, files: nil)
        handler.sendPromptReq(reqBody: body)
        return handler.update.eraseToAnyPublisher()
    }
}

/// Simple mock for tests; configurable outputs.
final class MockHFNetworking: HFNetworking {
    var models: [LLMModel] = []
    var conversations: [String: Conversation] = [:]
    var streamChunks: [String] = []
    var failError: HFError?
    
    func getModels() -> AnyPublisher<[LLMModel], HFError> {
        if let failError { return Fail(error: failError).eraseToAnyPublisher() }
        return Just(models).setFailureType(to: HFError.self).eraseToAnyPublisher()
    }
    func createConversation(model: LLMModel) -> AnyPublisher<Conversation, HFError> {
        if let failError { return Fail(error: failError).eraseToAnyPublisher() }
        let convo = Conversation(serverId: UUID().uuidString, title: model.displayName, modelId: model.id, updatedAt: Date(), messages: [])
        conversations[convo.serverId] = convo
        return Just(convo).setFailureType(to: HFError.self).eraseToAnyPublisher()
    }
    func getConversation(id: String) -> AnyPublisher<Conversation, HFError> {
        if let failError { return Fail(error: failError).eraseToAnyPublisher() }
        guard let c = conversations[id] else { return Fail(error: HFError.modelNotFound).eraseToAnyPublisher() }
        return Just(c).setFailureType(to: HFError.self).eraseToAnyPublisher()
    }
    func streamPrompt(conversationId: String, previousAssistantId: String?, input: String, webSearch: Bool) -> AnyPublisher<MessageViewModel, HFError> {
        if let failError { return Fail(error: failError).eraseToAnyPublisher() }
        let subject = PassthroughSubject<MessageViewModel, HFError>()
        DispatchQueue.global().async { [streamChunks] in
            var content = ""
            for chunk in streamChunks {
                content.append(chunk)
                let vm = MessageViewModel(author: .assistant, content: content)
                subject.send(vm)
            }
            subject.send(completion: .finished)
        }
        return subject.eraseToAnyPublisher()
    }
}