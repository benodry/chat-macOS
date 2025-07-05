#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔧 Detailed SQLite Debug")
print("=======================")

// Database setup
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
let dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path

print("🔍 Database path: \(dbPath)")

var db: OpaquePointer?
guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
    print("❌ Failed to open database")
    exit(1)
}

print("✅ Database opened successfully")

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

print("🔍 Preparing statement: \(sql)")
let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
print("📝 Prepare result: \(prepareResult) (SQLITE_OK = \(SQLITE_OK))")

guard prepareResult == SQLITE_OK else {
    let errorMessage = String(cString: sqlite3_errmsg(db))
    print("❌ Failed to prepare statement: \(errorMessage)")
    exit(1)
}

print("✅ Statement prepared successfully")

print("🔍 Binding user_id: '\(userId)'")
let bindResult = sqlite3_bind_text(statement, 1, userId, -1, nil)
print("📝 Bind result: \(bindResult) (SQLITE_OK = \(SQLITE_OK))")

var rowCount = 0
while true {
    let stepResult = sqlite3_step(statement)
    print("📝 Step result: \(stepResult) (SQLITE_ROW = \(SQLITE_ROW), SQLITE_DONE = \(SQLITE_DONE))")
    
    if stepResult == SQLITE_ROW {
        rowCount += 1
        print("\n--- Row \(rowCount) ---")
        
        // Check each column
        for i in 0..<6 {
            let columnType = sqlite3_column_type(statement, Int32(i))
            let columnName = String(cString: sqlite3_column_name(statement, Int32(i)))
            
            print("Column \(i) (\(columnName)): type = \(columnType)", terminator: "")
            
            switch columnType {
            case SQLITE3_TEXT:
                if let textPtr = sqlite3_column_text(statement, Int32(i)) {
                    let text = String(cString: textPtr)
                    print(", value = '\(text)'")
                } else {
                    print(", value = NULL")
                }
            case SQLITE3_FLOAT:
                let value = sqlite3_column_double(statement, Int32(i))
                print(", value = \(value)")
            case SQLITE3_INTEGER:
                let value = sqlite3_column_int64(statement, Int32(i))
                print(", value = \(value)")
            case SQLITE_NULL:
                print(", value = NULL")
            default:
                print(", value = <unknown type \(columnType)>")
            }
        }
        
        // Now extract values as the app would
        let idPtr = sqlite3_column_text(statement, 0)
        let titlePtr = sqlite3_column_text(statement, 1)
        let modelNamePtr = sqlite3_column_text(statement, 4)
        
        print("Raw pointers: id=\(idPtr != nil ? "valid" : "NULL"), title=\(titlePtr != nil ? "valid" : "NULL"), model=\(modelNamePtr != nil ? "valid" : "NULL")")
        
        if let idPtr = idPtr, let titlePtr = titlePtr, let modelNamePtr = modelNamePtr {
            let id = String(cString: idPtr)
            let title = String(cString: titlePtr)
            let modelName = String(cString: modelNamePtr)
            print("✅ Extracted: id='\(id)', title='\(title)', model='\(modelName)'")
        } else {
            print("❌ One or more required fields are NULL")
        }
        
    } else if stepResult == SQLITE_DONE {
        print("✅ Query completed")
        break
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("❌ Step failed: \(errorMessage)")
        break
    }
}

print("\n📊 Total rows processed: \(rowCount)")

sqlite3_close(db)
