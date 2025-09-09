# Phase 3 Implementation: Gemini and Bedrock Integration

This document outlines the implementation of Phase 3, which adds support for Google Gemini and AWS Bedrock providers to the chat application.

## Latest API Versions Used

### Google Gemini API
- **API Version**: v1beta (with fallback to v1 stable)
- **Base URL**: `https://generativelanguage.googleapis.com`
- **Authentication**: API Key via `x-goog-api-key` header
- **Models Supported**:
  - `gemini-2.0-flash-exp` - Latest experimental model
  - `gemini-1.5-pro` - Production model with high capability
  - `gemini-1.5-flash` - Fast and efficient model
  - `gemini-1.5-flash-8b` - Lightweight model
- **Features**:
  - Context window: Up to 1M tokens
  - Streaming support via Server-Sent Events
  - Tool calling support
  - Reasoning capabilities

### AWS Bedrock API
- **API Version**: Latest Bedrock Runtime API
- **Base URL**: `https://bedrock-runtime.{region}.amazonaws.com`
- **Authentication**: AWS Signature V4 (Access Key + Secret Key)
- **Models Supported**:
  - `anthropic.claude-3-5-sonnet-20241022-v2:0` - Latest Claude 3.5 Sonnet v2
  - `anthropic.claude-3-5-haiku-20241022-v1:0` - Claude 3.5 Haiku
  - `anthropic.claude-3-sonnet-20240229-v1:0` - Claude 3 Sonnet
  - `meta.llama3-1-70b-instruct-v1:0` - Llama 3.1 70B
  - `meta.llama3-1-8b-instruct-v1:0` - Llama 3.1 8B
- **Features**:
  - Context window: Up to 200k tokens (Claude models)
  - Streaming support via event stream
  - Tool calling support
  - Multi-modal capabilities

## Configuration Requirements

### Gemini Setup
1. Get API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Enter API key in provider settings
3. Select desired model

### Bedrock Setup
1. Configure AWS credentials with Bedrock access
2. Ensure proper IAM permissions for Bedrock model access
3. Enter AWS Access Key ID and Secret Access Key
4. Select AWS region (defaults to us-east-1)
5. Select desired model

## Implementation Details

### Architecture
- Both providers implement the `ChatProvider` protocol
- Platform-specific code handles streaming differences between macOS and Linux
- AWS Signature V4 authentication implemented with CryptoKit (with fallback)
- Proper error handling and response parsing

### Features Implemented
- Full streaming support with delta accumulation
- Model listing with capabilities
- Configuration persistence via UserDefaults
- UI integration with provider picker
- Cross-platform compatibility

### Testing
- Unit tests for both providers
- Capability verification
- Model listing validation
- Configuration testing

## Usage
1. Open provider settings
2. Select "Google Gemini" or "AWS Bedrock"
3. Enter required credentials
4. Save and rebuild provider
5. Select desired model
6. Start chatting with the new provider