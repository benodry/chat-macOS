//
//  MCPToolSuggestionsView.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import SwiftUI

/// View for displaying MCP tool suggestions in the chat interface
struct MCPToolSuggestionsView: View {
    let suggestions: [MCPToolSelection]
    let onToolSelected: (MCPToolSelection) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            if suggestions.isEmpty {
                emptyView
            } else {
                suggestionsGrid
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundColor(.accentColor)
            
            Text("Suggested Tools")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var suggestionsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(suggestions, id: \.tool.id) { suggestion in
                ToolSuggestionCard(suggestion: suggestion) {
                    onToolSelected(suggestion)
                }
            }
        }
    }
    
    private var emptyView: some View {
        Text("No relevant tools found for this request.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
    }
}

// MARK: - Tool Suggestion Card

struct ToolSuggestionCard: View {
    let suggestion: MCPToolSelection
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(suggestion.tool.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    ConfidenceIndicator(confidence: suggestion.confidence)
                }
                
                Text(suggestion.tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    CategoryBadge(category: suggestion.tool.category)
                    
                    Spacer()
                    
                    Text(suggestion.server.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if !suggestion.reasoning.isEmpty {
                    Text(suggestion.reasoning)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .italic()
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: Double
    
    private var color: Color {
        switch confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    private var text: String {
        switch confidence {
        case 0.8...:
            return "High"
        case 0.6..<0.8:
            return "Med"
        default:
            return "Low"
        }
    }
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - In-Chat MCP Status

struct MCPStatusIndicator: View {
    let isEnabled: Bool
    let toolCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                
                Text("\(toolCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("MCP Tools: \(toolCount) available")
    }
}

// MARK: - Tool Execution Result View

struct MCPToolResultView: View {
    let result: MCPToolExecutionResult
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundColor(result.success ? .green : .orange)
                
                Text("Tool: \(result.tool.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Dismiss") {
                    onDismiss()
                }
                .font(.caption)
            }
            
            Text(result.displayText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            
            HStack {
                Text("Server: \(result.server.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                CategoryBadge(category: result.tool.category)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(result.success ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Floating MCP Panel

struct FloatingMCPPanel: View {
    @Bindable var mcpClient: MCPClient
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(.accentColor)
                    
                    Text("MCP Tools")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Divider()
                
                // Quick stats
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(mcpClient.servers.prefix(5), id: \.id) { server in
                            HStack {
                                StatusIndicator(status: server.status)
                                
                                Text(server.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(server.tools.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.9))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}

// MARK: - Preview

#Preview("Tool Suggestions") {
    MCPToolSuggestionsView(
        suggestions: [
            MCPToolSelection(
                tool: MCPTool(
                    name: "File Search",
                    description: "Search for files in the local filesystem",
                    serverID: nil,
                    inputSchema: nil,
                    outputSchema: nil,
                    category: .fileSystem,
                    tags: ["search", "files"]
                ),
                server: MCPServer(
                    name: "Local FS",
                    baseURL: "http://localhost:3001",
                    description: "Local file system"
                ),
                confidence: 0.85,
                reasoning: "High relevance for file operations"
            )
        ],
        onToolSelected: { _ in },
        onDismiss: { }
    )
    .frame(width: 400)
    .padding()
}

#Preview("MCP Status") {
    MCPStatusIndicator(
        isEnabled: true,
        toolCount: 12,
        onTap: { }
    )
    .padding()
}
