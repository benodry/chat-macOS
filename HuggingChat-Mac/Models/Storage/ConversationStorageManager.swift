//
//  ConversationStorageManager.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation
import SwiftUI

/// Central storage manager that coordinates between different storage implementations
@Observable class ConversationStorageManager {
    static let shared = ConversationStorageManager()
    
    // MARK: - Properties
    
    private var currentStorage: ConversationStorageProtocol
    private let localUserManager = LocalUserManager.shared
    private var isCreatingConversation = false
    private let creationQueue = DispatchQueue(label: "com.huggingchat.conversation.creation", qos: .userInitiated)
    
    var storageMode: StorageMode {
        get { localUserManager.storageMode }
        set { 
            localUserManager.setStorageMode(newValue)
            updateStorageImplementation()
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        self.currentStorage = HybridStorageManager(storageMode: localUserManager.storageMode)
    }
    
    // MARK: - Storage Implementation Management
    
    private func updateStorageImplementation() {
        currentStorage = HybridStorageManager(storageMode: storageMode)
        print("📦 Storage implementation updated to: \(storageMode.displayName)")
    }
    
    // MARK: - Public API
    
    func createConversation(title: String, model: LLMModel) async throws -> Conversation {
        // Ensure that only one conversation can be created at a time
        if isCreatingConversation {
            print("⚠️ Conversation creation already in progress, rejecting duplicate request")
            throw StorageError.invalidData
        }
        
        isCreatingConversation = true
        
        defer {
            // Allow new conversation creations after the current one is finished
            isCreatingConversation = false
        }
        
        let conversation = try await currentStorage.createConversation(title: title, model: model)
        
        // Post notification that a new conversation was created
        NotificationCenter.default.post(name: .conversationCreated, object: conversation)
        
        return conversation
    }
    
    func loadConversations() async throws -> [Conversation] {
        return try await currentStorage.loadConversations()
    }
    
    func loadConversation(id: String) async throws -> Conversation {
        return try await currentStorage.loadConversation(id: id)
    }
    
    func saveMessage(_ message: MessageRow, to conversationId: String) async throws {
        try await currentStorage.saveMessage(message, to: conversationId)
    }
    
    func deleteConversation(id: String) async throws {
        try await currentStorage.deleteConversation(id: id)
    }
    
    func updateConversationTitle(id: String, title: String) async throws {
        try await currentStorage.updateConversationTitle(id: id, title: title)
    }
    
    // MARK: - Utility Methods
    
    var canCreateConversations: Bool {
        switch storageMode {
        case .local, .hybrid:
            return true
        case .huggingface:
            return HuggingChatSession.shared.currentUser != nil
        }
    }
    
    var requiresAuthentication: Bool {
        return storageMode == .huggingface && HuggingChatSession.shared.currentUser == nil
    }
    
    var statusMessage: String {
        switch storageMode {
        case .local:
            return "Using local storage"
        case .huggingface:
            if HuggingChatSession.shared.currentUser != nil {
                return "Connected to HuggingFace"
            } else {
                return "HuggingFace authentication required"
            }
        case .hybrid:
            if HuggingChatSession.shared.currentUser != nil {
                return "Local storage with HuggingFace sync"
            } else {
                return "Local storage (HuggingFace sync unavailable)"
            }
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let conversationCreated = Notification.Name("conversationCreated")
}
