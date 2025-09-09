import XCTest
@testable import ChatCore

final class MultiRemoteProviderTests: XCTestCase {
    func testGeminiExtractText() {
        let sample = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"},{\"text\":\" World\"}]}}]}"
        let text = GeminiProvider.extractText(from: sample, decoder: JSONDecoder())
        XCTAssertEqual(text, "Hello World")
    }
    func testBedrockParseDelta() {
        let sample = "{\"delta\":\"Chunk\"}"
        let obj = BedrockProvider.parseDelta(line: sample, decoder: JSONDecoder())
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.delta, "Chunk")
    }
    func testBedrockParseCompleted() {
        let sample = "{\"completed\":true}"
        let obj = BedrockProvider.parseDelta(line: sample, decoder: JSONDecoder())
        XCTAssertTrue(obj?.completed == true)
    }
}