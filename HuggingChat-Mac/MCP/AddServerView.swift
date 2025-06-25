//
//  AddServerView.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import SwiftUI

/// View for adding new MCP servers
struct AddServerView: View {
    @Bindable var mcpClient: MCPClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var baseURL = ""
    @State private var description = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showingPresets = false
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: baseURL) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
//                        .keyboardType(.URL)
//                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                } header: {
                    Text("Server Information")
                } footer: {
                    if let error = validationError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("Enter the details for your MCP server")
                    }
                }
                
                Section {
                    Button("Use Preset Configuration") {
                        showingPresets = true
                    }
                    .disabled(isValidating)
                    
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!isFormValid || isValidating)
                    
                    if isValidating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Validating server...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Configuration")
                }
                
                Section {
                    exampleConfiguration
                } header: {
                    Text("Example")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add MCP Server")
//            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addServer()
                    }
                    .disabled(!isFormValid || isValidating)
                }
            }
        }
        .sheet(isPresented: $showingPresets) {
            ServerPresetsView { preset in
                name = preset.name
                baseURL = preset.baseURL
                description = preset.description
                showingPresets = false
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private var exampleConfiguration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local File System Server")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Name: File System MCP")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("URL: http://localhost:3001")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Description: Local file operations")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func testConnection() {
        isValidating = true
        validationError = nil
        
        Task {
            let testServer = MCPServer(
                name: name,
                baseURL: baseURL,
                description: description.isEmpty ? nil : description
            )
            
            // Create a temporary server manager for validation
            let serverManager = MCPServerManager()
            let validatedServer = await serverManager.verifyServer(testServer)
            
            await MainActor.run {
                isValidating = false
                
                switch validatedServer.status {
                case .online:
                    validationError = nil
                case .offline:
                    validationError = "Server is offline or unreachable"
                case .error:
                    validationError = "Server returned an error"
                case .unknown:
                    validationError = "Unable to determine server status"
                }
            }
        }
    }
    
    private func addServer() {
        let newServer = MCPServer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        mcpClient.addServer(newServer)
        
        // Refresh servers to get the new one's status
        Task {
            await mcpClient.discoverServers()
        }
        
        dismiss()
    }
}

// MARK: - Server Presets View

struct ServerPresetsView: View {
    let onSelectPreset: (ServerPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let presets: [ServerPreset] = [
        ServerPreset(
            name: "Local File System",
            baseURL: "http://localhost:3001",
            description: "Local file system operations and management"
        ),
        ServerPreset(
            name: "Web Search & Browse",
            baseURL: "http://localhost:3002",
            description: "Web search and content extraction capabilities"
        ),
        ServerPreset(
            name: "Database Tools",
            baseURL: "http://localhost:3003",
            description: "Database query and management tools"
        ),
        ServerPreset(
            name: "Development Assistant",
            baseURL: "http://localhost:3004",
            description: "Code analysis and development utilities"
        ),
        ServerPreset(
            name: "API Gateway",
            baseURL: "http://localhost:3005",
            description: "REST API interaction and testing tools"
        )
    ]
    
    var body: some View {
        NavigationStack {
            List(presets, id: \.name) { preset in
                PresetRowView(preset: preset) {
                    onSelectPreset(preset)
                }
            }
            .navigationTitle("Server Presets")
//            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

struct PresetRowView: View {
    let preset: ServerPreset
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(preset.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(preset.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Tool Test View

struct ToolTestView: View {
    let tool: MCPTool
    let server: MCPServer
    @Bindable var mcpClient: MCPClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var parameters: [String: String] = [:]
    @State private var isExecuting = false
    @State private var executionResult: String?
    @State private var executionError: String?
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                toolInfoSection
                
                if let schema = tool.inputSchema, let properties = schema.properties {
                    parametersSection(properties: properties, required: schema.required ?? [])
                }
                
                executeSection
                
                if let result = executionResult {
                    resultSection(result: result)
                } else if let error = executionError {
                    errorSection(error: error)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Test Tool")
//            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private var toolInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tool.name)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(tool.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                CategoryBadge(category: tool.category)
                Text("on \(server.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func parametersSection(properties: [String: MCPProperty], required: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parameters")
                .font(.headline)
            
            ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                let property = properties[key]!
                let isRequired = required.contains(key)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(key)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isRequired {
                            Text("*")
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                        
                        Text(property.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let description = property.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("Enter \(key)", text: Binding(
                        get: { parameters[key] ?? property.defaultValue ?? "" },
                        set: { parameters[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
    
    private var executeSection: some View {
        VStack(spacing: 8) {
            Button(action: executeTool) {
                HStack {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    
                    Text(isExecuting ? "Executing..." : "Execute Tool")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExecuting)
            
            if isExecuting {
                Text("Running tool on \(server.name)...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func resultSection(result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Result")
                .font(.headline)
            
            ScrollView {
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxHeight: 200)
        }
    }
    
    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private func executeTool() {
        isExecuting = true
        executionResult = nil
        executionError = nil
        
        Task {
            do {
                let response = try await mcpClient.executeTool(
                    tool,
                    server: server,
                    parameters: parameters // Remove .mapValues { $0 as Any }, keep as [String: String]
                )
                
                await MainActor.run {
                    isExecuting = false
                    if let content = response.result?.content?.first?.text {
                        executionResult = content
                    } else {
                        executionResult = "Tool executed successfully (no content returned)"
                    }
                }
            } catch {
                await MainActor.run {
                    isExecuting = false
                    executionError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct ServerPreset {
    let name: String
    let baseURL: String
    let description: String
}

// MARK: - Preview

#Preview("Add Server") {
    AddServerView(mcpClient: MCPClient())
}

#Preview("Server Presets") {
    ServerPresetsView { _ in }
}
