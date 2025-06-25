//
//  MCPView.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import SwiftUI

/// Main MCP management view
struct MCPView: View {
    @State private var mcpClient = MCPClient() // Changed from @StateObject to @State for @Observable/@Bindable compatibility
    @State private var selectedServer: MCPServer?
    @State private var showingAddServer = false
    @State private var searchText = ""
    
    var filteredServers: [MCPServer] {
        if searchText.isEmpty {
            return mcpClient.servers
        } else {
            return mcpClient.servers.filter { server in
                server.name.localizedCaseInsensitiveContains(searchText) ||
                server.description?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    var filteredTools: [MCPTool] {
        if searchText.isEmpty {
            return mcpClient.availableTools
        } else {
            return mcpClient.availableTools.filter { tool in
                tool.name.localizedCaseInsensitiveContains(searchText) ||
                tool.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - Server List
            VStack(alignment: .leading, spacing: 0) {
                headerView
                searchBar
                serverList
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            // Detail View
            if let selectedServer = selectedServer {
                ServerDetailView(server: selectedServer, mcpClient: mcpClient)
            } else {
                MCPOverviewView(mcpClient: mcpClient) // Pass as @Bindable
            }
        }
        .task {
            await mcpClient.discoverServers()
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerView(mcpClient: mcpClient) // Pass as @Bindable
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("MCP Servers")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: {
                Task {
                    await mcpClient.discoverServers()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(mcpClient.isDiscovering)
            
            Button(action: {
                showingAddServer = true
            }) {
                Image(systemName: "plus")
            }
        }
        .padding()
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search servers and tools...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var serverList: some View {
        List(filteredServers, selection: $selectedServer) { server in
            ServerRowView(server: server)
                .contextMenu {
                    Button("Refresh") {
                        Task {
                            await mcpClient.refreshServerStatus(server)
                        }
                    }
                    
                    Button("Remove", role: .destructive) {
                        mcpClient.removeServer(server)
                    }
                }
        }
        .listStyle(SidebarListStyle())
    }
}

// MARK: - Server Row View

struct ServerRowView: View {
    let server: MCPServer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(server.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                StatusIndicator(status: server.status)
            }
            
            if let description = server.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Text("\(server.tools.count) tools")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(server.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: MCPServerStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch status {
        case .online:
            return .green
        case .offline:
            return .gray
        case .error:
            return .red
        case .unknown:
            return .yellow
        }
    }
}

// MARK: - Preview

#Preview {
    MCPView()
        .frame(width: 1000, height: 700)
}
