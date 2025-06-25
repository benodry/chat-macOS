//
//  MCPIntegration.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import Foundation
import SwiftUI

/// Integration layer between MCP and the main conversation system
@Observable class MCPIntegration {
    
    // MARK: - Properties
    
    private let mcpClient = MCPClient()
    private let toolSelector = MCPToolSelector()
    
    var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "mcpEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "mcpEnabled")
        }
    }
    
    var autoSelectTools: Bool {
        get {
            UserDefaults.standard.bool(forKey: "mcpAutoSelectTools")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "mcpAutoSelectTools")
        }
    }
    
    // MARK: - Public Methods
    
    /// Process a user message and optionally enhance it with MCP tools
    func processMessage(
        _ messageText: String,
        context: String? = nil
    ) async -> MCPProcessingResult {
        
        guard isEnabled else {
            return MCPProcessingResult(
                originalMessage: messageText,
                enhancedMessage: messageText,
                toolsUsed: [],
                suggestions: []
            )
        }
        
        // Ensure servers are discovered
        await mcpClient.discoverServers()
        
        // Create tool request
        let toolRequest = MCPToolRequest(
            userQuery: messageText,
            context: context,
            preferredCategories: inferCategoriesFromMessage(messageText),
            maxResults: 3
        )
        
        if autoSelectTools {
            return await processWithAutoSelection(messageText, toolRequest: toolRequest)
        } else {
            return await processWithSuggestions(messageText, toolRequest: toolRequest)
        }
    }
    
    /// Get available MCP servers and tools for settings/configuration
    func getMCPClient() -> MCPClient {
        return mcpClient
    }
    
    /// Execute a specific tool with parameters
    func executeTool(
        _ tool: MCPTool,
        parameters: [String: String]
    ) async throws -> MCPToolExecutionResult {
        
        guard let server = mcpClient.servers.first(where: { $0.id == tool.serverID }) else {
            throw MCPIntegrationError.serverNotFound
        }
        
        let response = try await mcpClient.executeTool(tool, server: server, parameters: parameters)
        
        return MCPToolExecutionResult(
            tool: tool,
            server: server,
            response: response,
            success: response.error == nil
        )
    }
    
    // MARK: - Private Methods
    
    private func processWithAutoSelection(
        _ messageText: String,
        toolRequest: MCPToolRequest
    ) async -> MCPProcessingResult {
        
        if let selection = await mcpClient.selectTool(for: toolRequest) {
            // Attempt to auto-execute the tool if confidence is high
            if selection.confidence > 0.8 {
                do {
                    let result = try await executeTool(selection.tool, parameters: [:])
                    let enhancedMessage = enhanceMessageWithToolResult(messageText, result: result)
                    
                    return MCPProcessingResult(
                        originalMessage: messageText,
                        enhancedMessage: enhancedMessage,
                        toolsUsed: [result],
                        suggestions: []
                    )
                } catch {
                    // Fall back to suggestions if execution fails
                    return MCPProcessingResult(
                        originalMessage: messageText,
                        enhancedMessage: messageText,
                        toolsUsed: [],
                        suggestions: [selection]
                    )
                }
            } else {
                // Suggest the tool instead of auto-executing
                return MCPProcessingResult(
                    originalMessage: messageText,
                    enhancedMessage: messageText,
                    toolsUsed: [],
                    suggestions: [selection]
                )
            }
        }
        
        return MCPProcessingResult(
            originalMessage: messageText,
            enhancedMessage: messageText,
            toolsUsed: [],
            suggestions: []
        )
    }
    
    private func processWithSuggestions(
        _ messageText: String,
        toolRequest: MCPToolRequest
    ) async -> MCPProcessingResult {
        
        let suggestions = await toolSelector.suggestTools(
            for: toolRequest,
            from: mcpClient.availableTools,
            servers: mcpClient.servers
        )
        
        return MCPProcessingResult(
            originalMessage: messageText,
            enhancedMessage: messageText,
            toolsUsed: [],
            suggestions: suggestions
        )
    }
    
    private func enhanceMessageWithToolResult(
        _ originalMessage: String,
        result: MCPToolExecutionResult
    ) -> String {
        
        guard result.success,
              let content = result.response.result?.content?.first?.text else {
            return originalMessage
        }
        
        return """
        \(originalMessage)
        
        [MCP Tool: \(result.tool.name)]
        \(content)
        """
    }
    
    private func inferCategoriesFromMessage(_ message: String) -> [MCPToolCategory] {
        let lowercased = message.lowercased()
        var categories: [MCPToolCategory] = []
        
        // Search-related keywords
        if lowercased.contains("search") || lowercased.contains("find") || lowercased.contains("look up") {
            categories.append(.search)
        }
        
        // File-related keywords
        if lowercased.contains("file") || lowercased.contains("save") || lowercased.contains("open") {
            categories.append(.fileSystem)
        }
        
        // Web-related keywords
        if lowercased.contains("website") || lowercased.contains("url") || lowercased.contains("web") {
            categories.append(.web)
        }
        
        // Database-related keywords
        if lowercased.contains("data") || lowercased.contains("query") || lowercased.contains("database") {
            categories.append(.database)
        }
        
        // If no specific categories found, return empty array for all categories
        return categories
    }
}

// MARK: - Result Types

/// Result of MCP processing
struct MCPProcessingResult {
    let originalMessage: String
    let enhancedMessage: String
    let toolsUsed: [MCPToolExecutionResult]
    let suggestions: [MCPToolSelection]
}

/// Result of tool execution
struct MCPToolExecutionResult {
    let tool: MCPTool
    let server: MCPServer
    let response: MCPResponse
    let success: Bool
    
    var displayText: String {
        if success, let content = response.result?.content?.first?.text {
            return content
        } else if let error = response.error {
            return "Error: \(error.message)"
        } else {
            return "Tool executed successfully"
        }
    }
}

// MARK: - Errors

enum MCPIntegrationError: LocalizedError {
    case serverNotFound
    case toolExecutionFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "MCP server not found"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .invalidResponse:
            return "Invalid response from MCP server"
        }
    }
}
