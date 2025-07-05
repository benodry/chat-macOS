#!/usr/bin/env swift

import Foundation
import SQLite3

// Simulate the exact environment the app uses
func testAppDatabase() {
    print("🔧 Testing App Database Environment")
    print("=====================================")
    
    // Use the same path calculation as the app
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                               in: .userDomainMask).first!
    let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
    let dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path
    
    print("🔍 Database path: \(dbPath)")
    print("📁 App directory: \(appDirectory.path)")
    
    // Check if directory exists
    let directoryExists = FileManager.default.fileExists(atPath: appDirectory.path)
    print("📁 App directory exists: \(directoryExists)")
    
    // Check if database file exists
    let dbExists = FileManager.default.fileExists(atPath: dbPath)
    print("🗄️ Database file exists: \(dbExists)")
    
    if dbExists {
        let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath)
        if let fileSize = attributes?[FileAttributeKey.size] as? Int64 {
            print("📊 File size: \(fileSize) bytes")
        }
        if let modDate = attributes?[FileAttributeKey.modificationDate] as? Date {
            print("📅 Modified: \(modDate)")
        }
        
        // Check permissions
        let readable = FileManager.default.isReadableFile(atPath: dbPath)
        let writable = FileManager.default.isWritableFile(atPath: dbPath)
        print("📖 Readable: \(readable)")
        print("✏️ Writable: \(writable)")
    }
    
    // Try to open database
    var db: OpaquePointer?
    let result = sqlite3_open(dbPath, &db)
    
    if result == SQLITE_OK {
        print("✅ Database opened successfully")
        
        // Test query to list all conversations
        let sql = "SELECT id, user_id, title, created_at, updated_at, model_name FROM conversations ORDER BY updated_at DESC;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            print("📋 Conversations in database:")
            var count = 0
            
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
                
                let id = String(cString: sqlite3_column_text(statement, 0))
                let userId = String(cString: sqlite3_column_text(statement, 1))
                let title = String(cString: sqlite3_column_text(statement, 2))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let modelName = String(cString: sqlite3_column_text(statement, 5))
                
                print("  - \(id): \(title)")
                print("    User: \(userId)")
                print("    Model: \(modelName)")
                print("    Created: \(createdAt)")
                print("    Updated: \(updatedAt)")
                print()
            }
            
            print("📊 Total conversations: \(count)")
            sqlite3_finalize(statement)
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare statement: \(errorMessage)")
        }
        
        sqlite3_close(db)
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("❌ Failed to open database: \(errorMessage)")
    }
}

testAppDatabase()
