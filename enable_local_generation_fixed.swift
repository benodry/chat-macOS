#!/usr/bin/env swift

import Foundation

print("🔧 Enabling local generation and checking settings...")

// Enable local generation
UserDefaults.standard.set(true, forKey: "isLocalGeneration")

// Set a local model (this should exist based on previous tests)
UserDefaults.standard.set("SmolLM-135M-Instruct-4bit", forKey: "localModel")

// Set storage mode to local
UserDefaults.standard.set("local", forKey: "storageMode")

// Sync changes
UserDefaults.standard.synchronize()

print("✅ Settings updated!")

// Verify the changes
let isLocalGeneration = UserDefaults.standard.bool(forKey: "isLocalGeneration")
let selectedModel = UserDefaults.standard.string(forKey: "localModel") ?? "None"
let storageMode = UserDefaults.standard.string(forKey: "storageMode") ?? "hybrid"

print("\n📊 Current settings:")
print("   - isLocalGeneration: \(isLocalGeneration)")
print("   - selectedLocalModel: \(selectedModel)")  
print("   - storageMode: \(storageMode)")

if isLocalGeneration && selectedModel != "None" {
    print("\n✅ Local generation should now be active!")
} else {
    print("\n⚠️  Local generation may not be fully configured")
}
