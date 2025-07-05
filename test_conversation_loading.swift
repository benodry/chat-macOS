#!/usr/bin/env swift

import Foundation
import SQLite3

// Test script to diagnose conversation loading issues

print("🔧 Testing Conversation Loading")
print("=============================")

// Database setup
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
let dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path

print("🔍 Database path: \(dbPath)")
print("📁 Database exists: \(FileManager.default.fileExists(atPath: dbPath))")

if !FileManager.default.fileExists(atPath: dbPath) {
    print("❌ Database doesn't exist!")
    exit(1)
}

// Open database
var db: OpaquePointer?
guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
    print("❌ Failed to open database")
    exit(1)
}

print("✅ Database opened successfully")

// Test query to load conversations (mimicking LocalDatabaseManager)
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
    exit(1)
}

sqlite3_bind_text(statement, 1, userId, -1, nil)

var conversations: [[String: Any]] = []

while sqlite3_step(statement) == SQLITE_ROW {
    guard let idPtr = sqlite3_column_text(statement, 0),
          let titlePtr = sqlite3_column_text(statement, 1),
          let modelNamePtr = sqlite3_column_text(statement, 4) else {
        print("⚠️ Skipping row with null required fields")
        continue
    }
    
    let id = String(cString: idPtr)
    let title = String(cString: titlePtr)
    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
    let modelName = String(cString: modelNamePtr)
    
    let hfServerIdPtr = sqlite3_column_text(statement, 5)
    let serverId = hfServerIdPtr != nil ? String(cString: hfServerIdPtr!) : id
    
    let conversation: [String: Any] = [
        "id": id,
        "serverId": serverId,
        "title": title,
        "modelName": modelName,
        "createdAt": createdAt,
        "updatedAt": updatedAt
    ]
    
    conversations.append(conversation)
    print("📝 Found conversation: \(title) (id: \(id), model: \(modelName))")
}

print("\n📊 Total conversations found: \(conversations.count)")

if conversations.isEmpty {
    print("❌ No conversations found for user: \(userId)")
    
    // Let's check if there are any conversations at all
    let allSQL = "SELECT id, user_id, title FROM conversations;"
    var allStatement: OpaquePointer?
    defer { 
        if allStatement != nil {
            sqlite3_finalize(allStatement) 
        }
    }
    
    if sqlite3_prepare_v2(db, allSQL, -1, &allStatement, nil) == SQLITE_OK {
        print("\n🔍 Checking all conversations in database:")
        while sqlite3_step(allStatement) == SQLITE_ROW {
            let idPtr = sqlite3_column_text(allStatement, 0)
            let userIdPtr = sqlite3_column_text(allStatement, 1)
            let titlePtr = sqlite3_column_text(allStatement, 2)
            
            let id = idPtr != nil ? String(cString: idPtr!) : "NULL"
            let userId = userIdPtr != nil ? String(cString: userIdPtr!) : "NULL"
            let title = titlePtr != nil ? String(cString: titlePtr!) : "NULL"
            
            print("  - ID: \(id), User: \(userId), Title: \(title)")
        }
    }
} else {
    print("✅ Successfully loaded conversations!")
}

sqlite3_close(db)
print("\n✅ Test completed")
