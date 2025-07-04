//
//  StorageSettingsView.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import SwiftUI

struct StorageSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var storageManager = ConversationStorageManager.shared
    @State private var localUserManager = LocalUserManager.shared
    @State private var showingDataMigration = false
    @State private var showingExportOptions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage & Data")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose how your conversations are stored and managed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Storage Mode Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Storage Mode")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ForEach(StorageMode.allCases, id: \.self) { mode in
                        StorageModeRow(
                            mode: mode,
                            isSelected: storageManager.storageMode == mode,
                            onSelect: {
                                storageManager.storageMode = mode
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Current Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Status")
                    .font(.headline)
                
                HStack {
                    statusIcon
                    Text(storageManager.statusMessage)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Local User Profile (only show in local/hybrid mode)
            if localUserManager.canUseLocalStorage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Local Profile")
                        .font(.headline)
                    
                    if let user = localUserManager.currentLocalUser {
                        HStack {
                            Text("Username:")
                            TextField("Username", text: Binding(
                                get: { user.username },
                                set: { localUserManager.updateUsername($0) }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 200)
                        }
                    }
                }
                
                Divider()
            }
            
            // Data Management
            VStack(alignment: .leading, spacing: 12) {
                Text("Data Management")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    // Export Data
                    HStack {
                        Button("Export Conversations") {
                            showingExportOptions = true
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Text("Export your conversation data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Migration (only show in hybrid mode)
                    if storageManager.storageMode == .hybrid {
                        HStack {
                            Button("Sync Data") {
                                showingDataMigration = true
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Text("Sync between local and HuggingFace")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingExportOptions) {
            ExportDataView()
        }
        .sheet(isPresented: $showingDataMigration) {
            DataMigrationView()
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch storageManager.storageMode {
            case .local:
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.blue)
            case .huggingface:
                if HuggingChatSession.shared.currentUser != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            case .hybrid:
                if HuggingChatSession.shared.currentUser != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Storage Mode Row

struct StorageModeRow: View {
    let mode: StorageMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                        
                        Text(mode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Conversations")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choose the format for exporting your conversation data.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Button("Export as JSON") {
                    // TODO: Implement JSON export
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Export as Markdown") {
                    // TODO: Implement Markdown export
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
        }
        .padding(30)
        .frame(width: 400)
    }
}

// MARK: - Data Migration View

struct DataMigrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var migrationInProgress = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Data Synchronization")
                .font(.title2)
                .fontWeight(.bold)
            
            if migrationInProgress {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Synchronizing data...")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Sync your local conversations with HuggingFace or import data from HuggingFace to local storage.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        Button("Import from HuggingFace") {
                            startMigration()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Export to HuggingFace") {
                            startMigration()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(30)
        .frame(width: 450)
    }
    
    private func startMigration() {
        migrationInProgress = true
        
        // TODO: Implement actual migration logic
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            migrationInProgress = false
            dismiss()
        }
    }
}

#Preview {
    StorageSettingsView()
        .frame(width: 600, height: 500)
}
