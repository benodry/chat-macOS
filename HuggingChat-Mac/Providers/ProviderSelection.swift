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
            guard let modelInfo, providerKind == .openAI else { return }
            UserDefaults.standard.set(modelInfo.modelId, forKey: "openai_selected_model")
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
    // Dynamic model listings cache per provider kind
    var availableModels: [ModelInfo] = []
    var isLoadingModels: Bool = false
    var modelLoadError: String?
    // Keep separate caches per provider kind if needed (currently reused single list)
    
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
            guard let key = UserDefaults.standard.string(forKey: "gemini_api_key"), !key.isEmpty else { engine = nil; return }
            let model = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash"
            let provider = GeminiProvider(configuration: .init(apiKey: key, model: model))
            engine = ChatEngine(provider: provider, store: store)
            cancelHFRefreshTimer()
            Task { await loadModelsIfNeeded(force: false) }
        case .bedrock:
            let endpointStr = UserDefaults.standard.string(forKey: "bedrock_gateway") ?? "https://bedrock-gateway.local"
            let model = UserDefaults.standard.string(forKey: "bedrock_model") ?? "anthropic.claude-3-haiku"
            guard let endpoint = URL(string: endpointStr) else { engine = nil; return }
            let provider = BedrockProvider(configuration: .init(modelId: model, endpoint: endpoint))
            engine = ChatEngine(provider: provider, store: store)
            cancelHFRefreshTimer()
            Task { await loadModelsIfNeeded(force: false) }
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
        if providerKind == .openAI, modelInfo == nil, let saved = UserDefaults.standard.string(forKey: "openai_selected_model") {
            modelInfo = ModelInfo(modelId: saved, displayName: saved, provider: .openAI, capabilities: ProviderCapabilities.basicStreaming)
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
    @MainActor
    func loadModelsIfNeeded(force: Bool) async {
    guard (providerKind == .gemini || providerKind == .bedrock), let engine else { return }
        if !force, !availableModels.isEmpty { return }
        isLoadingModels = true; modelLoadError = nil
        defer { isLoadingModels = false }
        do {
            let models = try await engineListModels()
            availableModels = models
            if providerKind == .gemini {
                if let saved = UserDefaults.standard.string(forKey: "gemini_model"), models.contains(where: { $0.modelId == saved }) {
                } else if let first = models.first { UserDefaults.standard.set(first.modelId, forKey: "gemini_model") }
            } else if providerKind == .bedrock {
                if let saved = UserDefaults.standard.string(forKey: "bedrock_model"), models.contains(where: { $0.modelId == saved }) {
                } else if let first = models.first { UserDefaults.standard.set(first.modelId, forKey: "bedrock_model") }
            }
        } catch {
            modelLoadError = String(describing: error)
        }
    }
    /// Thin pass-through until we potentially add multi-provider engine store
    func engineListModels() async throws -> [ModelInfo] {
        try await (engine?.providerListModels() ?? [])
    }
}

extension ChatEngine {
    // Internal helper to expose provider listing while keeping provider private in engine API surface.
    fileprivate func providerListModels() async throws -> [ModelInfo] { try await provider.listModels() }
}

struct ProviderPickerView: View {
    @Environment(ProviderRuntime.self) private var runtime
    @State private var openAIKey: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIAPIKey) ?? ""
    @State private var openAIBase: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.openAIBaseURL) ?? "https://api.openai.com/"
    
    var body: some View {
        Form {
            Picker("Provider", selection: $runtime.providerKind) {
                Text("HuggingFace").tag(ProviderKind.huggingFace)
                Text("OpenAI").tag(ProviderKind.openAI)
                Text("Gemini").tag(ProviderKind.gemini)
                Text("Bedrock").tag(ProviderKind.bedrock)
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
                Divider()
                if !runtime.localConversations.isEmpty {
                    Text("Local Conversations").font(.subheadline).padding(.top, 4)
                    ScrollView {
                        ForEach(runtime.localConversations, id: \..id) { convo in
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
            } else if runtime.providerKind == .gemini {
                SecureField("API Key", text: Binding(
                    get: { UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" },
                    set: { UserDefaults.standard.set($0, forKey: "gemini_api_key") }))
                if runtime.isLoadingModels {
                    ProgressView().controlSize(.small)
                } else if let err = runtime.modelLoadError {
                    Text("Model load failed: \(err)").foregroundStyle(.red).font(.caption)
                } else if !runtime.availableModels.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "gemini_model") ?? runtime.availableModels.first!.modelId },
                        set: { newVal in
                            UserDefaults.standard.set(newVal, forKey: "gemini_model")
                            runtime.rebuildProvider(); runtime.refreshLocalConversations()
                        })) {
                        ForEach(runtime.availableModels) { model in
                            HStack {
                                Text(model.displayName)
                                if model.capabilities.supportsReasoning { Text("R").font(.caption2).foregroundStyle(.blue) }
                                if model.capabilities.supportsStreaming { Text("S").font(.caption2).foregroundStyle(.green) }
                            }.tag(model.modelId)
                        }
                    }
                } else {
                    TextField("Model (fallback)", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash" },
                        set: { UserDefaults.standard.set($0, forKey: "gemini_model") }))
                }
                HStack {
                    Button("Refresh Models") { Task { await runtime.loadModelsIfNeeded(force: true) } }.disabled((UserDefaults.standard.string(forKey: "gemini_api_key") ?? "").isEmpty)
                    Button("Save & Rebuild") { runtime.rebuildProvider(); runtime.refreshLocalConversations() }
                }
            } else if runtime.providerKind == .bedrock {
                TextField("Gateway Endpoint", text: Binding(
                    get: { UserDefaults.standard.string(forKey: "bedrock_gateway") ?? "https://bedrock-gateway.local" },
                    set: { UserDefaults.standard.set($0, forKey: "bedrock_gateway") }))
                if runtime.isLoadingModels {
                    ProgressView().controlSize(.small)
                } else if let err = runtime.modelLoadError {
                    Text("Model load failed: \(err)").foregroundStyle(.red).font(.caption)
                } else if !runtime.availableModels.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "bedrock_model") ?? runtime.availableModels.first!.modelId },
                        set: { newVal in
                            UserDefaults.standard.set(newVal, forKey: "bedrock_model")
                            runtime.rebuildProvider(); runtime.refreshLocalConversations()
                        })) {
                        ForEach(runtime.availableModels) { model in
                            HStack {
                                Text(model.displayName)
                                if model.capabilities.supportsReasoning { Text("R").font(.caption2).foregroundStyle(.blue) }
                                if model.capabilities.supportsStreaming { Text("S").font(.caption2).foregroundStyle(.green) }
                            }.tag(model.modelId)
                        }
                    }
                } else {
                    TextField("Model (fallback)", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "bedrock_model") ?? "anthropic.claude-3-haiku" },
                        set: { UserDefaults.standard.set($0, forKey: "bedrock_model") }))
                }
                HStack {
                    Button("Refresh Models") { Task { await runtime.loadModelsIfNeeded(force: true) } }
                    Button("Save & Rebuild") { runtime.rebuildProvider(); runtime.refreshLocalConversations() }
                }
            }
        }
        .padding()
        .frame(width: 320, height: runtime.providerKind == .openAI ? 240 : 120)
        .onAppear { runtime.configureInitial() }
    }
}