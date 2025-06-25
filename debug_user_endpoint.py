#!/usr/bin/env python3
"""
Debug script to test the /chat/api/user endpoint and understand
what headers and cookies are needed for it to work.
"""

import requests
import json

# You'll need to get these from your browser's developer tools
# Go to https://huggingface.co/chat/, open developer tools,
# go to Network tab, refresh the page, find the /chat/api/user request
# and copy the Cookie header value
COOKIE_HEADER = input("Enter the full Cookie header from your browser (from /chat/api/user request): ")

# Test with minimal headers (like the app currently does)
def test_minimal_headers():
    print("\n=== Testing with minimal headers (like the app) ===")
    headers = {
        'Cookie': COOKIE_HEADER,
        'User-Agent': 'HuggingChat Mac App/1.0',
        'Accept': 'application/json'
    }
    
    try:
        response = requests.get('https://huggingface.co/chat/api/user', headers=headers)
        print(f"Status: {response.status_code}")
        print(f"Headers: {dict(response.headers)}")
        if response.status_code == 200:
            print(f"Response: {response.json()}")
        else:
            print(f"Error response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")

# Test with full browser headers
def test_browser_headers():
    print("\n=== Testing with full browser headers ===")
    headers = {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
        'Cookie': COOKIE_HEADER,
        'Origin': 'https://huggingface.co',
        'Referer': 'https://huggingface.co/chat/',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'X-Requested-With': 'XMLHttpRequest'
    }
    
    try:
        response = requests.get('https://huggingface.co/chat/api/user', headers=headers)
        print(f"Status: {response.status_code}")
        print(f"Headers: {dict(response.headers)}")
        if response.status_code == 200:
            print(f"Response: {response.json()}")
        else:
            print(f"Error response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    print("This script will help debug the /chat/api/user endpoint")
    print("Make sure you're logged into HuggingFace Chat in your browser first.")
    print("\nInstructions:")
    print("1. Go to https://huggingface.co/chat/ in your browser")
    print("2. Open Developer Tools (F12)")
    print("3. Go to Network tab")
    print("4. Refresh the page")
    print("5. Find the /chat/api/user request")
    print("6. Right-click it and 'Copy as cURL' or copy the Cookie header")
    print("7. Paste the full Cookie header below")
    
    test_minimal_headers()
    test_browser_headers()
