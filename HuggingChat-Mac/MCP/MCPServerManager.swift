//
//  MCPServerManager.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import Foundation
import Network

/// Manages MCP server discovery and verification
class MCPServerManager {
    
    private let session = URLSession.shared
    private let timeout: TimeInterval = 10.0
    
    // MARK: - Server Discovery
    
    /// Discover all configured servers and fetch their capabilities
    func discoverServers() async throws -> [MCPServer] {
        let configuredServers = loadServerConfiguration()
        
        return await withTaskGroup(of: MCPServer.self, returning: [MCPServer].self) { group in
            var servers: [MCPServer] = []
            
            for server in configuredServers {
                group.addTask {
                    await self.verifyServer(server)
                }
            }
            
            for await server in group {
                servers.append(server)
            }
            
            return servers
        }
    }
    
    /// Verify a single server's status and capabilities
    func verifyServer(_ server: MCPServer) async -> MCPServer {
        var updatedServer = server
        
        do {
            // Check server health
            let isHealthy = try await checkServerHealth(server)
            
            if isHealthy {
                // Fetch capabilities
                if let capabilities = try await fetchCapabilities(server) {
                    updatedServer.capabilities = capabilities
                }
                
                // Fetch available tools
                let tools = try await fetchTools(server)
                updatedServer.tools = tools
                updatedServer.status = .online
            } else {
                updatedServer.status = .offline
            }
            
        } catch {
            updatedServer.status = .error
            print("Error verifying server \(server.name): \(error)")
        }
        
        return updatedServer
    }
    
    // MARK: - Network Operations
    
    private func checkServerHealth(_ server: MCPServer) async throws -> Bool {
        guard let url = URL(string: "\(server.baseURL)/health") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        
        do {
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return 200...299 ~= httpResponse.statusCode
            }
            return false
        } catch {
            return false
        }
    }
    
    private func fetchCapabilities(_ server: MCPServer) async throws -> MCPCapabilities? {
        guard let url = URL(string: "\(server.baseURL)/capabilities") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            return nil
        }
        
        return try JSONDecoder().decode(MCPCapabilities.self, from: data)
    }
    
    private func fetchTools(_ server: MCPServer) async throws -> [MCPTool] {
        guard let url = URL(string: "\(server.baseURL)/tools") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return []
            }
            
            let toolsResponse = try JSONDecoder().decode(ToolsResponse.self, from: data)
            
            // Convert to MCPTool and associate with server
            return toolsResponse.tools.map { toolData in
                MCPTool(
                    name: toolData.name,
                    description: toolData.description,
                    serverID: server.id,
                    inputSchema: toolData.inputSchema,
                    outputSchema: toolData.outputSchema,
                    category: determineCategory(from: toolData.name, description: toolData.description),
                    tags: toolData.tags ?? []
                )
            }
        } catch {
            print("Error fetching tools for \(server.name): \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineCategory(from name: String, description: String) -> MCPToolCategory {
        let combinedText = "\(name) \(description)".lowercased()
        
        if combinedText.contains("search") || combinedText.contains("find") {
            return .search
        } else if combinedText.contains("file") || combinedText.contains("directory") {
            return .fileSystem
        } else if combinedText.contains("web") || combinedText.contains("http") || combinedText.contains("url") {
            return .web
        } else if combinedText.contains("database") || combinedText.contains("sql") || combinedText.contains("query") {
            return .database
        } else if combinedText.contains("api") || combinedText.contains("request") {
            return .api
        } else if combinedText.contains("ai") || combinedText.contains("ml") || combinedText.contains("model") {
            return .ai
        } else if combinedText.contains("utility") || combinedText.contains("helper") || combinedText.contains("tool") {
            return .utility
        }
        
        return .other
    }
    
    private func loadServerConfiguration() -> [MCPServer] {
        // In a real implementation, this could load from:
        // - UserDefaults
        // - Configuration file
        // - Environment variables
        // - Network discovery (Bonjour, etc.)
        
        return [
            MCPServer(
                name: "Local File System",
                baseURL: "http://localhost:3001",
                description: "Local file system operations and file management"
            ),
            MCPServer(
                name: "Web Search",
                baseURL: "http://localhost:3002",
                description: "Web search, URL fetching, and content extraction"
            ),
            MCPServer(
                name: "Database Tools",
                baseURL: "http://localhost:3003",
                description: "Database queries and data management"
            ),
            MCPServer(
                name: "Development Tools",
                baseURL: "http://localhost:3004",
                description: "Code analysis, testing, and development utilities"
            )
        ]
    }
}

// MARK: - Supporting Types

private struct ToolsResponse: Codable {
    let tools: [ToolData]
}

private struct ToolData: Codable {
    let name: String
    let description: String
    let inputSchema: MCPToolSchema?
    let outputSchema: MCPToolSchema?
    let tags: [String]?
}
