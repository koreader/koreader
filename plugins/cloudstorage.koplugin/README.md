# Cloud Storage Plugin

A modular cloud storage plugin system for KOReader that supports multiple cloud storage providers through a unified plugin architecture.

## Features

- **Multiple Provider Support**: Dropbox, WebDAV, and FTP providers
- **Unified Sync Engine**: Common synchronization logic across all providers
- **Memory Efficient**: Streaming file operations and optimized memory usage
- **Progress Tracking**: Real-time sync progress with UI feedback
- **Error Handling**: Robust error recovery and user-friendly error messages
- **Security Focused**: Secure credential handling and minimal logging exposure

## Architecture

The cloud storage system uses a provider-based architecture:

```
plugins/
├── cloudstorage.koplugin/           # Main plugin
│   ├── main.lua                     # Plugin entry point
│   ├── base.lua                     # Base provider class
│   └── synccommon.lua               # Shared sync utilities
├── provider-dropbox-cloudstorage.koplugin/    # Dropbox provider
├── provider-webdav-cloudstorage.koplugin/     # WebDAV provider
└── provider-ftp-cloudstorage.koplugin/        # FTP provider
```

### Base Provider Class

All providers inherit from `BaseCloudStorage` which provides:
- Settings management (load/save)
- Version tracking
- Common interface definitions
- Configuration field management

### SyncCommon Module

Shared utilities for all providers:
- Recursive file scanning (local and remote)
- Directory creation with proper error handling
- File comparison logic (size, modification time)
- Progress callback management
- Memory-safe file operations
- UI responsiveness during long operations

## Provider Implementation

### Required Methods

Each provider must implement:

```lua
function Provider:list(address, username, password, path, folder_mode)
    -- Return table of files/folders or nil, error_msg
end
```

### Optional Methods

```lua
function Provider:download(item, address, username, password, local_path, callback_close)
    -- Download file with UI feedback
end

function Provider:sync(item, address, username, password, on_progress)
    -- Synchronize files with progress tracking
    -- Return SyncCommon.init_results() structure
end

function Provider:info(item)
    -- Show provider-specific information
end
```

### Sync Results Structure

```lua
{
    downloaded = 0,     -- Number of files downloaded
    failed = 0,         -- Number of failed operations
    skipped = 0,        -- Number of files skipped (up-to-date)
    deleted_files = 0,  -- Number of local files deleted
    deleted_folders = 0,-- Number of local folders deleted  
    errors = {}         -- Array of error messages
}
```

## Configuration

### Provider Registration

```lua
Provider:register("cloudstorage", "provider_name", {
    name = _("Display Name"),
    list = function(...) return Provider:list(...) end,
    download = function(...) return Provider:download(...) end,
    sync = function(...) return Provider:sync(...) end,
    config_title = _("Configuration Title"),
    config_fields = {
        {name = "field_name", hint = _("Field description"), text_type = "password"},
        -- ...
    },
    config_info = _("Additional configuration help text")
})
```

### Configuration Fields

Standard field types:
- `name`: Display name for the account
- `address`: Server URL or endpoint
- `username`: Authentication username  
- `password`: Authentication password/token (use `text_type = "password"`)
- `url`: Base path or folder

## Security Considerations

### Credential Handling
- Passwords and tokens are stored in encrypted settings
- No credential exposure in debug logs
- Secure token exchange for OAuth2 providers

### Network Security
- HTTPS enforcement for WebDAV when possible
- FTP security warnings about plain-text transmission
- Proper SSL/TLS certificate validation

### File System Security
- Path traversal protection
- Safe file operations with proper cleanup
- Permission checks before file operations

## Error Handling

### Network Errors
- Automatic retry logic with exponential backoff
- Network connectivity detection
- Timeout handling for large file operations

### File System Errors
- Graceful handling of permission denied
- Disk space checks before large downloads
- Atomic file operations where possible

### User Experience
- Progress indicators for long operations
- Meaningful error messages
- Operation cancellation support

## Performance Optimizations

### Memory Management
- Streaming file operations to avoid loading large files in memory
- Periodic garbage collection during long operations
- Efficient data structures for file listings

### Network Efficiency
- Connection reuse where supported
- Chunked transfer encoding
- Compression support when available

### UI Responsiveness
- Yielding control during long operations
- Background processing for sync operations
- Real-time progress updates

## Usage Examples

### Basic File Listing
```lua
local files, err = provider:list(address, username, password, "/folder", false)
if files then
    for _, file in ipairs(files) do
        print(file.text, file.type, file.size)
    end
else
    print("Error:", err)
end
```

### Synchronization with Progress
```lua
local function on_progress(kind, current, total, filename)
    print(string.format("%s: %d/%d %s", kind, current, total, filename or ""))
end

local results = provider:sync(item, address, username, password, on_progress)
print(string.format("Downloaded: %d, Failed: %d, Skipped: %d", 
    results.downloaded, results.failed, results.skipped))
```

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify credentials are correct
   - Check if OAuth2 tokens need refresh
   - Ensure account has proper permissions

2. **Network Connectivity**
   - Test basic connectivity to server
   - Check firewall and proxy settings
   - Verify SSL/TLS certificate validity

3. **Sync Issues**
   - Check local folder permissions
   - Verify sufficient disk space
   - Review sync folder configuration

### Debug Logging

Enable debug logging for detailed troubleshooting:
```lua
logger.dbg("CloudStorage: Debug message")
```

Note: Debug logs automatically filter out sensitive credential information.

## Contributing

### Adding New Providers

1. Create new provider plugin directory: `provider-{name}-cloudstorage.koplugin/`
2. Implement provider class inheriting from `BaseCloudStorage`
3. Implement required methods (`list` minimum)
4. Register provider with `Provider:register()`
5. Add configuration fields and help text
6. Test with various file types and folder structures

### Provider Guidelines

- Follow existing naming conventions
- Implement proper error handling
- Use SyncCommon utilities for file operations
- Add comprehensive configuration help
- Include security warnings where appropriate
- Test with large file sets and slow networks

## API Reference

See individual provider files and `base.lua` for complete API documentation.

## License

This plugin follows the same license as KOReader.
