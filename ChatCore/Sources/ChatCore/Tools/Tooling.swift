import Foundation

public protocol Tool {
    var name: String { get }
    var description: String { get }
    /// Invoke tool with JSON arguments; return JSON result string
    func invoke(argumentsJSON: String) async throws -> String
}

public enum ToolError: Error, CustomStringConvertible {
    case notFound(String)
    case invocationFailed(String)
    public var description: String {
        switch self {
        case .notFound(let n): return "Tool not found: \(n)"
        case .invocationFailed(let r): return "Tool failed: \(r)"
        }
    }
}

public actor ToolRegistry {
    private var tools: [String: Tool] = [:]
    public init() {}
    public func register(_ tool: Tool) { tools[tool.name] = tool }
    public func unregister(name: String) { tools.removeValue(forKey: name) }
    public func listTools() -> [String] { Array(tools.keys).sorted() }
    public func invoke(name: String, argumentsJSON: String) async throws -> String {
        guard let tool = tools[name] else { throw ToolError.notFound(name) }
        return try await tool.invoke(argumentsJSON: argumentsJSON)
    }
}

// Simple echo tool for demos / tests
public struct EchoTool: Tool {
    public let name = "echo"
    public let description = "Echoes back provided JSON arguments under {\\\"echo\\\":...}"
    public init() {}
    public func invoke(argumentsJSON: String) async throws -> String {
        return "{\"echo\":\(argumentsJSON)}"
    }
}
