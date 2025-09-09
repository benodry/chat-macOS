import XCTest
@testable import ChatCore

final class GeminiProviderTests: XCTestCase {
    func testGeminiProviderBasics() async throws {
        // Test with mock API key - provider should initialize without errors
        let provider = GeminiProvider(configuration: .init(apiKey: "test-key"))
        
        // Test capabilities
        let capabilities = provider.capabilities()
        XCTAssertTrue(capabilities.supportsTools)
        XCTAssertTrue(capabilities.supportsReasoning)
        XCTAssertTrue(capabilities.supportsStreaming)
        XCTAssertEqual(capabilities.maxContextTokens, 1_048_576)
        
        // Test kind
        XCTAssertEqual(provider.kind, .gemini)
        
        // Test models list
        let models = try await provider.listModels()
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains { $0.modelId == "gemini-1.5-flash" })
        XCTAssertTrue(models.contains { $0.modelId == "gemini-2.0-flash-exp" })
    }
}

final class BedrockProviderTests: XCTestCase {
    func testBedrockProviderBasics() async throws {
        // Test with mock AWS credentials - provider should initialize without errors
        let provider = BedrockProvider(configuration: .init(
            accessKeyId: "test-access-key",
            secretAccessKey: "test-secret-key"
        ))
        
        // Test capabilities
        let capabilities = provider.capabilities()
        XCTAssertTrue(capabilities.supportsTools)
        XCTAssertTrue(capabilities.supportsReasoning)
        XCTAssertTrue(capabilities.supportsStreaming)
        XCTAssertEqual(capabilities.maxContextTokens, 200_000)
        
        // Test kind
        XCTAssertEqual(provider.kind, .bedrock)
        
        // Test models list
        let models = try await provider.listModels()
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains { $0.modelId.contains("claude-3-5-sonnet") })
        XCTAssertTrue(models.contains { $0.modelId.contains("llama3-1") })
    }
    
    func testBedrockConfiguration() {
        let config = BedrockProvider.Configuration(
            accessKeyId: "test-key", 
            secretAccessKey: "test-secret",
            region: "us-west-2"
        )
        
        XCTAssertEqual(config.region, "us-west-2")
        XCTAssertTrue(config.baseURL.absoluteString.contains("us-west-2"))
    }
}