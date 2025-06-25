#!/bin/bash

# HuggingChat API Test Script
# This script tests all key HuggingChat API endpoints to help debug authentication issues
# Usage: ./test_huggingchat_api.sh <hf-chat-cookie-value>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hf-chat-cookie-value>"
    echo "Example: $0 'your-hf-chat-cookie-value-here'"
    echo ""
    echo "To get your hf-chat cookie:"
    echo "1. Open Chrome/Safari and go to https://huggingface.co/chat"
    echo "2. Open Developer Tools (F12)"
    echo "3. Go to Application/Storage tab"
    echo "4. Under Cookies, find 'hf-chat' and copy its value"
    exit 1
fi

HF_CHAT_COOKIE="$1"
BASE_URL="https://huggingface.co"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "🧪 HuggingChat API Test Suite"
echo "============================="
echo "Base URL: $BASE_URL"
echo "Cookie: hf-chat=${HF_CHAT_COOKIE:0:20}..."
echo ""

# Common headers for all requests
COMMON_HEADERS=(
    -H "User-Agent: $USER_AGENT"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: en-US,en;q=0.9"
    -H "Origin: $BASE_URL"
    -H "Referer: $BASE_URL/chat/"
    -H "Cookie: hf-chat=$HF_CHAT_COOKIE"
    -H "Cache-Control: no-cache, no-store, must-revalidate"
    -H "Pragma: no-cache"
)

test_endpoint() {
    local method="$1"
    local endpoint="$2"
    local description="$3"
    local data="$4"
    
    echo "🔍 Testing: $description"
    echo "   Method: $method"
    echo "   Endpoint: $endpoint"
    
    # Build the full URL
    local full_url="${BASE_URL}${endpoint}"
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "${COMMON_HEADERS[@]}" "$full_url")
    else
        # POST request
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "${COMMON_HEADERS[@]}" \
            -H "Content-Type: application/json" \
            -X POST \
            -d "$data" \
            "$full_url")
    fi
    
    # Split response and status code
    http_code=$(echo "$response" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
    body=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    echo "   Status: $http_code"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "   ✅ SUCCESS"
        if [ ${#body} -gt 200 ]; then
            echo "   Response: ${body:0:200}..."
        else
            echo "   Response: $body"
        fi
    else
        echo "   ❌ FAILED"
        echo "   Error: $body"
    fi
    echo ""
}

echo ""
echo "Starting API tests..."

# Test GET endpoints
test_endpoint "GET" "/chat/api/models" "Get available models"
test_endpoint "GET" "/chat/api/conversations" "Get conversations"
test_endpoint "GET" "/chat/api/user" "Get current user"
test_endpoint "GET" "/chat/api/user/assistants" "Get user assistants"

# Test POST endpoints
test_endpoint "POST" "/chat/conversation" "Create conversation" '{"model":"meta-llama/Llama-3.3-70B-Instruct","preprompt":""}'

echo ""
echo "============================================================"
echo " Test Suite Complete"
echo "============================================================"
echo ""
echo "💡 Tips for debugging:"
echo "   - ✅ SUCCESS means the endpoint is working correctly"
echo "   - ❌ FAILED means there's an authentication or API issue"
echo "   - Check the HTTP status codes and error messages above"
echo "   - 401 = Authentication problem"
echo "   - 403 = Permission problem"
echo "   - 404 = Endpoint not found"
echo "   - 500 = Server error"
