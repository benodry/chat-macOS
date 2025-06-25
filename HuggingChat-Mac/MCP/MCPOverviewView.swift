//
//  MCPOverviewView.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import SwiftUI

/// Overview of all MCP servers and tools
struct MCPOverviewView: View {
    @Bindable var mcpClient: MCPClient
    @State private var selectedCategory: MCPToolCategory = .search
    
    private var toolsByCategory: [MCPToolCategory: [MCPTool]] {
        Dictionary(grouping: mcpClient.availableTools) { $0.category }
    }
    
    private var serverStatistics: (online: Int, offline: Int, total: Int) {
        let online = mcpClient.servers.filter { $0.status == .online }.count
        let offline = mcpClient.servers.count - online
        return (online: online, offline: offline, total: mcpClient.servers.count)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statisticsSection
                toolCategoriesSection
                recentActivitySection
            }
            .padding()
        }
        .navigationTitle("MCP Overview")
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Context Protocol")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Manage servers and tools for enhanced AI capabilities")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var statisticsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
            StatCard(
                title: "Servers",
                value: "\(serverStatistics.total)",
                subtitle: "\(serverStatistics.online) online",
                icon: "server.rack",
                color: .blue
            )
            
            StatCard(
                title: "Tools",
                value: "\(mcpClient.availableTools.count)",
                subtitle: "\(toolsByCategory.keys.count) categories",
                icon: "wrench.and.screwdriver",
                color: .green
            )
            
            StatCard(
                title: "Status",
                value: mcpClient.isDiscovering ? "Syncing" : "Ready",
                subtitle: mcpClient.isDiscovering ? "Discovering..." : "All systems",
                icon: mcpClient.isDiscovering ? "arrow.clockwise" : "checkmark.circle",
                color: mcpClient.isDiscovering ? .orange : .green
            )
        }
    }
    
    private var toolCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Tools by Category")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(MCPToolCategory.allCases, id: \.self) { category in
                    let toolCount = toolsByCategory[category]?.count ?? 0
                    
                    CategoryCard(
                        category: category,
                        toolCount: toolCount,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            
            if !toolsByCategory[selectedCategory, default: []].isEmpty {
                toolListForCategory
            }
        }
    }
    
    private var toolListForCategory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools in \(selectedCategory.displayName)")
                .font(.subheadline)
                .fontWeight(.medium)
            
            LazyVStack(spacing: 4) {
                ForEach(toolsByCategory[selectedCategory, default: []], id: \.id) { tool in
                    ToolRowView(tool: tool, mcpClient: mcpClient)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                ActionButton(
                    title: "Refresh All",
                    icon: "arrow.clockwise",
                    color: .blue
                ) {
                    Task {
                        await mcpClient.discoverServers()
                    }
                }
                
                ActionButton(
                    title: "Add Server",
                    icon: "plus",
                    color: .green
                ) {
                    // This would be handled by parent view
                }
                
                ActionButton(
                    title: "Settings",
                    icon: "gear",
                    color: .gray
                ) {
                    // Open MCP settings
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct CategoryCard: View {
    let category: MCPToolCategory
    let toolCount: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack {
                    Text(category.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(toolCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                HStack {
                    Text("tools available")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    
                    Spacer()
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ToolRowView: View {
    let tool: MCPTool
    @Bindable var mcpClient: MCPClient
    
    private var server: MCPServer? {
        mcpClient.servers.first { $0.id == tool.serverID }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let server = server {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(server.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    StatusIndicator(status: server.status)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    MCPOverviewView(mcpClient: MCPClient())
        .frame(width: 800, height: 600)
}
