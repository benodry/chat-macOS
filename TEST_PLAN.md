# HuggingChat-Mac Testing Plan - Post Authentication Fixes

## Test Environment
- macOS app rebuilt with header fixes
- Valid HuggingFace token available
- All API endpoints verified working via curl

## Test Steps

### 1. Launch and Initial Authentication
- [ ] Launch the HuggingChat Mac app
- [ ] Verify login screen appears if not authenticated
- [ ] Enter valid HuggingFace credentials
- [ ] Confirm successful login and user info display

### 2. Session Sync and Conversation Loading
- [ ] Verify existing conversations load from HuggingFace account
- [ ] Check that conversation list populates correctly
- [ ] Confirm conversation metadata (titles, timestamps) display properly

### 3. New Conversation Creation (Primary Fix Target)
- [ ] Click "New Conversation" or equivalent button
- [ ] Verify conversation creates without 401 errors
- [ ] Confirm new conversation appears in conversation list
- [ ] Check that conversation has proper ID and metadata

### 4. Message Sending (Secondary Fix Target)
- [ ] Select a conversation (new or existing)
- [ ] Type a test message
- [ ] Send the message
- [ ] Verify message sends without 401 errors
- [ ] Confirm response is received and displayed

### 5. Error Monitoring
- [ ] Monitor console logs for any remaining authentication errors
- [ ] Check for proper session cookie handling
- [ ] Verify no 401 errors in network requests

## Expected Results After Fixes
- ✅ Conversation creation succeeds (was failing with 401)
- ✅ Message sending works properly (was failing with 401)
- ✅ All POST requests include required headers
- ✅ Session persistence works correctly
- ✅ No authentication errors in console logs

## Critical Headers Now Included
All POST requests now include:
- `Accept: */*`
- `Accept-Language: en-US,en;q=0.9`
- `Cache-Control: no-cache`
- `Pragma: no-cache`
- `Referer: https://huggingface.co/chat/`
- `Origin: https://huggingface.co`
- `User-Agent: [correct app user agent]`

## Rollback Plan
If issues persist:
1. Check console logs for specific error details
2. Compare network requests with working curl examples
3. Verify session cookie handling in app
4. Consider additional header requirements
