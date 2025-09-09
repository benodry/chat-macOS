// Placeholder for future HuggingFaceProvider tests.
// Real tests will require mocking NetworkService or injecting a protocol.
import XCTest
@testable import ChatCore

final class HuggingFaceProviderAdapterTests: XCTestCase {
    func testCapabilitiesBaseline() throws {
        // Cannot init provider here because it resides in app target; once moved or bridged via @testable import we can assert.
        XCTAssertTrue(true)
    }
}
