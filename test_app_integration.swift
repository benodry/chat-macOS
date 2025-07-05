#!/usr/bin/env swift

import Foundation
import SQLite3

// Test script to verify that local model generation is working correctly

func testDatabaseConnection() {
    let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("HuggingChat")
        .appendingPathComponent("conversations.db")
    
    print("Testing database at: \(dbPath.path)")
    
    var db: OpaquePointer?
    if sqlite3_open(dbPath.path, &db) == SQLITE_OK {
        print("✅ Database connection successful")
        
        // Check conversations table
        let query = "SELECT id, title FROM conversations ORDER BY createdAt DESC LIMIT 5"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            print("\n📋 Recent conversations:")
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                print("  - \(id): \(title)")
            }
        }
        sqlite3_finalize(stmt)
        
        // Check messages table for recent activity
        let messageQuery = """
            SELECT content, isUser, conversationId 
            FROM messages 
            ORDER BY createdAt DESC 
            LIMIT 10
        """
        
        if sqlite3_prepare_v2(db, messageQuery, -1, &stmt, nil) == SQLITE_OK {
            print("\n💬 Recent messages:")
            while sqlite3_step(stmt) == SQLITE_ROW {
                let content = String(cString: sqlite3_column_text(stmt, 0))
                let isUser = sqlite3_column_int(stmt, 1) == 1
                let convId = String(cString: sqlite3_column_text(stmt, 2))
                let role = isUser ? "User" : "Assistant"
                let preview = String(content.prefix(50))
                print("  - [\(role)] \(preview)... (conv: \(convId))")
            }
        }
        sqlite3_finalize(stmt)
        
    } else {
        print("❌ Failed to open database")
    }
    
    sqlite3_close(db)
}

func checkAppSettings() {
    print("\n🔧 Checking app settings...")
    
    // Check if local generation is enabled in UserDefaults
    let defaults = UserDefaults.standard
    let localGenEnabled = defaults.bool(forKey: "localGenerationEnabled")
    let selectedModel = defaults.string(forKey: "selectedLocalModel")
    
    print("Local generation enabled: \(localGenEnabled)")
    print("Selected local model: \(selectedModel ?? "None")")
}

func main() {
    print("🧪 Testing HuggingChat app integration...")
    print("================================================")
    
    testDatabaseConnection()
    checkAppSettings()
    
    print("\n✅ Test completed")
}

main()
