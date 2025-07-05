#!/usr/bin/env swift

import Foundation
import SQLite3

// Helper to get the database path
func getDatabasePath() -> String {
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                               in: .userDomainMask).first!
    let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
    return appDirectory.appendingPathComponent("conversations.sqlite").path
}

// Check if database file exists and permissions
func checkDatabaseFile() {
    let dbPath = getDatabasePath()
    print("🔍 Database path: \(dbPath)")
    
    let fileManager = FileManager.default
    
    // Check if directory exists
    let parentDir = URL(fileURLWithPath: dbPath).deletingLastPathComponent().path
    print("📁 Parent directory: \(parentDir)")
    print("📁 Parent directory exists: \(fileManager.fileExists(atPath: parentDir))")
    
    // Try to create directory if it doesn't exist
    if !fileManager.fileExists(atPath: parentDir) {
        do {
            try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            print("✅ Created parent directory")
        } catch {
            print("❌ Failed to create parent directory: \(error)")
            return
        }
    }
    
    // Check if database file exists
    let dbExists = fileManager.fileExists(atPath: dbPath)
    print("🗄️ Database file exists: \(dbExists)")
    
    if dbExists {
        // Check file attributes
        do {
            let attributes = try fileManager.attributesOfItem(atPath: dbPath)
            print("📊 File size: \(attributes[.size] ?? 0) bytes")
            print("📅 Modified: \(attributes[.modificationDate] ?? Date())")
            
            // Check permissions
            let readable = fileManager.isReadableFile(atPath: dbPath)
            let writable = fileManager.isWritableFile(atPath: dbPath)
            print("📖 Readable: \(readable)")
            print("✏️ Writable: \(writable)")
        } catch {
            print("❌ Failed to get file attributes: \(error)")
        }
    }
}

// Test database connection and operations
func testDatabase() {
    let dbPath = getDatabasePath()
    var db: OpaquePointer?
    
    // Try to open database
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        print("❌ Failed to open database")
        if let errorMessage = sqlite3_errmsg(db) {
            print("❌ SQLite error: \(String(cString: errorMessage))")
        }
        return
    }
    
    defer { sqlite3_close(db) }
    print("✅ Database opened successfully")
    
    // Test creating tables
    let createConversationsTable = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            model_name TEXT,
            model_config TEXT,
            is_synced_to_hf INTEGER DEFAULT 0,
            hf_server_id TEXT
        );
    """
    
    if sqlite3_exec(db, createConversationsTable, nil, nil, nil) == SQLITE_OK {
        print("✅ Conversations table created/verified")
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("❌ Failed to create conversations table: \(errorMessage)")
        return
    }
    
    // Test inserting a conversation
    let testInsert = """
        INSERT OR REPLACE INTO conversations (id, user_id, title, created_at, updated_at, model_name) 
        VALUES ('test-conversation', 'test-user', 'Test Conversation', ?, ?, 'test-model');
    """
    
    var statement: OpaquePointer?
    if sqlite3_prepare_v2(db, testInsert, -1, &statement, nil) == SQLITE_OK {
        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(statement, 1, now)
        sqlite3_bind_double(statement, 2, now)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            print("✅ Test conversation inserted successfully")
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to insert test conversation: \(errorMessage)")
        }
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("❌ Failed to prepare insert statement: \(errorMessage)")
    }
    
    if statement != nil {
        sqlite3_finalize(statement)
    }
    
    // Test querying conversations
    let query = "SELECT id, title, created_at FROM conversations;"
    statement = nil
    
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        print("📋 Conversations in database:")
        var count = 0
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let createdAt = sqlite3_column_double(statement, 2)
            let date = Date(timeIntervalSince1970: createdAt)
            
            print("  - \(id): \(title) (created: \(date))")
            count += 1
        }
        
        print("📊 Total conversations: \(count)")
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("❌ Failed to prepare query: \(errorMessage)")
    }
    
    if statement != nil {
        sqlite3_finalize(statement)
    }
}

// Run the diagnostics
print("🔧 Database Diagnostics Tool")
print("=============================")
print()

checkDatabaseFile()
print()
testDatabase()
