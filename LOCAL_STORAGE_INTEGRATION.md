# Local Storage Integration

This document describes the new local storage system that allows HuggingChat-Mac to function without requiring HuggingFace authentication.

## Overview

The app now supports three storage modes:

### 1. Local Only Mode
- **Default mode** - works completely offline
- Stores all conversations in a local SQLite database
- No authentication required
- Full functionality available immediately
- Data stays on your device

### 2. HuggingFace Mode
- **Legacy mode** - preserves original behavior
- Requires HuggingFace login
- Stores conversations on HuggingFace servers
- Depends on internet connection

### 3. Hybrid Mode
- **Best of both worlds**
- Primary storage is local (works offline)
- Syncs with HuggingFace when authenticated
- Graceful fallback to local-only if HF unavailable

## Architecture

### Core Components

#### Storage Protocol
- `ConversationStorageProtocol` - Unified interface for all storage operations
- Supports async/await for modern Swift concurrency
- Consistent API regardless of storage backend

#### Storage Implementations
- `LocalDatabaseManager` - SQLite-based local storage
- `RemoteStorageManager` - Wrapper around existing HF network calls
- `HybridStorageManager` - Coordinates between local and remote

#### Management Layer
- `ConversationStorageManager` - Central coordinator (singleton)
- `LocalUserManager` - Manages local user profiles and preferences
- Auto-switches storage implementation based on user preference

### Database Schema

```sql
-- Local conversations table
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,              -- Local UUID
    user_id TEXT NOT NULL,            -- Local user ID
    title TEXT NOT NULL,              -- Conversation title
    created_at REAL NOT NULL,         -- Unix timestamp
    updated_at REAL NOT NULL,         -- Unix timestamp
    model_name TEXT,                  -- AI model used
    model_config TEXT,                -- Model configuration (JSON)
    is_synced_to_hf INTEGER DEFAULT 0,-- Sync status
    hf_server_id TEXT                 -- HF server ID (for sync)
);

-- Messages table
CREATE TABLE messages (
    id TEXT PRIMARY KEY,              -- Message UUID
    conversation_id TEXT NOT NULL,    -- Foreign key to conversations
    type INTEGER NOT NULL,            -- 0=user, 1=assistant
    content TEXT NOT NULL,            -- Message content
    timestamp REAL NOT NULL,          -- Unix timestamp
    metadata TEXT,                    -- Additional data (JSON)
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
```

## User Interface Changes

### Settings Integration
- New **Storage** tab in Settings
- Storage mode selection (Local/HuggingFace/Hybrid)
- Local user profile management
- Data export/import tools
- Sync status and controls

### Chat Interface
- **Storage Status Indicator** in toolbar - shows current mode and sync status
- **MCP Integration** button for Model Context Protocol features
- Seamless experience regardless of storage mode

### Status Messages
- Clear indication of current storage mode
- Authentication requirements when needed
- Sync status for hybrid mode

## Migration Strategy

### Phase 1: Parallel Implementation ✅
- Local storage implemented alongside existing HF system
- User can choose storage mode in settings
- No disruption to existing functionality

### Phase 2: Enhanced Features (Next)
- Conversation import/export
- Bidirectional sync in hybrid mode
- Conflict resolution for synced conversations
- Bulk migration tools

### Phase 3: Local-First Default (Future)
- Default new installations to local storage
- HF integration becomes optional enhancement
- Full offline-first experience

## Benefits

### For Users
- **Immediate functionality** - no login required to start chatting
- **Privacy** - conversations stay local by default
- **Reliability** - works without internet connection
- **Flexibility** - choose your preferred storage method
- **Data ownership** - full control over conversation data

### For Developers
- **Modular design** - easy to extend or modify storage backends
- **Testable** - local storage enables better testing
- **Maintainable** - clean separation of concerns
- **Future-proof** - ready for additional storage providers

## Technical Details

### Storage Location
- **macOS**: `~/Library/Application Support/HuggingChat-Mac/conversations.sqlite`
- **Automatic backup** - included in Time Machine
- **iCloud sync** - possible future enhancement

### Performance
- **SQLite** - Fast, reliable, battle-tested
- **Indexed queries** - Optimized for common operations
- **Lazy loading** - Messages loaded on demand
- **Memory efficient** - Only active conversation in memory

### Security
- **Local encryption** - Database can be encrypted (future)
- **Secure defaults** - No data transmitted unless explicitly synced
- **User control** - Clear visibility into where data is stored

## Usage Examples

### Starting Fresh (Local Mode)
1. Launch app
2. Start chatting immediately - no login required
3. All conversations stored locally
4. Full functionality available offline

### Existing Users (HuggingFace Mode)
1. App detects existing HF authentication
2. Continues working as before
3. Can optionally switch to local or hybrid mode
4. Smooth transition without data loss

### Best of Both (Hybrid Mode)
1. Primary storage is local (instant access)
2. Automatic sync when HF authentication available
3. Works offline, syncs when online
4. Conflict resolution for simultaneous edits

## Troubleshooting

### Common Issues
- **Permission errors** - Check Application Support folder permissions
- **Sync conflicts** - Use conflict resolution UI in hybrid mode
- **Authentication failures** - Clear HF cookies and re-login

### Debug Information
- Storage status visible in chat toolbar
- Detailed logs for storage operations
- Settings panel shows current configuration

## Future Enhancements

### Planned Features
- **Conversation encryption** - Local database encryption option
- **Cloud providers** - Support for additional sync services
- **Export formats** - PDF, HTML, plain text export options
- **Search** - Full-text search across all conversations
- **Tags/Categories** - Organize conversations with metadata

### Integration Opportunities
- **MCP Tools** - Enhanced integration with Model Context Protocol
- **Local Models** - Optimized for local AI model inference
- **Plugins** - Extensible storage and sync plugins
- **APIs** - Developer APIs for conversation data access
