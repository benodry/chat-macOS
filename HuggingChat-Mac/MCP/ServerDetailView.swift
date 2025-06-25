//
//  ServerDetailView.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import SwiftUI

/// Detailed view of a specific MCP server
struct ServerDetailView: View {
    let server: MCPServer
    @Bindable var mcpClient: MCPClient
    @State private var selectedTool: MCPTool?
    @State private var showingTestTool = false
    
    private var serverTools: [MCPTool] {
        mcpClient.availableTools.filter { $0.serverID == server.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    serverInfoSection
                    capabilitiesSection
                    toolsSection
                }
                .padding()
            }
        }
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task {
                        await mcpClient.refreshServerStatus(server)
                    }
                }
            }
        }
        .sheet(isPresented: $showingTestTool) {
            if let selectedTool = selectedTool {
                ToolTestView(tool: selectedTool, server: server, mcpClient: mcpClient)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let description = server.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                ServerStatusView(server: server)
            }
            
            HStack {
                Label(server.baseURL, systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !serverTools.isEmpty {
                    Label("\(serverTools.count) tools", systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    private var serverInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server Information")
                .font(.headline)
            
            InfoGrid {
                InfoRow(label: "URL", value: server.baseURL)
                InfoRow(label: "Status", value: server.status.rawValue.capitalized)
                InfoRow(label: "Tools", value: "\(serverTools.count)")
                
                if let capabilities = server.capabilities {
                    InfoRow(label: "Methods", value: "\(capabilities.supportedMethods.count)")
                    
                    if let timeout = capabilities.timeout {
                        InfoRow(label: "Timeout", value: "\(Int(timeout))s")
                    }
                    
                    if let auth = capabilities.authentication {
                        InfoRow(label: "Auth", value: auth.rawValue)
                    }
                }
            }
        }
    }
    
    private var capabilitiesSection: some View {
        Group {
            if let capabilities = server.capabilities {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Capabilities")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if !capabilities.supportedMethods.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supported Methods")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                FlowLayout {
                                    ForEach(capabilities.supportedMethods, id: \.self) { method in
                                        MethodTag(method: method)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Tools")
                    .font(.headline)
                
                Spacer()
                
                if !serverTools.isEmpty {
                    Menu("Sort") {
                        Button("By Name") { /* TODO: Implement sorting */ }
                        Button("By Category") { /* TODO: Implement sorting */ }
                    }
                }
            }
            
            if serverTools.isEmpty {
                EmptyToolsView()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(serverTools, id: \.id) { tool in
                        ToolDetailCard(tool: tool) {
                            selectedTool = tool
                            showingTestTool = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ServerStatusView: View {
    let server: MCPServer
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                StatusIndicator(status: server.status)
                Text(server.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if server.status == .online {
                Text("Last checked: now")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InfoGrid<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            content
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct MethodTag: View {
    let method: String
    
    var body: some View {
        Text(method)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(4)
    }
}

struct ToolDetailCard: View {
    let tool: MCPTool
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.headline)
                    
                    Text(tool.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    CategoryBadge(category: tool.category)
                    
                    Button("Test") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            if !tool.tags.isEmpty {
                HStack {
                    ForEach(tool.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .cornerRadius(3)
                    }
                    
                    if tool.tags.count > 3 {
                        Text("+\(tool.tags.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct CategoryBadge: View {
    let category: MCPToolCategory
    
    var body: some View {
        Text(category.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}

struct EmptyToolsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No Tools Available")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("This server doesn't have any tools available or they couldn't be loaded.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, spacing: 8, containerWidth: proposal.width ?? 0).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, spacing: 8, containerWidth: bounds.width).offsets
        
        for (offset, subview) in zip(offsets, subviews) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }
    
    private func layout(sizes: [CGSize], spacing: CGFloat, containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentPosition = CGPoint.zero
        var maxY: CGFloat = 0
        
        for size in sizes {
            if currentPosition.x + size.width > containerWidth && currentPosition.x > 0 {
                currentPosition.x = 0
                currentPosition.y = maxY + spacing
            }
            
            offsets.append(currentPosition)
            currentPosition.x += size.width + spacing
            maxY = max(maxY, currentPosition.y + size.height)
        }
        
        return (offsets, CGSize(width: containerWidth, height: maxY))
    }
}

// MARK: - Preview

#Preview {
    ServerDetailView(
        server: MCPServer(
            name: "Example Server",
            baseURL: "http://localhost:3001",
            description: "An example MCP server for testing"
        ),
        mcpClient: MCPClient()
    )
    .frame(width: 800, height: 600)
}
