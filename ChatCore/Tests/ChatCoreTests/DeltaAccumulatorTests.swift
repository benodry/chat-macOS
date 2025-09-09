import XCTest
@testable import ChatCore

final class DeltaAccumulatorTests: XCTestCase {
    func testIncrementalDeltas() {
        var acc = DeltaAccumulator()
        XCTAssertEqual(acc.delta(new: "H"), "H")
        XCTAssertEqual(acc.delta(new: "He"), "e")
        XCTAssertEqual(acc.delta(new: "Hel"), "l")
        XCTAssertEqual(acc.delta(new: "Hello"), "lo")
    }
    func testReplacementFallback() {
        var acc = DeltaAccumulator()
        _ = acc.delta(new: "Hello")
        // Now a non-prefix update (e.g. model rewrites output)
        XCTAssertEqual(acc.delta(new: "Hi"), "Hi")
    }
}