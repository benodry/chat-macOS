//
//  MCPModels.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import Foundation

// MARK: - MCP Server Models

/// Represents an MCP server configuration
struct MCPServer: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let description: String?
    var status: MCPServerStatus = .unknown
    var capabilities: MCPCapabilities?
    var tools: [MCPTool] = []
    
    enum CodingKeys: String, CodingKey {
        case name, baseURL, description, status, capabilities, tools
    }
}

/// Server status enumeration
enum MCPServerStatus: String, Codable, CaseIterable {
    case online = "online"
    case offline = "offline"
    case error = "error"
    case unknown = "unknown"
    
    var color: String {
        switch self {
        case .online: return "green"
        case .offline: return "gray"
        case .error: return "red"
        case .unknown: return "yellow"
        }
    }
}

/// Server capabilities
struct MCPCapabilities: Codable, Equatable, Hashable {
    let supportedMethods: [String]
    let maxRequestSize: Int?
    let timeout: TimeInterval?
    let authentication: MCPAuthType?
}

enum MCPAuthType: String, Codable {
    case none = "none"
    case apiKey = "api_key"
    case bearer = "bearer"
    case basic = "basic"
}

// MARK: - MCP Tool Models

/// Represents a tool available on an MCP server
struct MCPTool: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let serverID: UUID?
    let inputSchema: MCPToolSchema?
    let outputSchema: MCPToolSchema?
    let category: MCPToolCategory
    let tags: [String]
    
    enum CodingKeys: String, CodingKey {
        case name, description, serverID, inputSchema, outputSchema, category, tags
    }
}

/// Tool categories for easier classification and selection
enum MCPToolCategory: String, Codable, CaseIterable {
    case search = "search"
    case fileSystem = "file_system"
    case web = "web"
    case database = "database"
    case api = "api"
    case utility = "utility"
    case ai = "ai"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .search: return "Search"
        case .fileSystem: return "File System"
        case .web: return "Web"
        case .database: return "Database"
        case .api: return "API"
        case .utility: return "Utility"
        case .ai: return "AI"
        case .other: return "Other"
        }
    }
}

/// Tool input/output schema
struct MCPToolSchema: Codable, Equatable, Hashable {
    let type: String
    let properties: [String: MCPProperty]?
    let required: [String]?
}

struct MCPProperty: Codable, Equatable, Hashable {
    let type: String
    let description: String?
    let enumValues: [String]?
    let defaultValue: String?
        
    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
        case defaultValue = "default"
    }
}

// MARK: - MCP Request/Response Models

/// Generic MCP request structure
struct MCPRequest: Codable {
    let method: String
    let params: [String: String]?
    let id: String
    
    init(method: String, params: [String: String]? = nil) {
        self.method = method
        self.params = params
        self.id = UUID().uuidString
    }
    
    enum CodingKeys: String, CodingKey {
        case method, params, id
    }
    
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(method, forKey: .method)
//        try container.encode(id, forKey: .id)
//
//        if let params = params {
//            let data = try JSONSerialization.data(withJSONObject: params)
//            let jsonObject = try JSONSerialization.jsonObject(with: data)
//            try container.encode(jsonObject as! [String: String], forKey: .params)
//        }
//    }
}

/// Generic MCP response structure
struct MCPResponse: Codable {
    let id: String
    let result: MCPResult?
    let error: MCPError?
}

struct MCPResult: Codable {
    let content: [MCPContent]?
    let isError: Bool?
    let data: [String: String]?
}

struct MCPContent: Codable {
    let type: String
    let text: String?
    let data: String?
}

struct MCPError: Codable {
    let code: Int
    let message: String
    let data: String?
}

// MARK: - Tool Selection Models

/// Represents a request for tool selection
struct MCPToolRequest {
    let userQuery: String
    let context: String?
    let preferredCategories: [MCPToolCategory]
    let maxResults: Int
    
    init(userQuery: String, context: String? = nil, preferredCategories: [MCPToolCategory] = [], maxResults: Int = 5) {
        self.userQuery = userQuery
        self.context = context
        self.preferredCategories = preferredCategories
        self.maxResults = maxResults
    }
}

/// Result of tool selection process
struct MCPToolSelection {
    let tool: MCPTool
    let server: MCPServer
    let confidence: Double
    let reasoning: String
}
