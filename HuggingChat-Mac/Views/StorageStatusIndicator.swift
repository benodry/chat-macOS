//
//  StorageStatusIndicator.swift
//  HuggingChat-Mac
//
//  Created by Local Database Integration on 7/4/25.
//

import SwiftUI

/// Small indicator showing current storage status
struct StorageStatusIndicator: View {
    @State private var storageManager = ConversationStorageManager.shared
    @State private var showingTooltip = false
    
    var body: some View {
        Button(action: {
            showingTooltip.toggle()
        }) {
            HStack(spacing: 4) {
                statusIcon
                    .imageScale(.small)
                
                if storageManager.storageMode != .local {
                    authenticationIcon
                        .imageScale(.small)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(storageManager.statusMessage)
        .popover(isPresented: $showingTooltip) {
            StorageStatusTooltip()
                .padding()
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch storageManager.storageMode {
            case .local:
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.blue)
            case .huggingface:
                Image(systemName: "cloud.fill")
                    .foregroundColor(.green)
            case .hybrid:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.purple)
            }
        }
    }
    
    private var authenticationIcon: some View {
        Group {
            if HuggingChatSession.shared.currentUser != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Storage Status Tooltip

struct StorageStatusTooltip: View {
    @State private var storageManager = ConversationStorageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Status")
                .font(.headline)
            
            HStack {
                Text("Mode:")
                Text(storageManager.storageMode.displayName)
                    .fontWeight(.semibold)
            }
            
            Text(storageManager.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if storageManager.requiresAuthentication {
                Text("Login required for full functionality")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 200)
    }
}

#Preview {
    StorageStatusIndicator()
}
