#!/usr/bin/env swift

// Test script to investigate local model generation issue
// This script will test the LocalLLM/ModelManager functionality directly

import Foundation

print("🔍 Testing local model generation issue...")

// Check if we're correctly setting local generation mode
let isLocalGeneration = UserDefaults.standard.bool(forKey: "isLocalGeneration")
let selectedLocalModel = UserDefaults.standard.string(forKey: "localModel") ?? "None"
let storageMode = UserDefaults.standard.string(forKey: "storageMode") ?? "Unknown"

print("📊 Current Settings:")
print("   - isLocalGeneration: \(isLocalGeneration)")
print("   - selectedLocalModel: \(selectedLocalModel)")
print("   - storageMode: \(storageMode)")

// Check if SmolLM model is available
let modelsData = UserDefaults.standard.data(forKey: "models")
if let data = modelsData {
    print("✅ Found models data in UserDefaults (\(data.count) bytes)")
} else {
    print("❌ No models data found in UserDefaults")
}

// Check active model
let activeModelData = UserDefaults.standard.data(forKey: "active_model")
if let data = activeModelData {
    print("✅ Found active model data in UserDefaults (\(data.count) bytes)")
} else {
    print("❌ No active model data found in UserDefaults")
}

print("🔍 Investigation complete. Check app preferences to ensure:")
print("   1. Local Generation is enabled")
print("   2. SmolLM-135M-Instruct-4bit model is selected")
print("   3. Model is downloaded")
