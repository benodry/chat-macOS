#!/bin/bash

# Quick test script to check if the app can successfully create a conversation
# This will print whether the conversation creation works

echo "Testing conversation creation with minimal setup..."

# Test the user endpoint first (should work without authentication issues)
echo "1. Testing user endpoint..."
RESPONSE=$(curl -s -w "%{http_code}" "https://huggingface.co/chat/api/user" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36")

HTTP_CODE="${RESPONSE: -3}"
BODY="${RESPONSE%???}"

echo "User endpoint HTTP status: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ User endpoint accessible"
    echo "Response: ${BODY:0:100}..."
else
    echo "❌ User endpoint failed"
    echo "Response: $BODY"
fi

echo ""
echo "2. Testing conversation creation..."
echo "Note: This will likely fail with 401 without authentication"
echo "But we can check if the error response is consistent with the working headers"

# Test conversation creation (expected to fail but we can see the error pattern)
CONV_RESPONSE=$(curl -s -w "%{http_code}" "https://huggingface.co/chat/api/conversation" \
    -X POST \
    -H "Accept: */*" \
    -H "Accept-Language: en-US,en;q=0.9" \
    -H "Cache-Control: no-cache" \
    -H "Content-Type: application/json" \
    -H "Origin: https://huggingface.co" \
    -H "Pragma: no-cache" \
    -H "Referer: https://huggingface.co/chat/" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36" \
    -d '{"model":"mistralai/Mistral-7B-Instruct-v0.3"}')

CONV_HTTP_CODE="${CONV_RESPONSE: -3}"
CONV_BODY="${CONV_RESPONSE%???}"

echo "Conversation creation HTTP status: $CONV_HTTP_CODE"
echo "Response: ${CONV_BODY:0:200}..."

if [[ "$CONV_HTTP_CODE" == "401" ]]; then
    echo "✅ Expected 401 - Authentication required (this is normal without a valid token)"
else
    echo "❌ Unexpected status code: $CONV_HTTP_CODE"
fi

echo ""
echo "If you want to test with a real token, manually run:"
echo "./test_huggingchat_api.sh 'your-hf-chat-token-here'"
