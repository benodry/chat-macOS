//
//  HuggingChatSession.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 8/23/24.
//

import SwiftUI
import Combine
import Foundation
import WebKit
import SafariServices
import AuthenticationServices

@Observable class HuggingChatSession {
    static let shared: HuggingChatSession = HuggingChatSession()

    var clientID: String?
    var token: String?
    var conversations: [Conversation] = []
    var availableLLM: [LLMModel] = []
    var currentConversation: String?
    var currentUser: HuggingChatUser?
    
    private var cancellables: [AnyCancellable] = []

    init() {
        print("🍪 HuggingChatSession.init - Checking available cookies...")
        
        // Safely get cookies with nil coalescing to prevent crashes
        guard let cookies = HTTPCookieStorage.shared.cookies else {
            print("⚠️  HTTPCookieStorage.shared.cookies returned nil")
            return
        }
        
        print("🍪 Total cookies in HTTPCookieStorage: \(cookies.count)")
        for cookie in cookies {
            print("   \(cookie.name): \(cookie.value.prefix(20))... (domain: \(cookie.domain), path: \(cookie.path))")
        }
        
        // Specifically check for HuggingFace cookies
        let hfCookies = cookies.filter { $0.domain.contains("huggingface") }
        print("🍪 HuggingFace cookies: \(hfCookies.count)")
        
        if let hfChatCookie = cookies.first(where: { $0.name == "hf-chat" }) {
            print("✅ Found hf-chat cookie: \(hfChatCookie.value.prefix(20))...")
            // Defer validation to avoid circular dependency during singleton initialization
            // Use a longer delay to ensure the singleton is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.validateAndCleanupAuthState()
            }
        } else {
            print("❌ No hf-chat cookie found - user needs to authenticate")
        }
    }
    
    /// Validates existing auth cookies and cleans up stale authentication state
    private func validateAndCleanupAuthState() {
        print("🔍 HuggingChatSession.validateAndCleanupAuthState - Testing existing auth cookies")
        
        NetworkService.getCurrentUser()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                switch completion {
                case .failure(let error):
                    print("❌ Auth validation failed: \(error.localizedDescription)")
                    
                    // Check if this is a 401 Unauthorized error (stale cookie)
                    if let hfError = error as? HFError {
                        switch hfError {
                        case .httpUnauthorized, .httpError(401, _):
                            print("🧹 Detected stale auth cookies (401 Unauthorized) - cleaning up")
                            self?.cleanupStaleAuthState()
                        default:
                            print("ℹ️ Auth validation failed with non-auth error: \(hfError)")
                        }
                    }
                case .finished:
                    break
                }
            } receiveValue: { [weak self] user in
                print("✅ Auth validation successful - cookies are valid for user: \(user.username)")
                self?.currentUser = user
            }.store(in: &cancellables)
    }
    
    /// Clean up stale authentication state when cookies are invalid
    private func cleanupStaleAuthState() {
        print("🧹 HuggingChatSession.cleanupStaleAuthState - Removing stale authentication")
        
        // Clear all auth-related cookies
        clearAuthCookies()
        
        // Reset user state
        currentUser = nil
        currentConversation = nil
        UserDefaults.standard.setValue(false, forKey: "userLoggedIn")
        UserDefaults.standard.setValue(false, forKey: "onboardingDone")
        
        print("✅ Stale auth state cleaned up - user will need to re-authenticate")
    }
    
    func refreshLoginState() {
        print("🔄 HuggingChatSession.refreshLoginState - Checking authentication")
        NetworkService.getCurrentUser()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
            switch completion {
            case .failure(let error):
                print("❌ refreshLoginState failed: \(error.localizedDescription)")
                
                // Check if this is a 401 Unauthorized error (stale cookie)
                if let hfError = error as? HFError {
                    switch hfError {
                    case .httpUnauthorized, .httpError(401, _):
                        print("🧹 refreshLoginState detected stale auth cookies - cleaning up")
                        self?.cleanupStaleAuthState()
                    default:
                        self?.currentUser = nil
                    }
                } else {
                    self?.currentUser = nil
                }
            case .finished: break
            }
        } receiveValue: { [weak self] user in
            print("✅ refreshLoginState successful - user: \(user.username)")
            self?.currentUser = user
        }.store(in: &cancellables)
    }
    
    var hfChatToken: String? {
        print("🔍 HuggingChatSession.hfChatToken - Looking for authentication token")
        
        // Always read fresh cookies from HTTPCookieStorage to get latest OAuth tokens
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Total cookies in HTTPCookieStorage: \(cookies.count)")
        
        // Show all HuggingFace related cookies
        let hfCookies = cookies.filter { $0.domain.contains("huggingface") }
        print("🍪 HuggingFace cookies found: \(hfCookies.count)")
        for cookie in hfCookies {
            print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain), path: \(cookie.path))")
        }
        
        guard let token = cookies.first(where: { $0.name == "hf-chat" })?.value else {
            print("❌ No hf-chat token found in HTTPCookieStorage")
            
            // Check for similar cookies
            let similarCookies = cookies.filter { $0.name.contains("chat") || $0.name.contains("token") || $0.name.contains("hf") }
            print("🔍 Similar cookies found: \(similarCookies.count)")
            for cookie in similarCookies {
                print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
            }
            
            return nil
        }
        print("✅ Found fresh hf-chat token: \(token.prefix(20))...")
        return token
    }
    
    /// Force refresh the current user session by re-checking authentication
    func forceRefreshSession() {
        print("🔄 HuggingChatSession.forceRefreshSession - Force refreshing authentication state")
        refreshLoginState()
    }

    func logout() {
        print("🚪 HuggingChatSession.logout - Starting logout process")
        
        // Get all cookies and log them before deletion
        let cookieStore = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Total cookies before logout: \(cookieStore.count)")
        
        let hfCookies = cookieStore.filter { $0.domain.contains("huggingface") }
        print("🍪 HuggingFace cookies to delete: \(hfCookies.count)")
        for cookie in hfCookies {
            print("   Deleting: \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain), path: \(cookie.path))")
        }
        
        // Delete ALL cookies synchronously to avoid race conditions
        for cookie in cookieStore {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        
        // Verify cookies are actually deleted
        let remainingCookies = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Remaining cookies after logout: \(remainingCookies.count)")
        if remainingCookies.count > 0 {
            print("⚠️ Warning: Some cookies remain after logout:")
            for cookie in remainingCookies {
                print("   \(cookie.name) (domain: \(cookie.domain))")
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentUser = nil
            self?.currentConversation = ""
            UserDefaults.standard.setValue(false, forKey: "userLoggedIn")
            UserDefaults.standard.setValue(false, forKey: "onboardingDone")
            print("✅ Logout completed - user state cleared")
        }
    }
    
    /// Clear only authentication-related cookies to prepare for fresh OAuth
    func clearAuthCookies() {
        print("🧹 HuggingChatSession.clearAuthCookies - Clearing auth cookies for fresh OAuth")
        
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let authCookies = allCookies.filter { cookie in
            // Clear HuggingFace domain cookies and any auth-related cookies
            return cookie.domain.contains("huggingface") || 
                   cookie.name.contains("auth") ||
                   cookie.name.contains("token") ||
                   cookie.name == "hf-chat"
        }
        
        print("🍪 Found \(authCookies.count) auth cookies to clear:")
        for cookie in authCookies {
            print("   Clearing: \(cookie.name) (domain: \(cookie.domain))")
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        
        // Reset current user state
        currentUser = nil
        print("✅ Auth cookies cleared, ready for fresh OAuth")
    }
    
    /// Get the hf-chat token directly from cookies without accessing the singleton
    /// This prevents circular dependencies during initialization
    static func getHfChatToken() -> String? {
        print("🔍 HuggingChatSession.getHfChatToken (static) - Looking for authentication token")
        
        // Always read fresh cookies from HTTPCookieStorage to get latest OAuth tokens
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Total cookies in HTTPCookieStorage: \(cookies.count)")
        
        // Show all HuggingFace related cookies
        let hfCookies = cookies.filter { $0.domain.contains("huggingface") }
        print("🍪 HuggingFace cookies found: \(hfCookies.count)")
        for cookie in hfCookies {
            print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain), path: \(cookie.path))")
        }
        
        guard let token = cookies.first(where: { $0.name == "hf-chat" })?.value else {
            print("❌ No hf-chat token found in HTTPCookieStorage")
            
            // Check for similar cookies
            let similarCookies = cookies.filter { $0.name.contains("chat") || $0.name.contains("token") || $0.name.contains("hf") }
            print("🔍 Similar cookies found: \(similarCookies.count)")
            for cookie in similarCookies {
                print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
            }
            
            return nil
        }
        print("✅ Found fresh hf-chat token: \(token.prefix(20))...")
        return token
    }
}
