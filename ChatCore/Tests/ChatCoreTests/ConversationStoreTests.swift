import XCTest
@testable import ChatCore

final class ConversationStoreTests: XCTestCase {
    func testCreateLoadAppendDelete() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ChatCoreTests_\(UUID().uuidString)")
        let store = try JSONConversationStore(rootDirectory: temp)
        var convo = ChatConversation(provider: .openAI, modelId: "mock-model", title: "Test Conversation")
        try store.create(convo)
        var all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        let firstId = convo.id
        let msg = ChatMessage(role: .user, content: "Hello")
        try store.appendMessage(conversationId: firstId, message: msg)
        let loaded = try store.load(id: firstId)
        XCTAssertEqual(loaded?.messages.count, 1)
        convo.title = "Renamed"
        try store.save(convo)
        let renamed = try store.load(id: firstId)
        XCTAssertEqual(renamed?.title, "Renamed")
        try store.delete(id: firstId)
        all = try store.loadAll()
        XCTAssertEqual(all.count, 0)
    }
}
