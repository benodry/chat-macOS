//
//  InputView.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 1/21/25.
//

import SwiftUI
import ChatCore
import Combine

struct InputView: View {
    
    var cornerRadius: CGFloat = 14
    var isChatBarMode: Bool = false
    var onSubmit: (() -> Void)
    
    @Environment(CoordinatorModel.self) private var coordinator
    @Environment(\.openWindow) var openWindow
    @Environment(\.colorScheme) var colorScheme
    @State private var inputText: String = ""
    // Future injection point for new engine (non-HF providers)
    @State private var chatEngine: ChatEngine? = nil
    @Environment(ProviderRuntime.self) private var providerRuntime
    @State private var sendCancellable: AnyCancellable? = nil
    
    var body: some View {
        VStack(alignment: .leading) {
            TextField("", text: $inputText, prompt: Text("Message \(conversationModelName())").foregroundColor(.primary), axis: .vertical)
                .font(.system(size: 14.5, weight: .regular, design: .default))
                .textFieldStyle(.plain)
                .lineLimit(12)
                .frame(maxHeight: .infinity, alignment: .top)
                .onSubmit { performSend() }
            InputViewToolbar(inputText: inputText) { performToolbarSend() }
                
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(minHeight: 87)
        
        .background {
            if isChatBarMode {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThickMaterial)
                    .fill(colorScheme == .dark ? .black.opacity(0.4) : .white.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.gray.opacity(0.5), style: StrokeStyle(lineWidth: 0.5)))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.gray.opacity(0.5), lineWidth: 1)
                    .fill(.regularMaterial)
                    .fill(.quinary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    func conversationModelName() -> String {
        if let selectedConversationId = coordinator.selectedConversation, let conversation = coordinator.conversations.first(where: { $0.id == selectedConversationId }) {
            return conversation.modelId
        } else {
//            let modelName = coordinator.activeModel?.displayName.split(separator: "/").last ?? ""
//            let primaryName = modelName.split(separator: "-").first ?? ""
//            let secondaryName = modelName.components(separatedBy: primaryName).last?.trimmingCharacters(in: .whitespaces) ?? ""
            return coordinator.activeModel?.displayName ?? ""
        }
    }
    private func performSend() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if isChatBarMode { coordinator.selectedConversation = nil }
        // Placeholder: until provider selector exists, continue using CoordinatorModel
        // If runtime engine available for non-HF provider, route through it.
    if let engine = providerRuntime.engine, providerRuntime.providerKind != .huggingFace {
            let content = inputText
            Task {
                let modelInfo: ModelInfo
                if let existing = providerRuntime.modelInfo {
                    modelInfo = existing
                } else if let list = try? await engine.provider.listModels(), let first = list.first {
                    providerRuntime.modelInfo = first
                    modelInfo = first
                } else { return }
        // Ensure a local conversation exists (engine will create on first send)
        if providerRuntime.selectedLocalConversationId == nil { providerRuntime.createLocalConversationIfNeeded(initialUserMessage: content) }
                providerRuntime.isStreaming = true
                providerRuntime.streamingAssistantContent = ""
                _ = try? await engine.sendUserMessage(content, model: modelInfo, config: GenerationConfig()) { event in
                    switch event {
                    case .token(let delta):
                        providerRuntime.streamingAssistantContent += delta
                    case .completed:
                        providerRuntime.isStreaming = false
                        providerRuntime.refreshLocalConversations()
                    default: break
                    }
                }
            }
        } else {
            coordinator.send(text: inputText)
        }
        inputText = ""
        onSubmit()
        if isChatBarMode { openWindow(id: "main-window") }
    }
    private func performToolbarSend() { DispatchQueue.main.async { performSend() } }
}

#Preview {
    ContentView()
        .environmentObject(AppDelegate())
        .environment(CoordinatorModel())
}

