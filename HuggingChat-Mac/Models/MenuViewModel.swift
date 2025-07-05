//
//  MenuViewModel.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 12/17/24.
//

import SwiftUI
import Combine

enum GroupedConversationType {
    case section, conversation(Conversation)
}

struct GroupedConversation: Identifiable {
    var id: String {
        switch type {
        case .section:
            return "section-\(title)"
        case .conversation(let conversation):
            return "conv-\(conversation.id)"
        }
    }
    let title: String
    let type: GroupedConversationType
}

@Observable final class MenuViewModel {
    var conversations: [String: [Conversation]] = [:]
    
    private var cancellables = [AnyCancellable]()
    private let storageManager = ConversationStorageManager.shared
    
    var currentConversationId: String = ""
    
    init() {
        setupNotificationListeners()
    }
    
    private func setupNotificationListeners() {
        // Listen for new conversation creation
        NotificationCenter.default.publisher(for: .conversationCreated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("📱 MenuViewModel: Received conversation created notification, refreshing...")
                self?.getConversations()
            }
            .store(in: &cancellables)
    }

    func refreshState() {
        // Check authentication based on storage mode
        if storageManager.storageMode != .local {
            HuggingChatSession.shared.refreshLoginState()
        }
        
        // Load conversations based on storage capabilities
        if storageManager.canCreateConversations {
            self.getConversations()
        } else {
            self.conversations = [:]
        }
        
        // Set current conversation if available
        if let conversation = HuggingChatSession.shared.currentConversation {
            self.currentConversationId = conversation
        }
    }
    
    func didSelectConversation(at indexPath: IndexPath) {
//        let conv = conversations[indexPath.row]
//        guard case let .conversation(conversation) = conv.type else { return }
//        currentConversationId = conversation.id
//        internalDelegate?.reloadData()
//        
//        DispatchQueue.main.asyncAfter(deadline: .now()) {
//            self.delegate?.didSelect(conversation: conversation)
//        }
    }
    
    func deleteConversation(at indexPath: IndexPath) {
//        guard case let .conversation(conversation) = conversations[indexPath.row].type else { return }
//        conversations.remove(at: indexPath.row)
//        internalDelegate?.reloadData()
//        
//        NetworkService.deleteConversation(id: conversation.id)
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] completion in
//                    switch completion {
//                    case .finished: break
//                    case .failure(let error):
//                        self?.delegate?.showError(error: error)
//                        self?.getConversations()
//                    }
//            } receiveValue: { _ in
//                
//            }.store(in: &cancellables)
    }
    
    func editConversationTitle(at indexPath: IndexPath, title: String) {
//        guard case let .conversation(conversation) = conversations[indexPath.row].type, !title.isEmpty else { return }
//        conversation.title = title
//        internalDelegate?.reloadData()
//        
//        NetworkService.editConversationTitle(conversation: conversation)
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] completion in
//                    switch completion {
//                    case .finished: break
//                    case .failure(let error):
//                        self?.delegate?.showError(error: error)
//                        self?.getConversations()
//                    }
//            } receiveValue: { _ in
//                
//            }.store(in: &cancellables)
    }

    func getConversations() {
        Task {
            do {
                let conversations = try await storageManager.loadConversations()
                print("📱 MenuViewModel: Loaded \(conversations.count) conversations from storage")
                
                // Debug: Print each conversation details
                for (index, conversation) in conversations.enumerated() {
                    print("📱 Conversation \(index): id='\(conversation.serverId)', title='\(conversation.title)', updatedAt=\(conversation.updatedAt)")
                }
                
                let groupedConversations = MenuViewModel.groupConversationsByDates(conversations: conversations)
                print("📱 MenuViewModel: Grouped into \(groupedConversations.count) sections")
                
                // Debug: Print grouped sections
                for (section, convs) in groupedConversations {
                    print("📱 Section '\(section)': \(convs.count) conversations")
                }
                
                await MainActor.run {
                    if !groupedConversations.isEmpty {
                        self.conversations = groupedConversations
                        print("📱 MenuViewModel: Updated UI with \(groupedConversations.count) sections")
                    } else {
                        print("📱 MenuViewModel: No grouped conversations to display")
                    }
                }
            } catch {
                print("❌ MenuViewModel: Error loading conversations: \(error.localizedDescription)")
                
                await MainActor.run {
                    // Clear conversations on error unless it's just auth required
                    if !storageManager.requiresAuthentication {
                        self.conversations = [:]
                    }
                }
            }
        }
    }
    
    func getConversation(withServerId id: String) -> Conversation? {
        for (_, conversations) in conversations {
            if let conversation = conversations.first(where: { $0.serverId == id }) {
                return conversation
            }
        }
        return nil
    }

    static func groupConversationsByDates(conversations: [Conversation]) -> [String: [Conversation]] {
        print("📱 Grouping \(conversations.count) conversations by dates")
        
        let date = Date()
        let calendar = Calendar.current
        
        // Get start of today
        let startOfToday = calendar.startOfDay(for: date)
        
        // Initialize the grouped dictionary
        var grouped: [String: [Conversation]] = [
            "Today": [],
            "This Week": [],
            "This Month": [],
            "Older": []
        ]
        
        for conversation in conversations {
            print("📱 Processing conversation: '\(conversation.title)' updated at \(conversation.updatedAt)")
            
            if calendar.isDate(conversation.updatedAt, inSameDayAs: date) {
                print("📱 -> Adding to Today")
                grouped["Today"]?.append(conversation)
            } else if conversation.updatedAt >= calendar.date(byAdding: .day, value: -7, to: startOfToday)! {
                print("📱 -> Adding to This Week")
                grouped["This Week"]?.append(conversation)
            } else if conversation.updatedAt >= calendar.date(byAdding: .day, value: -30, to: startOfToday)! {
                print("📱 -> Adding to This Month")
                grouped["This Month"]?.append(conversation)
            } else {
                print("📱 -> Adding to Older")
                grouped["Older"]?.append(conversation)
            }
        }
        
        // Remove empty sections
        let filtered = grouped.filter { !$0.value.isEmpty }
        print("📱 Final grouped sections: \(filtered.keys.sorted())")
        return filtered
    }
}
