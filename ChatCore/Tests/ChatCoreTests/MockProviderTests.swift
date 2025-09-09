import XCTest
@testable import ChatCore

final class MockProviderTests: XCTestCase {
    func testMockProviderEcho() async throws {
        let provider = MockProvider()
        let models = try await provider.listModels()
        XCTAssertFalse(models.isEmpty)
        let model = models[0]
        let user = ChatMessage(role: .user, content: "Ping")
        var streamed = ""
        let final = try await provider.send(messages: [user], model: model, config: GenerationConfig()) { event in
            if case let .token(t) = event { streamed.append(t) }
        }
        XCTAssertTrue(streamed.contains("Echo"))
        XCTAssertEqual(final.role, .assistant)
    }
}
