//
//  HybridStorageManager.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation
import Combine

/// Hybrid storage manager that combines local and remote storage
class HybridStorageManager: ConversationStorageProtocol {
    
    // MARK: - Properties
    
    private let localStorage = LocalDatabaseManager()
    private let remoteStorage = RemoteStorageManager()
    private let storageMode: StorageMode
    
    // MARK: - Initialization
    
    init(storageMode: StorageMode = .local) {
        self.storageMode = storageMode
    }
    
    // MARK: - ConversationStorageProtocol Implementation
    
    func createConversation(title: String, model: LLMModel) async throws -> Conversation {
        switch storageMode {
        case .local:
            return try await localStorage.createConversation(title: title, model: model)
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            return try await remoteStorage.createConversation(title: title, model: model)
            
        case .hybrid:
            // Create locally first, then sync to remote if authenticated
            let localConversation = try await localStorage.createConversation(title: title, model: model)
            
            if HuggingChatSession.shared.currentUser != nil {
                Task {
                    do {
                        let remoteConversation = try await remoteStorage.createConversation(title: title, model: model)
                        // TODO: Update local conversation with remote server ID for sync
                        print("🔄 Created conversation synced to HuggingFace: \(remoteConversation.serverId)")
                    } catch {
                        print("⚠️ Failed to sync conversation to HuggingFace: \(error)")
                    }
                }
            }
            
            return localConversation
        }
    }
    
    func loadConversations() async throws -> [Conversation] {
        switch storageMode {
        case .local:
            return try await localStorage.loadConversations()
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            return try await remoteStorage.loadConversations()
            
        case .hybrid:
            // Load local conversations, merge with remote if authenticated
            var conversations = try await localStorage.loadConversations()
            
            if HuggingChatSession.shared.currentUser != nil {
                do {
                    let remoteConversations = try await remoteStorage.loadConversations()
                    conversations = mergeConversations(local: conversations, remote: remoteConversations)
                } catch {
                    print("⚠️ Failed to load remote conversations: \(error)")
                    // Continue with local conversations only
                }
            }
            
            return conversations
        }
    }
    
    func loadConversation(id: String) async throws -> Conversation {
        switch storageMode {
        case .local:
            return try await localStorage.loadConversation(id: id)
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            return try await remoteStorage.loadConversation(id: id)
            
        case .hybrid:
            // Try local first, fallback to remote
            do {
                return try await localStorage.loadConversation(id: id)
            } catch {
                if HuggingChatSession.shared.currentUser != nil {
                    return try await remoteStorage.loadConversation(id: id)
                } else {
                    throw error
                }
            }
        }
    }
    
    func saveMessage(_ message: MessageRow, to conversationId: String) async throws {
        switch storageMode {
        case .local:
            try await localStorage.saveMessage(message, to: conversationId)
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            try await remoteStorage.saveMessage(message, to: conversationId)
            
        case .hybrid:
            // Save locally first
            try await localStorage.saveMessage(message, to: conversationId)
            
            // Sync to remote if authenticated
            if HuggingChatSession.shared.currentUser != nil {
                Task {
                    do {
                        try await remoteStorage.saveMessage(message, to: conversationId)
                        print("🔄 Message synced to HuggingFace")
                    } catch {
                        print("⚠️ Failed to sync message to HuggingFace: \(error)")
                    }
                }
            }
        }
    }
    
    func deleteConversation(id: String) async throws {
        switch storageMode {
        case .local:
            try await localStorage.deleteConversation(id: id)
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            try await remoteStorage.deleteConversation(id: id)
            
        case .hybrid:
            // Delete from both local and remote
            try await localStorage.deleteConversation(id: id)
            
            if HuggingChatSession.shared.currentUser != nil {
                Task {
                    do {
                        try await remoteStorage.deleteConversation(id: id)
                        print("🔄 Conversation deletion synced to HuggingFace")
                    } catch {
                        print("⚠️ Failed to sync deletion to HuggingFace: \(error)")
                    }
                }
            }
        }
    }
    
    func updateConversationTitle(id: String, title: String) async throws {
        switch storageMode {
        case .local:
            try await localStorage.updateConversationTitle(id: id, title: title)
            
        case .huggingface:
            guard HuggingChatSession.shared.currentUser != nil else {
                throw StorageError.authenticationRequired
            }
            try await remoteStorage.updateConversationTitle(id: id, title: title)
            
        case .hybrid:
            // Update locally first
            try await localStorage.updateConversationTitle(id: id, title: title)
            
            // Sync to remote if authenticated
            if HuggingChatSession.shared.currentUser != nil {
                Task {
                    do {
                        try await remoteStorage.updateConversationTitle(id: id, title: title)
                        print("🔄 Title update synced to HuggingFace")
                    } catch {
                        print("⚠️ Failed to sync title update to HuggingFace: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func mergeConversations(local: [Conversation], remote: [Conversation]) -> [Conversation] {
        var merged: [String: Conversation] = [:]
        
        // Add local conversations
        for conversation in local {
            merged[conversation.serverId] = conversation
        }
        
        // Add remote conversations, avoiding duplicates
        for conversation in remote {
            if merged[conversation.serverId] == nil {
                merged[conversation.serverId] = conversation
            }
        }
        
        return Array(merged.values).sorted { $0.updatedAt > $1.updatedAt }
    }
}

// MARK: - Remote Storage Manager

/// Wrapper around existing HuggingFace network operations
class RemoteStorageManager: ConversationStorageProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    func createConversation(title: String, model: LLMModel) async throws -> Conversation {
        return try await withCheckedThrowingContinuation { continuation in
            NetworkService.createConversation(base: model)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                } receiveValue: { conversation in
                    continuation.resume(returning: conversation)
                }
                .store(in: &self.cancellables)
        }
    }
    
    func loadConversations() async throws -> [Conversation] {
        return try await withCheckedThrowingContinuation { continuation in
            NetworkService.getConversations()
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                } receiveValue: { conversations in
                    continuation.resume(returning: conversations)
                }
                .store(in: &self.cancellables)
        }
    }
    
    func loadConversation(id: String) async throws -> Conversation {
        return try await withCheckedThrowingContinuation { continuation in
            NetworkService.getConversation(id: id)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                } receiveValue: { conversation in
                    continuation.resume(returning: conversation)
                }
                .store(in: &self.cancellables)
        }
    }
    
    func saveMessage(_ message: MessageRow, to conversationId: String) async throws {
        // This would need to be implemented based on the existing prompt sending logic
        // For now, this is a placeholder as the existing system handles message saving differently
        throw StorageError.invalidData
    }
    
    func deleteConversation(id: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            NetworkService.deleteConversation(id: id)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                } receiveValue: { _ in
                    // Void response
                }
                .store(in: &self.cancellables)
        }
    }
    
    func updateConversationTitle(id: String, title: String) async throws {
        // This would need to be implemented based on existing title update logic
        // For now, this is a placeholder
        throw StorageError.invalidData
    }
}
