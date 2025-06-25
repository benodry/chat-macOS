#!/usr/bin/env swift

import Foundation

// Simple script to clear HuggingFace cookies from HTTPCookieStorage
print("🧹 Clearing HuggingFace cookies from HTTPCookieStorage...")

let cookies = HTTPCookieStorage.shared.cookies ?? []
print("📊 Total cookies before cleanup: \(cookies.count)")

let hfCookies = cookies.filter { cookie in
    return cookie.domain.contains("huggingface") || 
           cookie.name.contains("hf") ||
           cookie.name == "hf-chat" ||
           cookie.name.contains("auth") ||
           cookie.name.contains("token")
}

print("🍪 Found \(hfCookies.count) HuggingFace-related cookies to delete:")
for cookie in hfCookies {
    print("   Deleting: \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
    HTTPCookieStorage.shared.deleteCookie(cookie)
}

let remainingCookies = HTTPCookieStorage.shared.cookies ?? []
print("✅ Cleanup complete. Remaining cookies: \(remainingCookies.count)")

// Verify no HF cookies remain
let remainingHFCookies = remainingCookies.filter { $0.domain.contains("huggingface") || $0.name.contains("hf") }
if remainingHFCookies.isEmpty {
    print("✅ All HuggingFace cookies successfully removed")
} else {
    print("⚠️  Some HuggingFace cookies still remain: \(remainingHFCookies.count)")
    for cookie in remainingHFCookies {
        print("   \(cookie.name) (domain: \(cookie.domain))")
    }
}
