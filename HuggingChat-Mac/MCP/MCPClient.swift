//
//  MCPClient.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import Foundation
import Combine

/// Main MCP client for managing servers and routing requests
@Observable class MCPClient {
    
    // MARK: - Properties
    
    var servers: [MCPServer] = []
    var availableTools: [MCPTool] = []
    var isDiscovering: Bool = false
    var lastError: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private let session = URLSession.shared
    private let serverManager = MCPServerManager()
    private let toolSelector = MCPToolSelector()
    
    // MARK: - Initialization
    
    init() {
        loadConfiguration()
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Discover and verify all configured MCP servers
    func discoverServers() async {
        await MainActor.run {
            isDiscovering = true
        }
        
        do {
            let discoveredServers = try await serverManager.discoverServers()
            
            await MainActor.run {
                self.servers = discoveredServers
                self.availableTools = discoveredServers.flatMap { $0.tools }
                self.isDiscovering = false
            }
            
            // Verify server health in background
            await verifyAllServers()
            
        } catch {
            await MainActor.run {
                self.lastError = error
                self.isDiscovering = false
            }
        }
    }
    
    /// Find the best tool for a given request
    func selectTool(for request: MCPToolRequest) async -> MCPToolSelection? {
        return await toolSelector.selectBestTool(
            for: request,
            from: availableTools,
            servers: servers
        )
    }
    
    /// Execute a tool with given parameters
    func executeTool(
        _ tool: MCPTool,
        server: MCPServer,
        parameters: [String: String]
    ) async throws -> MCPResponse {
        guard let serverURL = URL(string: server.baseURL) else {
            throw MCPClientError.invalidServerURL
        }
        
        let request = MCPRequest(
            method: "tools/call",
            params: [
                "name": tool.name,
                // Flatten parameters dictionary into string values
                "arguments": try JSONEncoder().encode(parameters).flatMap { String(data: Data([$0]), encoding: .utf8) }.joined()
            ]
        )
        
        return try await networkRequest(to: serverURL.appendingPathComponent("mcp"), request: request)
    }
    
    /// Add a new server configuration
    func addServer(_ server: MCPServer) {
        servers.append(server)
        saveConfiguration()
    }
    
    /// Remove a server
    func removeServer(_ server: MCPServer) {
        servers.removeAll { $0.id == server.id }
        availableTools.removeAll { $0.serverID == server.id }
        saveConfiguration()
    }
    
    /// Update server status
    func refreshServerStatus(_ server: MCPServer) async {
        let updatedServer = await serverManager.verifyServer(server)
        
        await MainActor.run {
            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index] = updatedServer
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Auto-save when servers change
//        $servers
//            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
//            .sink { [weak self] _ in
//                self?.saveConfiguration()
//            }
//            .store(in: &cancellables)
        // Remove $servers and debounce for macro-based observation
        // If you need to observe changes, use a didSet on servers or handle in MainActor
    }
    
    private func verifyAllServers() async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask { [weak self] in
                    await self?.refreshServerStatus(server)
                }
            }
        }
    }
    
    private func networkRequest(to url: URL, request: MCPRequest) async throws -> MCPResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestData = try JSONEncoder().encode(request)
        urlRequest.httpBody = requestData
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw MCPClientError.serverError(httpResponse.statusCode)
        }
        
        let mcpResponse = try JSONDecoder().decode(MCPResponse.self, from: data)
        
        if let error = mcpResponse.error {
            throw MCPClientError.mcpError(error)
        }
        
        return mcpResponse
    }
    
    private func loadConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "MCPServers"),
           let loadedServers = try? JSONDecoder().decode([MCPServer].self, from: data) {
            servers = loadedServers
        } else {
            // Load default servers
            servers = defaultServers()
        }
    }
    
    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: "MCPServers")
        }
    }
    
    private func defaultServers() -> [MCPServer] {
        return [
            MCPServer(
                name: "Local File System",
                baseURL: "http://localhost:3001",
                description: "Local file system operations"
            ),
            MCPServer(
                name: "Web Search",
                baseURL: "http://localhost:3002",
                description: "Web search and browsing capabilities"
            ),
            MCPServer(
                name: "Database Query",
                baseURL: "http://localhost:3003",
                description: "Database query and management"
            )
        ]
    }
}

// MARK: - Error Types

enum MCPClientError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case serverError(Int)
    case mcpError(MCPError)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .mcpError(let error):
            return "MCP Error: \(error.message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
