//
//  ConversationModel.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 8/29/24.
//

import SwiftUI
import Combine

enum ConversationState: Equatable {
    case none, empty, loaded, loading, generating, error
}

@Observable final class ConversationViewModel {
    
    var isInteracting = false
    var isMultimodal: Bool = false
    var isTools: Bool = false
    var model: AnyObject?
    var message: MessageRow? = nil
    var messages: [MessageRow] = [
//        MessageRow(
//            type: .user,
//            isInteracting: false,
//            contentType: .rawText("What is the meaning of life?")
//        ),
//        MessageRow(
//            type: .assistant,
//            isInteracting: false,
//            contentType: .rawText("""
//### How to Sort a List in Python
//
//1. **Sort a List of Numbers:**
//   ```python
//   numbers = [5, 2, 9, 1, 3]
//   numbers.sort()
//   print(numbers)
//""")
//        ),
    ]
    var error: HFError?
    
    // Tools
    var imageURL: String?
    
    // Context
    var contextAppName: String?
    var contextAppSelectedText: String?
    var contextAppFullText: String?
    var contextAppIcon: NSImage?
    var contextIsSupported: Bool = false
    
    // Local model support
    var selectedLocalModel: String {
        get {
            access(keyPath: \.selectedLocalModel)
            return UserDefaults.standard.string(forKey: "localModel") ?? "None"
        }
        set {
            withMutation(keyPath: \.selectedLocalModel) {
                UserDefaults.standard.setValue(newValue, forKey: "localModel")
            }
        }
    }
    
    var isLocalGeneration: Bool {
        get {
            access(keyPath: \.isLocalGeneration)
            return UserDefaults.standard.bool(forKey: "isLocalGeneration")
        }
        set {
            withMutation(keyPath: \.isLocalGeneration) {
                UserDefaults.standard.setValue(newValue, forKey: "isLocalGeneration")
                // When local generation changes, update storage mode accordingly
                if newValue {
                    storageManager.storageMode = .local
                }
            }
        }
    }
    
    // Currently the best way to get @AppStorage value while returning observability
    var useWebService: Bool {
        get {
            access(keyPath: \.useWebService)
            return UserDefaults.standard.bool(forKey: "useWebSearch")
        }
        set {
            withMutation(keyPath: \.useWebService) {
                UserDefaults.standard.setValue(newValue, forKey: "useWebSearch")
            }
        }
    }
    
    var useContext: Bool {
        get {
            access(keyPath: \.useContext)
            return UserDefaults.standard.bool(forKey: "useContext")
        }
        set {
            withMutation(keyPath: \.useContext) {
                UserDefaults.standard.setValue(newValue, forKey: "useContext")
            }
        }
    }
    
    var externalModel: String {
        get {
            access(keyPath: \.externalModel)
            return UserDefaults.standard.string(forKey: "externalModel") ?? "meta-llama/Meta-Llama-3.1-70B-Instruct"
        }
        set {
            withMutation(keyPath: \.externalModel) {
                UserDefaults.standard.setValue(newValue, forKey: "externalModel")
            }
        }
    }

    private var cancellables = [AnyCancellable]()
    private var sendPromptHandler: SendPromptHandler?
    private let storageManager = ConversationStorageManager.shared
    
    // We'll need to inject ModelManager through the environment
    private var modelManager: ModelManager?
    
    private(set) var conversation: Conversation? {
        didSet {
            guard let conversation = conversation else { return }
            // Only set HF session if using HuggingFace storage
            if storageManager.storageMode != .local {
                HuggingChatSession.shared.currentConversation = conversation.serverId
            }
        }
    }
    
    var state: ConversationState = .none
    
    func loadConversation(_ conversation: Conversation) {
        self.conversation = conversation
        // Only set HF session if using HuggingFace storage
        if storageManager.storageMode != .local {
            HuggingChatSession.shared.currentConversation = conversation.serverId
        }
        loadHistory()
    }
    
    private func loadHistory() {
        guard let conversation = conversation else { return }
        state = .loading
        
        Task {
            do {
                let loadedConversation = try await storageManager.loadConversation(id: conversation.serverId)
                
                await MainActor.run {
                    self.conversation = loadedConversation
                    self.messages = self.buildHistory(conversation: loadedConversation)
                    self.state = .loaded
                }
            } catch {
                await MainActor.run {
                    print("Error loading conversation: \(error.localizedDescription)")
                    self.state = .error
                    self.error = .verbose("Failed to load conversation")
                }
            }
        }
    }
    
    private func createConversationAndSendPrompt(_ prompt: String, withFiles: [String]? = nil, usingTools: [String]? = nil) {
        // Ensure we have the correct model based on local generation setting
        if model == nil {
            getActiveModel()
        }
        
        // For local generation mode, ensure we're using a local model
        if isLocalGeneration {
            // Ensure storage mode is local
            if storageManager.storageMode != .local {
                storageManager.storageMode = .local
            }
            
            guard selectedLocalModel != "None" else {
                state = .error
                error = .verbose("Please select a local model in Settings to create conversations.")
                return
            }
            
            // Ensure we have a local model loaded
            if model == nil || !(model is LLMModel) {
                getLocalModel()
            }
        }
        
        if let model = model as? LLMModel {
            createConversation(with: model, prompt: prompt, withFiles: withFiles, usingTools: usingTools)
        } else {
            state = .error
            error = .verbose("No suitable model available. Please check your settings.")
        }
    }
    
    private func createConversation(with model: LLMModel, prompt: String, withFiles: [String]? = nil, usingTools: [String]? = nil) {
        state = .loaded
        
        Task {
            do {
                let conversation = try await storageManager.createConversation(
                    title: String(prompt.prefix(50)), // Use first 50 chars as title
                    model: model
                )
                
                await MainActor.run {
                    self.conversation = conversation
                    self.sendAttributed(text: prompt, withFiles: withFiles)
                }
            } catch {
                await MainActor.run {
                    print("ConversationViewModel.createConversation failed:\n\(error)")
                    self.state = .error
                    
                    if storageManager.requiresAuthentication {
                        self.error = .verbose("Please log in to create conversations.")
                    } else {
                        self.error = .verbose("Failed to create conversation. Please try again.")
                    }
                }
            }
        }
    }
    
    func sendAttributed(text: String, withFiles: [String]? = nil) {
        guard let conversation = conversation, let previousId = conversation.messages.last?.id else {
            createConversationAndSendPrompt(text, withFiles: withFiles, usingTools: isTools ? []:nil)
            return
        }
        var trimmedText = ""
        if useContext {
            if let contextAppSelectedText = contextAppSelectedText {
                trimmedText += "Selected Text: ```\(contextAppSelectedText)```"
            }
            if let contextAppFullText = contextAppFullText {
                // TODO: Truncate full context if needed
                trimmedText += "\n\nFull Text:```\(contextAppFullText)```"
            }
        }
        
        trimmedText += text.trimmingCharacters(in: .whitespaces)
        
        // TODO: Add files here
        let userMessage = MessageRow(type: .user, isInteracting: false, contentType: .rawText(trimmedText))
        messages.append(userMessage)
        
        let req = PromptRequestBody(id: previousId, inputs: trimmedText, webSearch: useWebService, files: withFiles, tools: isTools ?  ["000000000000000000000001", "000000000000000000000002", "00000000000000000000000a"] : nil)
        sendPromptRequest(req: req, conversationID: conversation.serverId)
    }
    
    func sendTranscript(text: String) {
        guard let conversation = conversation, let previousId = conversation.messages.last?.id else {
            createConversationAndSendPrompt(text, withFiles: nil, usingTools: nil)
            return
        }
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let req = PromptRequestBody(id: previousId, inputs: trimmedText, webSearch: useWebService, files: nil, tools: nil)
        sendPromptRequest(req: req, conversationID: conversation.serverId)
    }
    
    private func sendPromptRequest(req: PromptRequestBody, conversationID: String) {
        // Check if we should use local generation
        if isLocalGeneration {
            sendLocalPromptRequest(prompt: req.inputs ?? "", conversationID: conversationID)
        } else {
            sendRemotePromptRequest(req: req, conversationID: conversationID)
        }
    }
    
    private func sendLocalPromptRequest(prompt: String, conversationID: String) {
        state = .generating
        isInteracting = true
        imageURL = nil
        
        // Create assistant message placeholder
        let messageRow = MessageRow(type: .assistant, isInteracting: true, contentType: .rawText(""))
        messages.append(messageRow)
        
        guard let modelManager = getModelManager() else {
            state = .error
            error = .verbose("Model manager not available.")
            return
        }
        
        Task {
            // Generate response using local model
            await modelManager.generate(prompt: prompt)
            
            // Wait for generation to complete and update UI
            await MainActor.run {
                // Update the assistant message with the generated content
                if let lastIndex = self.messages.lastIndex(where: { $0.type == .assistant && $0.isInteracting }) {
                    let updatedMessage = MessageRow(
                        type: .assistant,
                        isInteracting: false,
                        contentType: .rawText(modelManager.outputText)
                    )
                    self.messages[lastIndex] = updatedMessage
                }
                
                // Complete the interaction
                self.completeInteration()
            }
        }
    }
    
    private func sendRemotePromptRequest(req: PromptRequestBody, conversationID: String) {
        state = .generating
        isInteracting = true
        imageURL = nil
        let sendPromptHandler = SendPromptHandler(conversationId: conversationID)
        self.sendPromptHandler = sendPromptHandler
        let messageRow = sendPromptHandler.messageRow
        messages.append(messageRow)
        
        let pub = sendPromptHandler.update
            .receive(on: RunLoop.main).eraseToAnyPublisher()

        pub.scan((0, messageRow)) { (tuple, newMessage) in
            (tuple.0 + 1, newMessage)
        }.eraseToAnyPublisher()
            .sink { [weak self] completion in
                guard let self else { return }
                switch completion {
                case .finished:
                    self.sendPromptHandler = nil
                    isInteracting = false
                    self.sendPromptHandler = nil
                    state = .loaded
                case .failure(let error):
                    switch error {
                    case .httpTooManyRequest:
                        self.messages.removeLast(2)
                        self.state = .error
                        self.error = .verbose("You've sent too many requests. Please try logging in before sending a message.")
                        print(error.localizedDescription)
                    default:
                        self.state = .error
                        self.error = error
                        print(error.localizedDescription)
                    }
                }
            } receiveValue: { [weak self] obj in
                guard let self else { return }
                let (count, messageRow) = obj
                
                if count == 1 {
                    self.updateConversation(conversationID: conversationID)
                }
                
                self.message = messageRow
                print(messageRow)
                if let lastIndex = self.messages.lastIndex(where: { $0.id == messageRow.id }) {
                    self.messages[lastIndex] = messageRow
                }

                if let fileInfo = self.message?.fileInfo,
                   fileInfo.mime.hasPrefix("image/"),
                   let conversationID = self.conversation?.id {
                    self.imageURL = "https://huggingface.co/chat/conversation/\(conversationID)/output/\(fileInfo.sha)"
                }
                
            }.store(in: &cancellables)

        sendPromptHandler.sendPromptReq(reqBody: req)
    }
    
    private func updateConversation(conversationID: String) {
        NetworkService.getConversation(id: conversationID).sink { completion in
            switch completion {
            case .finished:
                print("ConversationViewModel.updateConversation finished")
            case .failure(let error):
                self.state = .error
                self.error = .verbose("Uh oh, something's not right! Please check your connection and try again later.")
                print(error.localizedDescription)
            }
        } receiveValue: { [weak self] conversation in
            self?.conversation = conversation
        }.store(in: &cancellables)
    }
    
    func getActiveModel() {
        // Priority: isLocalGeneration setting overrides storage mode
        if isLocalGeneration {
            // Force local mode when local generation is enabled
            if storageManager.storageMode != .local {
                storageManager.storageMode = .local
            }
            getLocalModel()
        } else {
            // Use storage mode to determine model source
            switch storageManager.storageMode {
            case .local:
                getLocalModel()
                
            case .huggingface, .hybrid:
                getHuggingFaceModel()
            }
        }
    }
    
    private func getLocalModel() {
        guard selectedLocalModel != "None" else {
            self.state = .error
            self.error = .verbose("Please select a local model in Settings.")
            return
        }
        
        // Find the local model from ModelManager
        guard let modelManager = getModelManager() else {
            self.state = .error
            self.error = .verbose("Model manager not available. Please restart the application.")
            return
        }
        
        guard let localModel = modelManager.availableModels.first(where: { $0.displayName == selectedLocalModel }) else {
            self.state = .error
            self.error = .verbose("Selected local model '\(selectedLocalModel)' not found.")
            return
        }
        
        guard localModel.downloadState == .downloaded else {
            self.state = .error
            self.error = .verbose("Local model '\(selectedLocalModel)' is not downloaded.")
            return
        }
        
        // Create a pseudo LLMModel for local model compatibility
        let localLLMModel = createLocalLLMModel(from: localModel)
        
        DispatchQueue.main.async {
            self.model = localLLMModel
            self.externalModel = localLLMModel.name
            self.isMultimodal = localLLMModel.multimodal
            self.isTools = localLLMModel.tools
        }
    }
    
    private func getHuggingFaceModel() {
        DataService.shared.getActiveModel().receive(on: DispatchQueue.main).sink { completion in
            switch completion {
            case .finished:
                print("ConversationViewModel.getActiveModel finished")
            case .failure(let error):
                self.state = .error
                if self.storageManager.storageMode == .huggingface {
                    self.error = .verbose("Please log in to use HuggingFace models.")
                } else {
                    self.error = .verbose("Failed to get HuggingFace model. Using local mode only.")
                    // Fallback to local model in hybrid mode
                    self.getLocalModel()
                }
                print("ConversationViewModel.getActiveModel failed:\n \(error)")
            }
        } receiveValue: { [weak self] model in
            self?.model = model
            self?.externalModel = (model as! LLMModel).name
            self?.isMultimodal = (model as! LLMModel).multimodal
            self?.isTools = (model as! LLMModel).tools
        }.store(in: &cancellables)
    }
    
    private func createLocalLLMModel(from localModel: LocalModel) -> LLMModel {
        // Create a pseudo LLMModel that represents the local model
        return LLMModel(
            id: localModel.id,
            name: localModel.displayName,
            displayName: localModel.displayName,
            websiteUrl: URL(string: localModel.hfURL ?? "https://huggingface.co/\(localModel.displayName)")!,
            modelUrl: URL(string: localModel.hfURL ?? "https://huggingface.co/\(localModel.displayName)")!,
            promptExamples: [],
            multimodal: false, // Local models typically don't support multimodal
            unlisted: false,
            description: "Local LLM Model",
            isActive: true,
            preprompt: "",
            tools: false // Local models typically don't support tools
        )
    }
    
    private func buildHistory(conversation: Conversation) -> [MessageRow] {
        let messages = conversation.messages.compactMap({ (message: Message) -> MessageRow? in
           return MessageRow(message: message)
        })
//        let historyParser = HistoryParser(isDarkMode: isDarkMode)
//        messages = historyParser.parseMessages(messages: messages)
        return messages
    }
    
    func reset() {
        state = .empty
        getActiveModel()
        cancellables = []
        conversation = nil
        error = nil
        isInteracting = false
        HuggingChatSession.shared.currentConversation = ""
        clearContext()
    }
    
    func stopGenerating() {
        cancellables = []
        sendPromptHandler?.cancel()
        completeInteration()
    }
    
    private func completeInteration() {
        isInteracting = false
        sendPromptHandler = nil
        state = .loaded
        error = nil
    }
    
    // MARK: Context Functions
    func fetchContext() {
        self.contextAppName = nil
        self.contextAppSelectedText = nil
        self.contextAppFullText = nil
        self.contextAppIcon = nil
        self.contextIsSupported = false
        Task {
            if let content = await AccessibilityContentReader.shared.getActiveEditorContent() {
                await MainActor.run {
                    self.contextIsSupported = content.isSupported
                    self.contextAppName = content.applicationName
                    self.contextAppIcon = content.applicationIcon
                    if self.contextIsSupported {
                        self.contextAppSelectedText = content.selectedText
                        self.contextAppFullText = content.fullText
                    }
                }
            }
        }
    }
    
    func formatContext() {
        // TODO: Truncate contextAppFullText from start to 3000 characters.
        
    }
    
    func clearContext() {
        contextAppName = nil
        contextAppSelectedText = nil
        contextAppFullText = nil
    }
    
}

// MARK: - Environment Setup
    
extension ConversationViewModel {
    func setModelManager(_ modelManager: ModelManager) {
        self.modelManager = modelManager
    }
    
    private func getModelManager() -> ModelManager? {
        return modelManager
    }
    
    // MARK: - Conversation Management
}
