# MCP Integration for HuggingChat macOS

This document outlines the Model Context Protocol (MCP) integration that has been added to the HuggingChat macOS application.

## Overview

The MCP integration allows HuggingChat macOS to connect to external tools and services, enhancing AI capabilities with real-world data and actions. The implementation is entirely in Swift and doesn't require a Python backend.

## Architecture

### Core Components

1. **MCPModels.swift** - Data models for MCP protocol
   - `MCPServer` - Represents an MCP server configuration
   - `MCPTool` - Represents available tools on servers
   - `MCPRequest/MCPResponse` - Protocol communication models
   - `MCPToolSelection` - Tool selection results

2. **MCPClient.swift** - Main MCP client for server management
   - Server discovery and verification
   - Tool execution
   - Configuration management
   - Background health monitoring

3. **MCPServerManager.swift** - Server discovery and verification
   - Health checks for servers
   - Capability fetching
   - Tool enumeration
   - Network operations

4. **MCPToolSelector.swift** - Intelligent tool selection
   - Natural language processing for tool matching
   - Confidence scoring
   - Multi-factor tool ranking
   - Category inference

5. **MCPIntegration.swift** - Integration layer with main app
   - Message processing with MCP enhancement
   - Auto-selection vs. suggestion modes
   - Tool execution coordination

### User Interface Components

1. **MCPView.swift** - Main MCP management interface
   - Server list with status indicators
   - Server detail views
   - Tool management

2. **MCPOverviewView.swift** - Dashboard view
   - Statistics and server health
   - Tool categories overview
   - Quick actions

3. **ServerDetailView.swift** - Individual server management
   - Server information and capabilities
   - Tool listing and testing
   - Configuration options

4. **AddServerView.swift** - Server configuration interface
   - Manual server addition
   - Preset configurations
   - Connection testing

5. **MCPSettings.swift** - Settings integration
   - Enable/disable MCP functionality
   - Auto-selection preferences
   - Quick server management

6. **MCPToolSuggestionsView.swift** - In-chat tool suggestions
   - Tool recommendation cards
   - Confidence indicators
   - Execution buttons

## Integration Points

### ConversationModel Integration

The `ConversationViewModel` has been enhanced with:
- `mcpIntegration: MCPIntegration` - Core MCP functionality
- `mcpSuggestions: [MCPToolSelection]` - Current tool suggestions
- `showingMCPSuggestions: Bool` - UI state for suggestions

### Message Processing Flow

1. User sends a message via `sendAttributed()`
2. Message is processed through `processMCPForMessage()`
3. MCP integration analyzes the message and suggests/executes tools
4. Enhanced message (with tool results) is sent to the conversation
5. Tool suggestions are displayed in the UI if applicable

### Settings Integration

Added MCP settings tab to the main settings view:
- Enable/disable MCP functionality
- Configure auto-selection behavior
- Access full MCP management interface

### Chat Interface Integration

- **MCPStatusIndicator** in `InputView` - Shows MCP status and tool count
- **MCPToolSuggestionsView** overlay in `ConversationView` - Displays tool suggestions
- Tool execution results appear as conversation messages

## Configuration

### Default Servers

The integration includes default server configurations for common use cases:
- Local File System (port 3001)
- Web Search & Browse (port 3002)
- Database Tools (port 3003)
- Development Assistant (port 3004)

### Settings

- `mcpEnabled` - Enable/disable MCP functionality
- `mcpAutoSelectTools` - Auto-execute tools vs. show suggestions
- Server configurations stored in UserDefaults

## Tool Categories

Tools are automatically categorized for better organization:
- **Search** - Find and discovery tools
- **File System** - Local file operations
- **Web** - Internet and URL-based tools
- **Database** - Data query and management
- **API** - External service integration
- **AI** - Machine learning and analysis
- **Utility** - General purpose tools
- **Other** - Uncategorized tools

## Intelligent Tool Selection

The tool selector uses multiple factors for ranking:
- **Name similarity** (30%) - Tool name matches query terms
- **Description match** (25%) - Description relevance
- **Category fit** (20%) - Inferred category from query
- **Server health** (15%) - Server availability and status
- **Context relevance** (10%) - Match with conversation context

## Usage Scenarios

### Auto-Selection Mode
- Tools with >80% confidence are automatically executed
- Results are seamlessly integrated into responses
- Lower confidence tools are suggested instead

### Suggestion Mode
- All relevant tools are presented as suggestions
- User can manually select and execute tools
- Results are added to the conversation

### Manual Management
- Full MCP interface accessible through settings
- Add, remove, and configure servers
- Test individual tools
- Monitor server health

## Error Handling

- Network timeouts and connection failures
- Server unavailability graceful degradation
- Tool execution error recovery
- Invalid response handling

## Future Enhancements

Potential areas for expansion:
- Authentication support for secure servers
- Tool parameter input interfaces
- Background tool execution
- Tool result caching
- Server discovery via Bonjour
- Custom tool development interface

## Technical Details

### Network Protocol
- HTTP/HTTPS for server communication
- JSON for data exchange
- RESTful API design
- WebSocket support ready

### Performance
- Async/await throughout
- Background server verification
- Debounced configuration saving
- Lazy loading of tool lists

### Security
- Sandboxed tool execution
- Server validation
- Input sanitization
- Error boundary isolation

This MCP integration enhances HuggingChat macOS with powerful extensibility while maintaining the native Swift experience and performance characteristics.
