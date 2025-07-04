//
//  LocalDatabaseManager.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import Foundation
import SQLite3

/// SQLite-based local storage implementation
class LocalDatabaseManager: ConversationStorageProtocol {
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let dbQueue = DispatchQueue(label: "com.huggingchat.database", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init() {
        // Create database in Application Support directory
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("HuggingChat-Mac")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appDirectory, 
                                               withIntermediateDirectories: true)
        
        dbPath = appDirectory.appendingPathComponent("conversations.sqlite").path
        
        print("📦 Local database path: \(dbPath)")
        
        initializeDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
     private func initializeDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("❌ Unable to open database at path: \(dbPath)")
            if let errorMessage = sqlite3_errmsg(db) {
                print("❌ SQLite error: \(String(cString: errorMessage))")
            }
            return
        }
        
        print("✅ Database opened successfully at: \(dbPath)")
        createTables()
    }
    
    private func createTables() {
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
        
        let createMessagesTable = """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                type INTEGER NOT NULL,
                content TEXT NOT NULL,
                timestamp REAL NOT NULL,
                metadata TEXT,
                FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
            );
        """
        
        let createIndexes = """
            CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
            CREATE INDEX IF NOT EXISTS idx_conversations_updated_at ON conversations(updated_at);
            CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
            CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
        """
        
        executeSQL(createConversationsTable)
        executeSQL(createMessagesTable)
        executeSQL(createIndexes)
        
        print("✅ Local database tables created successfully")
    }
    
    private func executeSQL(_ sql: String) {
        guard let db = db else {
            print("❌ Database not initialized")
            return
        }
        
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ SQL execution failed: \(errorMessage)")
            print("❌ Failed SQL: \(sql)")
            return
        }
        
        print("✅ SQL executed successfully: \(sql.prefix(50))...")
    }
    
    // MARK: - ConversationStorageProtocol Implementation
    
    func createConversation(title: String, model: LLMModel) async throws -> Conversation {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    guard let db = self.db else {
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    let conversationId = UUID().uuidString
                    let userId = LocalUserManager.shared.currentLocalUser?.id.uuidString ?? "default"
                    let now = Date()
                    
                    let sql = """
                        INSERT INTO conversations (id, user_id, title, created_at, updated_at, model_name) 
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
                        print("❌ Failed to prepare create conversation statement: \(errorMessage)")
                        continuation.resume(throwing: StorageError.databaseCorrupted)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, conversationId, -1, nil)
                    sqlite3_bind_text(statement, 2, userId, -1, nil)
                    sqlite3_bind_text(statement, 3, title, -1, nil)
                    sqlite3_bind_double(statement, 4, now.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 5, now.timeIntervalSince1970)
                    sqlite3_bind_text(statement, 6, model.id, -1, nil)
                    
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    // Create and return conversation object
                    let conversation = Conversation(
                        serverId: conversationId, // Use local ID as server ID for consistency
                        title: title,
                        modelId: model.id,
                        updatedAt: now,
                        messages: [],
                        areMessagesLoaded: true
                    )
                    
                    print("✅ Created local conversation: \(title) (\(conversationId))")
                    continuation.resume(returning: conversation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func loadConversations() async throws -> [Conversation] {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    print("🔍 Loading conversations from local database...")
                    
                    guard let db = self.db else {
                        print("❌ Database not initialized")
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    // Perform health check first
                    guard self.isDatabaseHealthy() else {
                        print("❌ Database health check failed")
                        continuation.resume(throwing: StorageError.databaseCorrupted)
                        return
                    }
                    
                    let userId = LocalUserManager.shared.currentLocalUser?.id.uuidString ?? "default"
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
                        continuation.resume(throwing: StorageError.databaseCorrupted)
                        return
                    }
                    
                    guard let statement = statement else {
                        print("❌ Statement is nil after preparation")
                        continuation.resume(throwing: StorageError.databaseCorrupted)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, userId, -1, nil)
                    
                    var conversations: [Conversation] = []
                    
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
                        
                        let conversation = Conversation(
                            serverId: serverId,
                            title: title,
                            modelId: modelName,
                            updatedAt: updatedAt,
                            messages: [],
                            areMessagesLoaded: false
                        )
                        
                        conversations.append(conversation)
                    }
                    
                    print("📦 Loaded \(conversations.count) local conversations")
                    continuation.resume(returning: conversations)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func loadConversation(id: String) async throws -> Conversation {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    guard let db = self.db else {
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    // First get conversation details
                    let conversationSQL = """
                        SELECT id, title, created_at, updated_at, model_name, hf_server_id 
                        FROM conversations 
                        WHERE id = ?;
                    """
                    
                    var statement: OpaquePointer?
                    defer { 
                        if statement != nil {
                            sqlite3_finalize(statement) 
                        }
                    }
                    
                    guard sqlite3_prepare_v2(db, conversationSQL, -1, &statement, nil) == SQLITE_OK else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    
                    guard sqlite3_step(statement) == SQLITE_ROW else {
                        continuation.resume(throwing: StorageError.conversationNotFound)
                        return
                    }
                    
                    guard let conversationIdPtr = sqlite3_column_text(statement, 0),
                          let titlePtr = sqlite3_column_text(statement, 1),
                          let modelNamePtr = sqlite3_column_text(statement, 4) else {
                        continuation.resume(throwing: StorageError.databaseCorrupted)
                        return
                    }
                    
                    let conversationId = String(cString: conversationIdPtr)
                    let title = String(cString: titlePtr)
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                    let modelName = String(cString: modelNamePtr)
                    
                    let hfServerIdPtr = sqlite3_column_text(statement, 5)
                    let serverId = hfServerIdPtr != nil ? String(cString: hfServerIdPtr!) : conversationId
                    
                    sqlite3_finalize(statement)
                    statement = nil
                    
                    // Load messages (this should also be called from dbQueue)
                    let messages = try self.loadMessagesSync(for: conversationId)
                    
                    let conversation = Conversation(
                        serverId: serverId,
                        title: title,
                        modelId: modelName,
                        updatedAt: updatedAt,
                        messages: messages,
                        areMessagesLoaded: true
                    )
                    
                    continuation.resume(returning: conversation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadMessages(for conversationId: String) async throws -> [Message] {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    let messages = try self.loadMessagesSync(for: conversationId)
                    continuation.resume(returning: messages)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadMessagesSync(for conversationId: String) throws -> [Message] {
        // This method assumes it's already being called from dbQueue
        guard let db = self.db else {
            throw StorageError.localStorageUnavailable
        }
        
        let sql = """
            SELECT id, type, content, timestamp, metadata 
            FROM messages 
            WHERE conversation_id = ? 
            ORDER BY timestamp ASC;
        """
        
        var statement: OpaquePointer?
        defer { 
            if statement != nil {
                sqlite3_finalize(statement) 
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.invalidData
        }
        
        sqlite3_bind_text(statement, 1, conversationId, -1, nil)
        
        var messages: [Message] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let contentPtr = sqlite3_column_text(statement, 2) else {
                continue // Skip corrupted messages
            }
            
            let id = String(cString: idPtr)
            let type = Int(sqlite3_column_int(statement, 1))
            let content = String(cString: contentPtr)
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            
            let message = Message(
                id: id,
                content: content,
                author: type == 0 ? .user : .assistant,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            
            messages.append(message)
        }
        
        return messages
    }
    
    func saveMessage(_ message: MessageRow, to conversationId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    guard let db = self.db else {
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    let messageId = UUID().uuidString
                    let typeValue = message.type == .user ? 0 : 1
                    let content = message.contentType.text
                    let timestamp = Date()
                    
                    let sql = """
                        INSERT INTO messages (id, conversation_id, type, content, timestamp) 
                        VALUES (?, ?, ?, ?, ?);
                    """
                    
                    var statement: OpaquePointer?
                    defer { 
                        if statement != nil {
                            sqlite3_finalize(statement) 
                        }
                    }
                    
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, messageId, -1, nil)
                    sqlite3_bind_text(statement, 2, conversationId, -1, nil)
                    sqlite3_bind_int(statement, 3, Int32(typeValue))
                    sqlite3_bind_text(statement, 4, content, -1, nil)
                    sqlite3_bind_double(statement, 5, timestamp.timeIntervalSince1970)
                    
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    // Update conversation updated_at timestamp (synchronously in same queue)
                    try self.updateConversationTimestampSync(conversationId)
                    
                    print("💬 Saved message to local database")
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func updateConversationTimestamp(_ conversationId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    try self.updateConversationTimestampSync(conversationId)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func updateConversationTimestampSync(_ conversationId: String) throws {
        // This method assumes it's already being called from dbQueue
        guard let db = self.db else {
            throw StorageError.localStorageUnavailable
        }
        
        let sql = "UPDATE conversations SET updated_at = ? WHERE id = ?;"
        
        var statement: OpaquePointer?
        defer { 
            if statement != nil {
                sqlite3_finalize(statement) 
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.invalidData
        }
        
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, conversationId, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.invalidData
        }
    }
    
    func deleteConversation(id: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    guard let db = self.db else {
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    let sql = "DELETE FROM conversations WHERE id = ?;"
                    
                    var statement: OpaquePointer?
                    defer { 
                        if statement != nil {
                            sqlite3_finalize(statement) 
                        }
                    }
                    
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        continuation.resume(throwing: StorageError.conversationNotFound)
                        return
                    }
                    
                    print("🗑️ Deleted local conversation: \(id)")
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateConversationTitle(id: String, title: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    guard let db = self.db else {
                        continuation.resume(throwing: StorageError.localStorageUnavailable)
                        return
                    }
                    
                    let sql = """
                        UPDATE conversations 
                        SET title = ?, updated_at = ? 
                        WHERE id = ?;
                    """
                    
                    var statement: OpaquePointer?
                    defer { 
                        if statement != nil {
                            sqlite3_finalize(statement) 
                        }
                    }
                    
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        continuation.resume(throwing: StorageError.invalidData)
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, title, -1, nil)
                    sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
                    sqlite3_bind_text(statement, 3, id, -1, nil)
                    
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        continuation.resume(throwing: StorageError.conversationNotFound)
                        return
                    }
                    
                    print("📝 Updated conversation title: \(title)")
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Database Health Check
    
    private func isDatabaseHealthy() -> Bool {
        // This method assumes it's already being called from dbQueue
        guard let db = db else {
            print("❌ Database pointer is nil")
            return false
        }
        
        let sql = "SELECT 1;"
        var statement: OpaquePointer?
        defer { 
            if statement != nil {
                sqlite3_finalize(statement) 
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Cannot prepare health check statement")
            return false
        }
        
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            print("✅ Database health check passed")
            return true
        } else {
            print("❌ Database health check failed with result: \(result)")
            return false
        }
    }
}
