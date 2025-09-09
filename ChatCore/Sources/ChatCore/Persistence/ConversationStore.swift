import Foundation

public protocol ConversationStore {
    func create(_ conversation: ChatConversation) throws
    func loadAll() throws -> [ChatConversation]
    func load(id: UUID) throws -> ChatConversation?
    func save(_ conversation: ChatConversation) throws
    func appendMessage(conversationId: UUID, message: ChatMessage) throws
    /// Upsert a partial assistant message (by temporary UUID) during streaming.
    /// If message with same id exists and is last, replace; else append.
    func upsertPartialAssistant(conversationId: UUID, message: ChatMessage) throws
    func delete(id: UUID) throws
}

public final class JSONConversationStore: ConversationStore {
    private let root: URL
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "json.conversation.store", qos: .utility)
    
    public init(rootDirectory: URL) throws {
        self.root = rootDirectory
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }
    
    private func url(for id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json") }
    
    public func create(_ conversation: ChatConversation) throws {
        let path = url(for: conversation.id)
        guard !fm.fileExists(atPath: path.path) else { throw StoreError.alreadyExists }
        try write(conversation, to: path)
    }
    
    public func loadAll() throws -> [ChatConversation] {
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try files.compactMap { file -> ChatConversation? in
            guard file.pathExtension == "json" else { return nil }
            let data = try Data(contentsOf: file)
            return try decoder.decode(ChatConversation.self, from: data)
        }.sorted(by: { $0.updatedAt > $1.updatedAt })
    }
    
    public func load(id: UUID) throws -> ChatConversation? {
        let path = url(for: id)
        guard fm.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try decoder.decode(ChatConversation.self, from: data)
    }
    
    public func save(_ conversation: ChatConversation) throws {
        let path = url(for: conversation.id)
        try write(conversation, to: path)
    }
    
    public func appendMessage(conversationId: UUID, message: ChatMessage) throws {
        let path = url(for: conversationId)
        guard fm.fileExists(atPath: path.path) else { throw StoreError.notFound }
        var convo = try decoder.decode(ChatConversation.self, from: Data(contentsOf: path))
        convo.messages.append(message)
        convo.updatedAt = Date()
        try write(convo, to: path)
    }
    public func upsertPartialAssistant(conversationId: UUID, message: ChatMessage) throws {
        let path = url(for: conversationId)
        guard fm.fileExists(atPath: path.path) else { throw StoreError.notFound }
        var convo = try decoder.decode(ChatConversation.self, from: Data(contentsOf: path))
        if let last = convo.messages.last, last.id == message.id {
            convo.messages.removeLast()
        }
        convo.messages.append(message)
        convo.updatedAt = Date()
        try write(convo, to: path)
    }
    
    public func delete(id: UUID) throws {
        let path = url(for: id)
        if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
    }
    
    private func write(_ convo: ChatConversation, to url: URL) throws {
        let data = try encoder.encode(convo)
        try data.write(to: url, options: .atomic)
    }
    
    public enum StoreError: Error { case alreadyExists, notFound }
}
