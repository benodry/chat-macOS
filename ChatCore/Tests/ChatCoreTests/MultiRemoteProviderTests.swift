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
    func testGeminiReasoningParse() {
        let line = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"<thinking>Chain of thought A</thinking>\"},{\"text\":\"Answer text\"}]}}]}"
        let parsed = GeminiProvider.parseLine(line, decoder: JSONDecoder())
        XCTAssertEqual(parsed.reasoning, "Chain of thought A")
        XCTAssertEqual(parsed.text, "Answer text")
    }
}

// MARK: - Model Listing Caching Tests
final class ModelListingCachingTests: XCTestCase {
    override class func setUp() {
        URLProtocol.registerClass(TestURLProtocol.self)
    }
    override class func tearDown() {
        URLProtocol.unregisterClass(TestURLProtocol.self)
        TestURLProtocol.reset()
    }
    func testGeminiModelListingCaching() async throws {
        TestURLProtocol.reset()
        TestURLProtocol.stubbedResponses["/v1beta/models"] = (200, "{\"models\":[{\"name\":\"models/gemini-1.5-pro\",\"displayName\":\"Gemini 1.5 Pro\",\"inputTokenLimit\":100000,\"supportedGenerationMethods\":[\"generateContent\"]}]}".data(using: .utf8)!)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let provider = GeminiProvider(configuration: .init(apiKey: "TEST", model: "gemini-1.5-pro"), session: session)
        let first = try await provider.listModels()
        let second = try await provider.listModels() // should hit cache
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(TestURLProtocol.requestCount(for: "/v1beta/models"), 1, "Second call should be cached")
        XCTAssertTrue(first[0].capabilities.supportsReasoning)
    }
    func testBedrockModelListingCaching() async throws {
        TestURLProtocol.reset()
        TestURLProtocol.stubbedResponses["/models"] = (200, "[{\"modelId\":\"anthropic.claude-3-sonnet\",\"reasoning\":true,\"tools\":false,\"context\":200000}]".data(using: .utf8)!)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let provider = BedrockProvider(configuration: .init(modelId: "anthropic.claude-3-sonnet", endpoint: URL(string: "https://bedrock.test")!), session: session)
        let first = try await provider.listModels()
        let second = try await provider.listModels()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(TestURLProtocol.requestCount(for: "/models"), 1)
        XCTAssertTrue(first[0].capabilities.supportsReasoning)
    }
}

// MARK: - Test URLProtocol
class TestURLProtocol: URLProtocol {
    static var stubbedResponses: [String: (Int, Data)] = [:]
    private static var counts: [String: Int] = [:]
    static func reset() { stubbedResponses = [:]; counts = [:] }
    static func requestCount(for path: String) -> Int { counts[path] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let path = request.url?.path else { return }
        Self.counts[path, default: 0] += 1
        if let (status, data) = Self.stubbedResponses[path] {
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"] )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}