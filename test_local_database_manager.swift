#!/usr/bin/env swift

import Foundation
import SQLite3

// Exact simulation of LocalDatabaseManager.loadConversations

print("🔧 LocalDatabaseManager Simulation")
print("==================================")

class TestLocalDatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String
    
    init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
        dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path
        
        print("📦 Database path: \(dbPath)")
        
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("❌ Unable to open database")
            return
        }
        
        print("✅ Database opened successfully")
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    func isDatabaseHealthy() -> Bool {
        guard let db = db else { return false }
        
        let sql = "PRAGMA integrity_check;"
        var statement: OpaquePointer?
        defer { 
            if statement != nil {
                sqlite3_finalize(statement) 
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if let resultPtr = sqlite3_column_text(statement, 0) {
                let result = String(cString: resultPtr)
                return result == "ok"
            }
        }
        
        return false
    }
    
    func loadConversations() -> [String] {
        print("🔍 Loading conversations from local database...")
        
        guard let db = self.db else {
            print("❌ Database not initialized")
            return []
        }
        
        // Perform health check first
        guard self.isDatabaseHealthy() else {
            print("❌ Database health check failed")
            return []
        }
        
        let userId = "default" // This is what the app uses
        print("🔍 Loading conversations for user: \(userId)")
        
        let sql = """
            SELECT id, title, created_at, updated_at, model_name, hf_server_id 
            FROM conversations 
            WHERE user_id = ? 
            ORDER BY updated_at DESC;
        """
        
        var statement: OpaquePointer?
        defer { 
            if statement != nil {
                sqlite3_finalize(statement) 
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare statement: \(errorMessage)")
            return []
        }
        
        guard let statement = statement else {
            print("❌ Statement is nil after preparation")
            return []
        }
        
        sqlite3_bind_text(statement, 1, userId, -1, nil)
        
        var conversations: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let titlePtr = sqlite3_column_text(statement, 1),
                  let modelNamePtr = sqlite3_column_text(statement, 4) else {
                print("⚠️ Skipping row with null required fields")
                continue // Skip invalid rows
            }
            
            let id = String(cString: idPtr)
            let title = String(cString: titlePtr)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let modelName = String(cString: modelNamePtr)
            
            let hfServerIdPtr = sqlite3_column_text(statement, 5)
            let serverId = hfServerIdPtr != nil ? String(cString: hfServerIdPtr!) : id
            
            print("📝 Found conversation: \(title) (id: \(id), serverId: \(serverId), model: \(modelName))")
            conversations.append("\(title) (\(id))")
        }
        
        print("📦 Loaded \(conversations.count) local conversations")
        return conversations
    }
}

let manager = TestLocalDatabaseManager()
let conversations = manager.loadConversations()

print("\n📊 Final result: \(conversations.count) conversations loaded")
for (index, conversation) in conversations.enumerated() {
    print("  \(index + 1). \(conversation)")
}
