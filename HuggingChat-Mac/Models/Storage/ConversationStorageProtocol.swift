//
//  ConversationStorageProtocol.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation

/// Protocol defining conversation storage operations
protocol ConversationStorageProtocol {
    func createConversation(title: String, model: LLMModel) async throws -> Conversation
    func loadConversations() async throws -> [Conversation]
    func loadConversation(id: String) async throws -> Conversation
    func saveMessage(_ message: MessageRow, to conversationId: String) async throws
    func deleteConversation(id: String) async throws
    func updateConversationTitle(id: String, title: String) async throws
}

/// Storage mode enumeration
enum StorageMode: String, CaseIterable {
    case local = "local"
    case huggingface = "huggingface"
    case hybrid = "hybrid"
    
    var displayName: String {
        switch self {
        case .local:
            return "Local Only"
        case .huggingface:
            return "HuggingFace"
        case .hybrid:
            return "Hybrid (Local + HF Sync)"
        }
    }
    
    var description: String {
        switch self {
        case .local:
            return "Store conversations locally on your device"
        case .huggingface:
            return "Use HuggingFace remote storage (requires login)"
        case .hybrid:
            return "Local storage with optional HuggingFace sync"
        }
    }
}

/// Error types for storage operations
enum StorageError: Error, LocalizedError {
    case conversationNotFound
    case invalidData
    case syncConflict
    case authenticationRequired
    case localStorageUnavailable
    case databaseCorrupted
    
    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .invalidData:
            return "Invalid data format"
        case .syncConflict:
            return "Sync conflict detected"
        case .authenticationRequired:
            return "Authentication required for this operation"
        case .localStorageUnavailable:
            return "Local storage is unavailable"
        case .databaseCorrupted:
            return "Database is corrupted or contains invalid data"
        }
    }
}
