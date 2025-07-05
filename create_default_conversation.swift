#!/usr/bin/env swift

import Foundation
import SQLite3

// Create a conversation with the "default" user ID that the app uses

print("🔧 Creating Test Conversation with 'default' user ID")
print("==================================================")

// Database setup
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
let dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path

print("🔍 Database path: \(dbPath)")

// Open database
var db: OpaquePointer?
guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
    print("❌ Failed to open database")
    exit(1)
}

print("✅ Database opened successfully")

// Create a conversation with user_id = "default"
let conversationId = "default-test-conversation"
let userId = "default" // This is what the app uses when no user is loaded
let title = "Test Conversation (Default User)"
let now = Date()
let modelName = "meta-llama/Meta-Llama-3.1-70B-Instruct"

let sql = """
    INSERT OR REPLACE INTO conversations (id, user_id, title, created_at, updated_at, model_name) 
    VALUES (?, ?, ?, ?, ?, ?);
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
    exit(1)
}

sqlite3_bind_text(statement, 1, conversationId, -1, nil)
sqlite3_bind_text(statement, 2, userId, -1, nil)
sqlite3_bind_text(statement, 3, title, -1, nil)
sqlite3_bind_double(statement, 4, now.timeIntervalSince1970)
sqlite3_bind_double(statement, 5, now.timeIntervalSince1970)
sqlite3_bind_text(statement, 6, modelName, -1, nil)

guard sqlite3_step(statement) == SQLITE_DONE else {
    let errorMessage = String(cString: sqlite3_errmsg(db))
    print("❌ Failed to insert conversation: \(errorMessage)")
    exit(1)
}

print("✅ Created conversation: \(title)")

// Now test loading conversations
let loadSQL = """
    SELECT id, title, created_at, updated_at, model_name, hf_server_id 
    FROM conversations 
    WHERE user_id = ? 
    ORDER BY updated_at DESC;
"""

var loadStatement: OpaquePointer?
defer { 
    if loadStatement != nil {
        sqlite3_finalize(loadStatement) 
    }
}

guard sqlite3_prepare_v2(db, loadSQL, -1, &loadStatement, nil) == SQLITE_OK else {
    let errorMessage = String(cString: sqlite3_errmsg(db))
    print("❌ Failed to prepare load statement: \(errorMessage)")
    exit(1)
}

sqlite3_bind_text(loadStatement, 1, userId, -1, nil)

print("\n📋 Conversations for user '\(userId)':")
var count = 0

while sqlite3_step(loadStatement) == SQLITE_ROW {
    guard let idPtr = sqlite3_column_text(loadStatement, 0),
          let titlePtr = sqlite3_column_text(loadStatement, 1),
          let modelNamePtr = sqlite3_column_text(loadStatement, 4) else {
        continue
    }
    
    let id = String(cString: idPtr)
    let title = String(cString: titlePtr)
    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(loadStatement, 2))
    let modelName = String(cString: modelNamePtr)
    
    print("  - \(id): \(title) (model: \(modelName), created: \(createdAt))")
    count += 1
}

print("📊 Total conversations: \(count)")

sqlite3_close(db)
print("\n✅ Test completed. The app should now be able to load conversations!")
