#!/usr/bin/env python3
"""
HuggingChat API Test Suite
Tests various endpoints to diagnose authentication and API issues
"""

import urllib.request
import urllib.parse
import urllib.error
import json
import sys

def print_section(title):
    print(f"\n{'='*60}")
    print(f" {title}")
    print('='*60)

def print_request_details(method, url, headers, data=None):
    print(f"\n🔧 {method} {url}")
    print("📋 Headers:")
    for key, value in headers.items():
        # Mask sensitive values
        if 'cookie' in key.lower() or 'authorization' in key.lower():
            masked_value = value[:20] + "..." if len(value) > 20 else value
            print(f"   {key}: {masked_value}")
        else:
            print(f"   {key}: {value}")
    if data:
        print(f"📦 Data: {data}")

def print_response_details(response):
    print(f"📊 Status: {response.status_code}")
    print("📋 Response Headers:")
    for key, value in response.headers.items():
        print(f"   {key}: {value}")
    print(f"📦 Content Length: {len(response.content)} bytes")
    
    # Try to parse as JSON
    try:
        json_data = response.json()
        print("📄 JSON Response:")
        print(json.dumps(json_data, indent=2)[:500] + ("..." if len(str(json_data)) > 500 else ""))
    except:
        print("📄 Raw Response (first 500 chars):")
        print(response.text[:500] + ("..." if len(response.text) > 500 else ""))

def extract_cookies_from_browser():
    """
    Instructions for user to extract cookies from browser
    """
    print("To run this test, you need to extract cookies from your browser:")
    print("1. Open HuggingChat in your browser and log in")
    print("2. Open Developer Tools (F12)")
    print("3. Go to Application/Storage > Cookies > huggingface.co")
    print("4. Find the 'hf-chat' cookie and copy its value")
    print("5. Paste it below when prompted")
    print()
    
    hf_chat = input("Enter your hf-chat cookie value: ").strip()
    if not hf_chat:
        print("❌ No cookie provided, exiting")
        sys.exit(1)
    
    return {"hf-chat": hf_chat}

def test_endpoint(session, method, url, description, headers=None, data=None):
    """Test a single endpoint and return success status"""
    print(f"\n🧪 Testing: {description}")
    
    try:
        request_headers = {
            "User-Agent": "HuggingChat/1.3-(4) arm64 Mac13,2 CFNetwork/1.0 Darwin/24.5.0",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Origin": "https://huggingface.co",
            "Referer": "https://huggingface.co/chat/",
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache"
        }
        
        if headers:
            request_headers.update(headers)
        
        print_request_details(method, url, request_headers, data)
        
        if method.upper() == "GET":
            response = session.get(url, headers=request_headers)
        elif method.upper() == "POST":
            if data:
                request_headers["Content-Type"] = "application/json"
                response = session.post(url, headers=request_headers, json=data)
            else:
                response = session.post(url, headers=request_headers)
        else:
            print(f"❌ Unsupported method: {method}")
            return False
            
        print_response_details(response)
        
        # Check for success
        if 200 <= response.status_code < 300:
            print("✅ SUCCESS")
            return True
        else:
            print(f"❌ FAILED - Status {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

def main():
    print_section("HuggingChat API Test Suite")
    
    # Get cookies from user
    cookies = extract_cookies_from_browser()
    
    # Create session with cookies
    session = requests.Session()
    for name, value in cookies.items():
        session.cookies.set(name, value, domain="huggingface.co", path="/")
    
    print(f"\n🍪 Using cookies: {list(cookies.keys())}")
    
    # Test endpoints
    base_url = "https://huggingface.co"
    tests = [
        # Basic GET endpoints
        ("GET", f"{base_url}/chat/api/models", "Get available models"),
        ("GET", f"{base_url}/chat/api/conversations", "Get conversations"),
        ("GET", f"{base_url}/chat/api/user", "Get current user"),
        ("GET", f"{base_url}/chat/api/user/assistants", "Get user assistants"),
        
        # POST endpoints
        ("POST", f"{base_url}/chat/conversation", "Create conversation", None, {
            "model": "meta-llama/Llama-3.3-70B-Instruct",
            "preprompt": ""
        }),
    ]
    
    results = []
    for test in tests:
        method, url, description = test[:3]
        data = test[4] if len(test) > 4 else None
        success = test_endpoint(session, method, url, description, data=data)
        results.append((description, success))
    
    # Summary
    print_section("Test Results Summary")
    
    success_count = 0
    for description, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} - {description}")
        if success:
            success_count += 1
    
    print(f"\nOverall: {success_count}/{len(results)} tests passed")
    
    if success_count == len(results):
        print("🎉 All tests passed! API authentication is working correctly.")
    else:
        print("⚠️  Some tests failed. Check the detailed output above for debugging.")

if __name__ == "__main__":
    main()
