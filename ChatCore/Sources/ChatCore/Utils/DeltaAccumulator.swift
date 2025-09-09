import Foundation

/// Utility to compute incremental delta substrings for a growing string buffer.
/// If the new text does not have the previous text as prefix (e.g. rewind / replace),
/// it treats the entire new text as a delta (conservative fallback).
public struct DeltaAccumulator {
    private var previous: String = ""
    public init() {}
    public mutating func delta(new: String) -> String {
        if new.hasPrefix(previous) {
            let delta = String(new.dropFirst(previous.count))
            previous = new
            return delta
        } else {
            previous = new
            return new
        }
    }
    public mutating func reset() { previous = "" }
}