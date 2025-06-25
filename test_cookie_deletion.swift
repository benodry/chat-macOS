#!/usr/bin/env swift

import Foundation

// Test script to manually delete hf-token/hf-chat cookies from HTTPCookieStorage
print("🧪 Testing cookie deletion functionality...")

// Check initial cookie state
let initialCookies = HTTPCookieStorage.shared.cookies ?? []
print("📊 Initial cookie count: \(initialCookies.count)")

// Find HuggingFace related cookies
let hfCookies = initialCookies.filter { cookie in
    return cookie.domain.contains("huggingface") || 
           cookie.name.contains("hf-") ||
           cookie.name.contains("token") ||
           cookie.name.contains("auth")
}

print("🔍 Found \(hfCookies.count) HuggingFace/auth related cookies:")
for cookie in hfCookies {
    print("   - \(cookie.name): \(String(cookie.value.prefix(20)))... (domain: \(cookie.domain))")
}

// Delete the cookies
print("\n🗑️  Deleting HuggingFace/auth cookies...")
for cookie in hfCookies {
    print("   Deleting: \(cookie.name)")
    HTTPCookieStorage.shared.deleteCookie(cookie)
}

// Verify deletion
let remainingCookies = HTTPCookieStorage.shared.cookies ?? []
let remainingHfCookies = remainingCookies.filter { cookie in
    return cookie.domain.contains("huggingface") || 
           cookie.name.contains("hf-") ||
           cookie.name.contains("token") ||
           cookie.name.contains("auth")
}

print("\n✅ Cookie deletion complete!")
print("📊 Remaining total cookies: \(remainingCookies.count)")
print("🔍 Remaining HuggingFace/auth cookies: \(remainingHfCookies.count)")

if remainingHfCookies.isEmpty {
    print("🎉 All HuggingFace/auth cookies successfully deleted!")
} else {
    print("⚠️  Some HuggingFace/auth cookies remain:")
    for cookie in remainingHfCookies {
        print("   - \(cookie.name) (domain: \(cookie.domain))")
    }
}
