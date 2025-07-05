#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔧 Simple SQLite Debug")
print("=====================")

// Database setup
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
let dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path

var db: OpaquePointer?
guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
    print("❌ Failed to open database")
    exit(1)
}

let userId = "default"
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

var rowCount = 0
while sqlite3_step(statement) == SQLITE_ROW {
    rowCount += 1
    print("\n--- Row \(rowCount) ---")
    
    // Extract text values directly
    let id = sqlite3_column_text(statement, 0) != nil ? String(cString: sqlite3_column_text(statement, 0)!) : "NULL"
    let title = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)!) : "NULL"
    let modelName = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)!) : "NULL"
    let hfServerId = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)!) : "NULL"
    
    let createdAt = sqlite3_column_double(statement, 2)
    let updatedAt = sqlite3_column_double(statement, 3)
    
    print("ID: '\(id)'")
    print("Title: '\(title)'")
    print("Model: '\(modelName)'")
    print("HF Server ID: '\(hfServerId)'")
    print("Created: \(createdAt)")
    print("Updated: \(updatedAt)")
    
    // Check if required fields are valid
    let hasRequiredFields = sqlite3_column_text(statement, 0) != nil && 
                           sqlite3_column_text(statement, 1) != nil && 
                           sqlite3_column_text(statement, 4) != nil
    
    print("Has required fields: \(hasRequiredFields)")
}

print("\n📊 Total rows: \(rowCount)")

sqlite3_close(db)
