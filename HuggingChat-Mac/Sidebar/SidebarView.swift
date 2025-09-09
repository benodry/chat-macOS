//
//  SidebarView.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 1/21/25.
//

import SwiftUI
import Nuke
import NukeUI
import ChatCore

struct SidebarView: View {
    @Environment(CoordinatorModel.self) private var coordinator
    @Environment(ProviderRuntime.self) private var runtime
    @State private var searchChat: String = ""
    @State private var providerFilter: ProviderKind? = nil
    @State private var renamingConversation: ChatConversation? = nil
    @State private var renameDraft: String = ""
    @State private var showingRenameSheet: Bool = false
    @State private var showingConfirmation = false
    @Binding var showShareSheet: Bool
    @AppStorage(UserDefaultsKeys.baseURL) var baseURL: String = "https://huggingface.co"
    
    var body: some View {
        VStack(spacing: 0) {
            @Bindable var coordinator = coordinator
            List {
                Section {
                    HStack(spacing: 8) {
                        providerBadge(for: .huggingFace)
                        providerBadge(for: .openAI)
                        providerBadge(for: .gemini)
                        providerBadge(for: .bedrock)
                        providerBadge(for: .local)
                        Spacer()
                        if runtime.providerKind != .huggingFace {
                            Toggle(isOn: $runtime.includeHFInNonHFMode) { Text("Show HF") }
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .help("Include mirrored Hugging Face conversations in list")
                        }
                        Menu {
                            Button("All", action: { providerFilter = nil })
                            Divider()
                            ForEach([ProviderKind.huggingFace, .openAI, .gemini, .bedrock, .local], id: \.self) { kind in
                                Button(kind.rawValue) { providerFilter = kind }
                            }
                            if providerFilter != nil { Button("Clear Filter") { providerFilter = nil } }
                        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                        .help("Filter by provider kind")
                    }
                    .font(.caption)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                Section {
                    ForEach(filteredConversations(), id: \.id) { convo in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(convo.title.isEmpty ? "(untitled)" : convo.title.withoutEmoji())
                                    .lineLimit(1)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    providerBadge(for: convo.provider)
                                    capabilityBadges(for: convo)
                                    Text(convo.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if runtime.selectedLocalConversationId == convo.id || (runtime.providerKind == .huggingFace && coordinator.selectedConversation == convo.id) {
                                Image(systemName: "chevron.right.circle.fill").imageScale(.small).foregroundStyle(.accent)
                            }
                        }
                        .padding(.leading, 4)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .background {
                            if runtime.providerKind == .huggingFace {
                                if coordinator.selectedConversation == convo.id {
                                    RoundedRectangle(cornerRadius: 8).fill(.quinary)
                                }
                            } else if runtime.selectedLocalConversationId == convo.id {
                                RoundedRectangle(cornerRadius: 8).fill(.quinary)
                            }
                        }
                        .onTapGesture { selectConversation(convo) }
                        .contextMenu { contextMenu(for: convo) }
                        .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 0, trailing: -4))
                    }
                } header: {
                    Text("Chats")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listStyle(.sidebar)
            
            
            // Profile Menu
            Menu {
                if let email = coordinator.currentUser?.email, !email.isEmpty {
                    Button {
                    } label: {
                        Text(verbatim: email)
                    }
                    .disabled(true)
                    Divider()
                }
                
                Button {
                    // TODO: Open settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Divider()
                Button {
                    coordinator.logout()
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.forward")
                }
            } label: {
                HStack {
                    if let avatarURL = coordinator.currentUser?.avatarUrl, let url = URL(string: avatarURL.absoluteString) {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else if state.error != nil {
                                DefaultAvatarView()
                            } else {
                                LoadingAvatarView()
                            }
                        }
                    } else {
                        DefaultAvatarView()
                    }

                    Text(coordinator.currentUser?.username ?? "User")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.highlightOnPress)
            .frame(height: 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .buttonStyle(.plain)
            
        }
        .searchable(text: $searchChat, placement: .sidebar)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    coordinator.resetConversation()
                    
                }, label: {
                    Image(systemName: "square.and.pencil")
                })
                if runtime.providerKind != .huggingFace {
                    Button(action: { if !runtime.isStreaming { runtime.createLocalConversationIfNeeded(); } }) { Image(systemName: "plus") }
                        .help(runtime.isStreaming ? "Finish streaming before starting a new chat" : "New Local Conversation")
                        .disabled(runtime.isStreaming)
                }
                Button(action: {
                    if runtime.providerKind == .huggingFace {
                        runtime.mirrorHFConversations(force: true)
                        coordinator.fetchConversations()
                    } else {
                        runtime.refreshLocalConversations()
                    }
                }, label: { Image(systemName: "arrow.clockwise") })
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Conversation").font(.headline)
                TextField("Title", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename() }
                HStack {
                    Spacer()
                    Button("Cancel") { showingRenameSheet = false }
                    Button("Save") { commitRename() }.disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 360)
        }
        .confirmationDialog("Delete Chat", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let selectedConversation = coordinator.selectedConversation, let conversation = coordinator.conversations.first(where: { $0.id == selectedConversation }) {
                    coordinator.deleteConversation(id: conversation.serverId)
                    coordinator.selectedConversation = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }
    @ViewBuilder private func capabilityBadges(for convo: ChatConversation) -> some View {
        // Derive capabilities heuristically: look at provider kind defaults.
        let caps: ProviderCapabilities = {
            switch convo.provider {
            case .huggingFace: return .init(supportsTools: false, supportsReasoning: true, supportsStreaming: true, maxContextTokens: nil)
            case .openAI: return .basicStreaming
            case .gemini: return .init(supportsTools: false, supportsReasoning: true, supportsStreaming: true, maxContextTokens: nil)
            case .bedrock: return .init(supportsTools: false, supportsReasoning: false, supportsStreaming: true, maxContextTokens: nil)
            case .local: return .basicStreaming
            }
        }()
        HStack(spacing: 2) {
            if caps.supportsReasoning { smallCap("R", .purple) }
            if caps.supportsTools { smallCap("T", .teal) }
            if caps.supportsStreaming { smallCap("S", .green) }
        }
    }
    private func smallCap(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold().padding(.horizontal, 3).background(color.opacity(0.15)).foregroundStyle(color).clipShape(RoundedRectangle(cornerRadius: 3))
    }
    private func filteredConversations() -> [ChatConversation] {
        let base = runtime.unifiedConversations()
        let byProvider = providerFilter == nil ? base : base.filter { $0.provider == providerFilter }
        if searchChat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return byProvider }
        let q = searchChat.lowercased()
        return byProvider.filter { $0.title.lowercased().contains(q) || $0.modelId.lowercased().contains(q) }
    }
    
    private func selectConversation(_ convo: ChatConversation) {
        if convo.provider == .huggingFace {
            // Use legacy coordinator path for now
            if coordinator.conversations.first(where: { $0.serverId == convo.remoteId }) == nil {
                // Trigger a refresh of HF conversations if missing (legacy fetch already populates)
                coordinator.fetchConversations()
            }
            if let match = coordinator.conversations.first(where: { $0.serverId == convo.remoteId }) {
                coordinator.selectedConversation = match.id
                coordinator.loadConversationHistory()
            }
        } else {
            runtime.selectLocalConversation(convo)
        }
    }
    @ViewBuilder private func providerBadge(for kind: ProviderKind) -> some View {
        switch kind {
        case .huggingFace: badgeLabel("HF", color: .orange)
        case .openAI: badgeLabel("OAI", color: .blue)
        case .gemini: badgeLabel("G", color: .purple)
        case .bedrock: badgeLabel("BR", color: .green)
        case .local: badgeLabel("LOC", color: .gray)
        }
    }
    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    @ViewBuilder private func contextMenu(for convo: ChatConversation) -> some View {
        if convo.provider == .huggingFace {
            if let remoteId = convo.remoteId {
                Link(destination: URL(string: "\(baseURL)/chat/conversation/" + remoteId)!, label: { Label("Open in Browser", systemImage: "globe") })
            }
        } else {
            Button { startRename(convo) } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { runtime.deleteLocalConversation(id: convo.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
    private func startRename(_ convo: ChatConversation) {
        renamingConversation = convo
        renameDraft = convo.title
        showingRenameSheet = true
    }
    private func commitRename() {
        guard let convo = renamingConversation else { return }
        let newTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty { runtime.renameLocalConversation(id: convo.id, newTitle: newTitle) }
        showingRenameSheet = false
        renamingConversation = nil
    }
}

// Extracted views for better organization
private struct DefaultAvatarView: View {
    var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(.quinary)
                .frame(width: 28, height: 28)
            Text("🤗")
        }
    }
}

private struct LoadingAvatarView: View {
    var body: some View {
        ZStack {
            Color.secondary
            ProgressView()
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }
}

//#Preview { /* Preview disabled due to new environment dependencies */ }
