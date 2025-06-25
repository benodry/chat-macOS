# Quick Cookie Test Script

This script will help us verify if we can access the hf-chat token properly.

## Test 1: Check if we can read Safari cookies

Run this to test if the hf-chat token is accessible:

```bash
# Check Safari cookies database
find ~/Library -name "Cookies.binarycookies" -type f 2>/dev/null

# Check if we can find HuggingFace cookies
sqlite3 ~/Library/Cookies/Cookies.binarycookies.db "SELECT name, value FROM moz_cookies WHERE host LIKE '%huggingface%';" 2>/dev/null || echo "Could not access Safari cookies"
```

## Test 2: Manual token extraction

1. Open Safari/Chrome
2. Go to https://huggingface.co/chat/
3. Open Developer Tools → Application/Storage → Cookies
4. Find `hf-chat` cookie and copy its value
5. Use our working test script:

```bash
./test_huggingchat_api.sh 'your-hf-chat-token-here'
```

## Root Cause Analysis

The Swift app is looking for the `hf-chat` token in `HTTPCookieStorage.shared.cookies`, but this only contains cookies set by the app itself, not browser cookies. 

We need to either:
1. Implement browser cookie reading from Safari/Chrome cookie stores
2. Add a manual token input mechanism 
3. Implement a proper OAuth/login flow in the app

## Immediate Fix Options

### Option 1: Read Safari Cookies (requires permissions)
Read Safari's cookie database directly 

### Option 2: Manual Token Input
Add a settings screen where users can paste their hf-chat token

### Option 3: WebView Login
Use a WebView for HuggingFace login, which would set the cookies properly

The cleanest immediate solution would be Option 2 - a manual token input field.
