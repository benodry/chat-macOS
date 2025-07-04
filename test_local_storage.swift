#!/usr/bin/env swift

//
//  test_local_storage.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation
import SQLite3

// Simple test script to verify local storage functionality
// Run with: swift test_local_storage.swift

func testLocalStorage() {
    print("🧪 Testing Local Storage Implementation")
    
    // Create temporary database for testing
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_conversations.sqlite")
    let dbPath = tempURL.path
    
    print("📂 Test database path: \(dbPath)")
    
    var db: OpaquePointer?
    
    // Open database
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        print("❌ Failed to open test database")
        return
    }
    
    defer {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // Create tables
    let createTables = """
        CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            model_name TEXT
        );
        
        CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            type INTEGER NOT NULL,
            content TEXT NOT NULL,
            timestamp REAL NOT NULL,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id)
        );
    """
    
    guard sqlite3_exec(db, createTables, nil, nil, nil) == SQLITE_OK else {
        print("❌ Failed to create tables")
        return
    }
    
    print("✅ Tables created successfully")
    
    // Test inserting a conversation
    let conversationId = UUID().uuidString
    let userId = "test-user"
    let title = "Test Conversation"
    let now = Date().timeIntervalSince1970
    
    let insertConversation = """
        INSERT INTO conversations (id, user_id, title, created_at, updated_at, model_name)
        VALUES (?, ?, ?, ?, ?, ?);
    """
    
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertConversation, -1, &statement, nil) == SQLITE_OK else {
        print("❌ Failed to prepare conversation insert")
        return
    }
    
    sqlite3_bind_text(statement, 1, conversationId, -1, nil)
    sqlite3_bind_text(statement, 2, userId, -1, nil)
    sqlite3_bind_text(statement, 3, title, -1, nil)
    sqlite3_bind_double(statement, 4, now)
    sqlite3_bind_double(statement, 5, now)
    sqlite3_bind_text(statement, 6, "test-model", -1, nil)
    
    guard sqlite3_step(statement) == SQLITE_DONE else {
        print("❌ Failed to insert conversation")
        sqlite3_finalize(statement)
        return
    }
    
    sqlite3_finalize(statement)
    print("✅ Conversation inserted successfully")
    
    // Test inserting a message
    let messageId = UUID().uuidString
    let messageContent = "Hello, this is a test message!"
    
    let insertMessage = """
        INSERT INTO messages (id, conversation_id, type, content, timestamp)
        VALUES (?, ?, ?, ?, ?);
    """
    
    guard sqlite3_prepare_v2(db, insertMessage, -1, &statement, nil) == SQLITE_OK else {
        print("❌ Failed to prepare message insert")
        return
    }
    
    sqlite3_bind_text(statement, 1, messageId, -1, nil)
    sqlite3_bind_text(statement, 2, conversationId, -1, nil)
    sqlite3_bind_int(statement, 3, 0) // user message
    sqlite3_bind_text(statement, 4, messageContent, -1, nil)
    sqlite3_bind_double(statement, 5, now)
    
    guard sqlite3_step(statement) == SQLITE_DONE else {
        print("❌ Failed to insert message")
        sqlite3_finalize(statement)
        return
    }
    
    sqlite3_finalize(statement)
    print("✅ Message inserted successfully")
    
    // Test querying conversations
    let selectConversations = "SELECT id, title, created_at FROM conversations WHERE user_id = ?;"
    
    guard sqlite3_prepare_v2(db, selectConversations, -1, &statement, nil) == SQLITE_OK else {
        print("❌ Failed to prepare conversation select")
        return
    }
    
    sqlite3_bind_text(statement, 1, userId, -1, nil)
    
    var conversationCount = 0
    while sqlite3_step(statement) == SQLITE_ROW {
        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let createdAt = sqlite3_column_double(statement, 2)
        
        print("📝 Found conversation: \(title) (\(id)) created at \(Date(timeIntervalSince1970: createdAt))")
        conversationCount += 1
    }
    
    sqlite3_finalize(statement)
    
    if conversationCount > 0 {
        print("✅ Successfully queried \(conversationCount) conversations")
    } else {
        print("❌ No conversations found")
        return
    }
    
    // Test querying messages
    let selectMessages = "SELECT content, type FROM messages WHERE conversation_id = ?;"
    
    guard sqlite3_prepare_v2(db, selectMessages, -1, &statement, nil) == SQLITE_OK else {
        print("❌ Failed to prepare message select")
        return
    }
    
    sqlite3_bind_text(statement, 1, conversationId, -1, nil)
    
    var messageCount = 0
    while sqlite3_step(statement) == SQLITE_ROW {
        let content = String(cString: sqlite3_column_text(statement, 0))
        let type = sqlite3_column_int(statement, 1)
        let typeString = type == 0 ? "user" : "assistant"
        
        print("💬 Found message (\(typeString)): \(content)")
        messageCount += 1
    }
    
    sqlite3_finalize(statement)
    
    if messageCount > 0 {
        print("✅ Successfully queried \(messageCount) messages")
    } else {
        print("❌ No messages found")
        return
    }
    
    print("🎉 All local storage tests passed!")
}

// Run the test
testLocalStorage()
