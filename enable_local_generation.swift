#!/usr/bin/env swift

import Foundation

// Enable local generation and select the local model
print("🔧 Enabling local generation...")

// Set local generation to true
UserDefaults.standard.set(true, forKey: "isLocalGeneration")

// Set the selected local model
UserDefaults.standard.set("SmolLM-135M-Instruct-4bit", forKey: "selectedLocalModel")

// Force storage mode to local
UserDefaults.standard.set("local", forKey: "storageMode")

// Sync the changes
UserDefaults.standard.synchronize()

print("✅ Local generation enabled!")
print("✅ Selected model: SmolLM-135M-Instruct-4bit")
print("✅ Storage mode: local")

// Verify the changes
let isLocalGeneration = UserDefaults.standard.bool(forKey: "isLocalGeneration")
let selectedModel = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? "None"
let storageMode = UserDefaults.standard.string(forKey: "storageMode") ?? "Unknown"

print("\n📊 Verification:")
print("   - isLocalGeneration: \(isLocalGeneration)")
print("   - selectedLocalModel: \(selectedModel)")
print("   - storageMode: \(storageMode)")
