import SwiftUI
import ChatCore
import Combine

/// Simple environment model to hold active provider + engine.
@Observable class ProviderRuntime {
    var providerKind: ProviderKind = {
        if let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeProvider), let kind = ProviderKind(rawValue: raw) { return kind }
        return .huggingFace
    }() {
        didSet { UserDefaults.standard.set(providerKind.rawValue, forKey: UserDefaultsKeys.activeProvider) }
    }
    var engine: ChatEngine?
    var modelInfo: ModelInfo? {
        didSet {
            switch providerKind {
            case .openAI:
                guard let modelInfo else { return }
                UserDefaults.standard.set(modelInfo.modelId, forKey: "openai_selected_model")
            case .gemini:
                guard let modelInfo else { return }
                UserDefaults.standard.set(modelInfo.modelId, forKey: "gemini_selected_model")
            case .bedrock:
                guard let modelInfo else { return }
                UserDefaults.standard.set(modelInfo.modelId, forKey: "bedrock_selected_model")
            default:
                break
            }
        }
    }
    var store: ConversationStore?
    // Local conversations (non-HF) cached in memory
    var localConversations: [ChatConversation] = []
    // Mirrored (read-only) HF conversations (metadata + messages as fetched)
    var hfConversations: [ChatConversation] = []
    // When using a non-HF provider, optionally include HF mirror in sidebar
    var includeHFInNonHFMode: Bool = false
    private var lastHFRefresh: Date?
    private var hfRefreshTimer: AnyCancellable?
    var selectedLocalConversationId: UUID?
    // Streaming assistant interim content
    var streamingAssistantContent: String = ""
    var isStreaming: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    func configureInitial() {
        if store == nil {
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let root = appSupport.appendingPathComponent("ChatMac/Conversations", isDirectory: true)
                store = try? JSONConversationStore(rootDirectory: root)
            }
        }
    rebuildProvider()
        loadPersistedModel()
        refreshLocalConversations()
    mirrorHFConversations(force: true)
    }
    
    func rebuildProvider() {
        switch providerKind {
        case .huggingFace:
            let provider = HuggingFaceProvider(conversationStore: store)
            engine = ChatEngine(provider: provider, store: store)
            selectedLocalConversationId = nil
            schedulePeriodicHFRefresh()
        case .openAI:
            guard let key = UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIAPIKey), !key.isEmpty else { engine = nil; return }
            let base = URL(string: UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIBaseURL) ?? "https://api.openai.com/")!
            let modelId = (modelInfo?.modelId) ?? UserDefaults.standard.string(forKey: "openai_selected_model") ?? "gpt-4o-mini"
            let provider = OpenAICompatibleProvider(configuration: .init(baseURL: base, apiKey: key, defaultModel: modelId))
            engine = ChatEngine(provider: provider, store: store)
            cancelHFRefreshTimer()
        case .gemini:
            guard let key = UserDefaults.standard.string(forKey: UserDefaultsKeys.geminiAPIKey), !key.isEmpty else { engine = nil; return }
            let modelId = (modelInfo?.modelId) ?? UserDefaults.standard.string(forKey: "gemini_selected_model") ?? "gemini-1.5-flash"
            let provider = GeminiProvider(configuration: .init(apiKey: key, defaultModel: modelId))
            engine = ChatEngine(provider: provider, store: store)
            cancelHFRefreshTimer()
        case .bedrock:
            guard let accessKey = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockAccessKey), !accessKey.isEmpty,
                  let secretKey = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockSecretKey), !secretKey.isEmpty else { engine = nil; return }
            let region = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockRegion) ?? "us-east-1"
            let modelId = (modelInfo?.modelId) ?? UserDefaults.standard.string(forKey: "bedrock_selected_model") ?? "anthropic.claude-3-5-sonnet-20241022-v2:0"
            let provider = BedrockProvider(configuration: .init(accessKeyId: accessKey, secretAccessKey: secretKey, region: region, defaultModel: modelId))
            engine = ChatEngine(provider: provider, store: store)
            cancelHFRefreshTimer()
        default:
            // Future providers
            engine = nil
            cancelHFRefreshTimer()
        }
    }
    func refreshLocalConversations() {
        guard providerKind != .huggingFace, let store else { localConversations = []; return }
        localConversations = (try? store.loadAll().filter { $0.provider == providerKind }) ?? []
        // Reselect if still present
        if let sel = selectedLocalConversationId, !localConversations.contains(where: { $0.id == sel }) {
            selectedLocalConversationId = nil
        }
    }
    /// Refresh Hugging Face remote conversations into memory (read-only mirror)
    /// Mirror HF remote conversations. Uses diffing to minimize UI churn.
    func mirrorHFConversations(force: Bool = false) {
        let now = Date()
        if !force, let last = lastHFRefresh, now.timeIntervalSince(last) < 30 { return } // throttle
        lastHFRefresh = now
        NetworkService.getConversations()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let err) = completion { print("HF mirror error: \(err)") }
            }, receiveValue: { [weak self] convos in
                guard let self else { return }
                let adapted = convos.toChatConversations(provider: .huggingFace)
                // Diff by remoteId
                var existingByRemote: [String: ChatConversation] = [:]
                for c in hfConversations { if let rid = c.remoteId { existingByRemote[rid] = c } }
                var merged: [ChatConversation] = []
                for c in adapted {
                    if let rid = c.remoteId, var existing = existingByRemote[rid] {
                        // Update mutable fields (title, updatedAt, messages count maybe)
                        existing.title = c.title
                        existing.updatedAt = c.updatedAt
                        existing.messages = c.messages
                        merged.append(existing)
                        existingByRemote.removeValue(forKey: rid)
                    } else {
                        merged.append(c)
                    }
                }
                self.hfConversations = merged.sorted { $0.updatedAt > $1.updatedAt }
            })
            .store(in: &cancellables)
    }
    private func schedulePeriodicHFRefresh() {
        cancelHFRefreshTimer()
        hfRefreshTimer = Timer.publish(every: 90, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.mirrorHFConversations() }
    }
    private func cancelHFRefreshTimer() { hfRefreshTimer?.cancel(); hfRefreshTimer = nil }
    /// Unified list for sidebar (HF + current provider local) depending on active provider
    func unifiedConversations() -> [ChatConversation] {
        if providerKind == .huggingFace { return hfConversations }
        if includeHFInNonHFMode {
            let combined = localConversations + hfConversations
            return combined.sorted { $0.updatedAt > $1.updatedAt }
        }
        return localConversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    /// Create a new local conversation for current non-HF provider
    func createLocalConversationIfNeeded(initialUserMessage: String? = nil) {
        guard providerKind != .huggingFace, let store, let engine else { return }
    let title = initialUserMessage.map { TitleHeuristics.title(from: $0) } ?? "New Chat"
        let convo = ChatConversation(
            id: UUID(),
            remoteId: nil,
            provider: providerKind,
            modelId: modelInfo?.modelId ?? "unknown",
            title: title,
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )
        do { try store.create(convo); refreshLocalConversations(); selectLocalConversation(convo) } catch { print("Failed to create local conversation: \(error)") }
    }
    /// Rename local conversation (persist)
    func renameLocalConversation(id: UUID, newTitle: String) {
        guard let store else { return }
        guard let idx = localConversations.firstIndex(where: { $0.id == id }) else { return }
        var convo = localConversations[idx]
        convo.title = newTitle
        convo.updatedAt = Date()
        do { try store.save(convo); refreshLocalConversations() } catch { print("Rename failed: \(error)") }
    }
    /// Delete local conversation
    func deleteLocalConversation(id: UUID) {
        guard let store else { return }
        do { try store.delete(id: id); refreshLocalConversations(); if selectedLocalConversationId == id { selectedLocalConversationId = nil } } catch { print("Delete failed: \(error)") }
    }
    func selectLocalConversation(_ convo: ChatConversation) {
        selectedLocalConversationId = convo.id
        engine?.loadConversation(convo)
    }
    func loadPersistedModel() {
        switch providerKind {
        case .openAI:
            if modelInfo == nil, let saved = UserDefaults.standard.string(forKey: "openai_selected_model") {
                modelInfo = ModelInfo(modelId: saved, displayName: saved, provider: .openAI, capabilities: ProviderCapabilities.basicStreaming)
            }
        case .gemini:
            if modelInfo == nil, let saved = UserDefaults.standard.string(forKey: "gemini_selected_model") {
                modelInfo = ModelInfo(modelId: saved, displayName: saved, provider: .gemini, capabilities: ProviderCapabilities(supportsTools: true, supportsReasoning: true, supportsStreaming: true, maxContextTokens: 1_048_576))
            }
        case .bedrock:
            if modelInfo == nil, let saved = UserDefaults.standard.string(forKey: "bedrock_selected_model") {
                modelInfo = ModelInfo(modelId: saved, displayName: saved, provider: .bedrock, capabilities: ProviderCapabilities(supportsTools: true, supportsReasoning: true, supportsStreaming: true, maxContextTokens: 200_000))
            }
        default:
            break
        }
    }
    // MARK: - Export / Import (stubs)
    func exportLocalConversations(to url: URL) throws {
        guard let store else { return }
        let all = try store.loadAll().filter { $0.provider != .huggingFace }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(all)
        try data.write(to: url, options: .atomic)
    }
    func importLocalConversations(from url: URL) throws {
        guard let store else { return }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let imported = try decoder.decode([ChatConversation].self, from: data)
        for convo in imported { try? store.create(convo) }
        refreshLocalConversations()
    }
}

struct ProviderPickerView: View {
    @Environment(ProviderRuntime.self) private var runtime
    @State private var openAIKey: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIAPIKey) ?? ""
    @State private var openAIBase: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIBaseURL) ?? "https://api.openai.com/"
    @State private var geminiKey: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.geminiAPIKey) ?? ""
    @State private var bedrockAccessKey: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockAccessKey) ?? ""
    @State private var bedrockSecretKey: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockSecretKey) ?? ""
    @State private var bedrockRegion: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.bedrockRegion) ?? "us-east-1"
    
    var body: some View {
        Form {
            Picker("Provider", selection: $runtime.providerKind) {
                Text("HuggingFace").tag(ProviderKind.huggingFace)
                Text("OpenAI").tag(ProviderKind.openAI)
                Text("Google Gemini").tag(ProviderKind.gemini)
                Text("AWS Bedrock").tag(ProviderKind.bedrock)
            }
            .onChange(of: runtime.providerKind) { _, _ in runtime.rebuildProvider() }
            
            if runtime.providerKind == .openAI {
                TextField("Base URL", text: $openAIBase)
                SecureField("API Key", text: $openAIKey)
                if openAIKey.isEmpty { Text("Enter API key to enable OpenAI provider").foregroundStyle(.red).font(.caption) }
                Button("Save & Rebuild") {
                    UserDefaults.standard.set(openAIBase, forKey: UserDefaultsKeys.openAIBaseURL)
                    UserDefaults.standard.set(openAIKey, forKey: UserDefaultsKeys.openAIAPIKey)
                    runtime.rebuildProvider()
                    runtime.refreshLocalConversations()
                }.disabled(openAIKey.isEmpty)
            } else if runtime.providerKind == .gemini {
                SecureField("API Key", text: $geminiKey)
                Text("Get your API key from Google AI Studio").font(.caption2).foregroundStyle(.secondary)
                if geminiKey.isEmpty { Text("Enter API key to enable Gemini provider").foregroundStyle(.red).font(.caption) }
                Button("Save & Rebuild") {
                    UserDefaults.standard.set(geminiKey, forKey: UserDefaultsKeys.geminiAPIKey)
                    runtime.rebuildProvider()
                    runtime.refreshLocalConversations()
                }.disabled(geminiKey.isEmpty)
            } else if runtime.providerKind == .bedrock {
                TextField("AWS Access Key ID", text: $bedrockAccessKey)
                SecureField("AWS Secret Access Key", text: $bedrockSecretKey)
                TextField("AWS Region", text: $bedrockRegion)
                Text("Configure AWS credentials with Bedrock access").font(.caption2).foregroundStyle(.secondary)
                if bedrockAccessKey.isEmpty || bedrockSecretKey.isEmpty {
                    Text("Enter AWS credentials to enable Bedrock provider").foregroundStyle(.red).font(.caption)
                }
                Button("Save & Rebuild") {
                    UserDefaults.standard.set(bedrockAccessKey, forKey: UserDefaultsKeys.bedrockAccessKey)
                    UserDefaults.standard.set(bedrockSecretKey, forKey: UserDefaultsKeys.bedrockSecretKey)
                    UserDefaults.standard.set(bedrockRegion, forKey: UserDefaultsKeys.bedrockRegion)
                    runtime.rebuildProvider()
                    runtime.refreshLocalConversations()
                }.disabled(bedrockAccessKey.isEmpty || bedrockSecretKey.isEmpty)
            }
            
            if runtime.providerKind != .huggingFace {
                Divider()
                if !runtime.localConversations.isEmpty {
                    Text("Local Conversations").font(.subheadline).padding(.top, 4)
                    ScrollView {
                        ForEach(runtime.localConversations, id: \.id) { convo in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(convo.title.isEmpty ? "(untitled)" : convo.title).lineLimit(1)
                                    Text(convo.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if runtime.selectedLocalConversationId == convo.id { Image(systemName: "checkmark.circle.fill").imageScale(.small) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                runtime.selectLocalConversation(convo)
                            }
                            Divider()
                        }
                    }.frame(maxHeight: 140)
                }
            }
        }
        .padding()
        .frame(width: 380, height: runtime.providerKind == .huggingFace ? 120 : (runtime.providerKind == .bedrock ? 300 : 260))
        .onAppear { runtime.configureInitial() }
    }
}