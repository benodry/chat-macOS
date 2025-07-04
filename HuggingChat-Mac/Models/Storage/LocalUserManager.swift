//
//  LocalUserManager.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation
import SwiftUI

/// Manages local user profiles and preferences
@Observable class LocalUserManager {
    static let shared = LocalUserManager()
    
    // MARK: - Properties
    
    var currentLocalUser: LocalUser?
    var storageMode: StorageMode {
        get {
            StorageMode(rawValue: UserDefaults.standard.string(forKey: "storageMode") ?? "local") ?? .local
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "storageMode")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadCurrentUser()
    }
    
    // MARK: - User Management
    
    func createLocalUser(username: String) {
        let user = LocalUser(
            id: UUID(),
            username: username,
            createdAt: Date(),
            preferences: LocalUserPreferences()
        )
        
        currentLocalUser = user
        saveCurrentUser()
    }
    
    func loadCurrentUser() {
        guard let userData = UserDefaults.standard.data(forKey: "currentLocalUser"),
              let user = try? JSONDecoder().decode(LocalUser.self, from: userData) else {
            // Create default user if none exists
            createLocalUser(username: "Local User")
            return
        }
        
        currentLocalUser = user
    }
    
    private func saveCurrentUser() {
        guard let user = currentLocalUser,
              let userData = try? JSONEncoder().encode(user) else { return }
        
        UserDefaults.standard.set(userData, forKey: "currentLocalUser")
    }
    
    func updateUsername(_ newUsername: String) {
        currentLocalUser?.username = newUsername
        saveCurrentUser()
    }
    
    func updatePreferences(_ preferences: LocalUserPreferences) {
        currentLocalUser?.preferences = preferences
        saveCurrentUser()
    }
    
    // MARK: - Storage Mode Management
    
    func setStorageMode(_ mode: StorageMode) {
        storageMode = mode
        print("📦 Storage mode changed to: \(mode.displayName)")
    }
    
    var requiresHuggingFaceAuth: Bool {
        return storageMode == .huggingface || storageMode == .hybrid
    }
    
    var canUseLocalStorage: Bool {
        return storageMode == .local || storageMode == .hybrid
    }
}

// MARK: - Local User Models

struct LocalUser: Codable, Identifiable {
    let id: UUID
    var username: String
    let createdAt: Date
    var preferences: LocalUserPreferences
    
    init(id: UUID, username: String, createdAt: Date, preferences: LocalUserPreferences) {
        self.id = id
        self.username = username
        self.createdAt = createdAt
        self.preferences = preferences
    }
}

struct LocalUserPreferences: Codable {
    var theme: String = "Default"
    var autoSave: Bool = true
    var enableNotifications: Bool = false
    var defaultModel: String = "meta-llama/Meta-Llama-3.1-70B-Instruct"
    var conversationRetentionDays: Int = 30
    
    init() {}
}
