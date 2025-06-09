# CloudStorage Plugin Architecture Documentation

## Overview

The KOReader CloudStorage module has been refactored from a monolithic architecture to a modular plugin-based system. This new architecture provides better separation of concerns, easier maintenance, and simplified addition of new cloud storage providers.

## Architecture Components

### 1. Core CloudStorage Plugin (`cloudstorage.koplugin`)

The main plugin that provides:
- Provider registration interface
- Common UI components and workflows
- Settings management
- Migration support from the old system
- Shared synchronization utilities

### 2. Provider Plugins

Individual plugins for each cloud storage service:
- `provider-dropbox.koplugin` - Dropbox support
- `provider-webdav.koplugin` - WebDAV support  
- `provider-ftp.koplugin` - FTP support

Each provider plugin registers itself with the core CloudStorage plugin.

### 3. External Dependencies

- API modules in `frontend/apps/cloudstorage/`: `dropboxapi.lua`, `webdavapi.lua`, `ftpapi.lua`

## Provider Plugin Interface

Each provider plugin must implement the following interface:

```lua
CloudStorage:registerProvider("provider_id", {
    name = _("Display Name"),
    list = function(address, username, password, path, folder_mode) end,
    download = function(item, address, username, password, local_path, callback_close) end,
    info = function(item) end,  -- optional
    sync = function(item, address, username, password, on_progress) end,  -- optional
    upload = function(url_base, address, username, password, file_path, callback_close) end,  -- optional
    create_folder = function(url_base, address, username, password, folder_name, callback_close) end,  -- optional
    config_title = _("Configuration Dialog Title"),
    config_fields = {
        {name = "field_name", hint = _("Field hint"), text_type = "password"},  -- optional text_type
        -- ... more fields
    },
    config_info = _("Optional configuration help text"),
})
```

### Required Functions

- **list**: Returns a list of files/folders at the given path
- **download**: Downloads a file to the local filesystem

### Optional Functions

- **info**: Shows provider-specific account information
- **sync**: Provides bidirectional synchronization
- **upload**: Uploads files to the cloud service
- **create_folder**: Creates folders on the cloud service

### Configuration Schema

- **config_fields**: Array of field definitions for the setup dialog
- **config_title**: Title for the configuration dialog
- **config_info**: Help text shown in the configuration dialog

## Migration Support

The system includes automatic migration from the old monolithic architecture:

1. Existing server configurations are preserved
2. Settings format remains compatible
3. Migration runs automatically on first load
4. Migration status is tracked to avoid repeated runs

## Benefits of the New Architecture

### For Users
- **Seamless transition**: Existing configurations continue to work
- **Better error handling**: Provider-specific error messages
- **Consistent UI**: Unified interface across all providers
- **Easier troubleshooting**: Clear separation of provider-specific issues

### For Developers
- **Modular design**: Each provider is self-contained
- **Easy to extend**: Adding new providers requires minimal core changes
- **Better testing**: Providers can be tested independently
- **Cleaner code**: Separation of concerns reduces complexity

### For Maintainers
- **Isolated changes**: Provider updates don't affect core functionality
- **Selective loading**: Only required providers are loaded
- **Plugin management**: Providers can be enabled/disabled independently
- **Reduced merge conflicts**: Changes to different providers don't conflict

## Adding New Providers

To add a new cloud storage provider:

1. Create a new plugin directory: `provider-newservice.koplugin/`
2. Add `_meta.lua` with plugin metadata
3. Implement `main.lua` with the provider interface
4. Register the provider with `CloudStorage:registerProvider()`

Example minimal provider:

```lua
local CloudStorage = require("plugins/cloudstorage.koplugin/main")

local function newservice_list(address, username, password, path, folder_mode)
    -- Implementation
end

local function newservice_download(item, address, username, password, local_path, callback_close)
    -- Implementation  
end

CloudStorage:registerProvider("newservice", {
    name = _("New Service"),
    list = newservice_list,
    download = newservice_download,
    config_fields = {
        {name = "name", hint = _("Account name")},
        {name = "username", hint = _("Username")},
        {name = "password", hint = _("Password"), text_type = "password"},
    },
})
```

## File Structure

```
plugins/
├── cloudstorage.koplugin/
│   ├── _meta.lua          # Plugin metadata
│   ├── main.lua           # Core CloudStorage implementation
│   ├── migration.lua      # Migration utilities
│   └── synccommon.lua     # Shared sync utilities
├── provider-dropbox.koplugin/
│   ├── _meta.lua          # Dropbox provider metadata
│   └── main.lua           # Dropbox provider implementation
├── provider-webdav.koplugin/
│   ├── _meta.lua          # WebDAV provider metadata
│   └── main.lua           # WebDAV provider implementation
└── provider-ftp.koplugin/
    ├── _meta.lua          # FTP provider metadata
    └── main.lua           # FTP provider implementation

frontend/apps/cloudstorage/
├── dropboxapi.lua         # Dropbox API (unchanged)
├── webdavapi.lua          # WebDAV API (unchanged)
└── ftpapi.lua             # FTP API (unchanged)
```

## What Can Be Removed

After the migration, the following files from `frontend/apps/cloudstorage/` can be safely removed:
- Any old `cloudstorage.lua` (monolithic implementation)
- Configuration or sync-related files that have been moved to plugins
- Any helper modules that are now part of the plugin system

The API modules (`dropboxapi.lua`, `webdavapi.lua`, `ftpapi.lua`) should be kept as they contain the low-level protocol implementations.

## Backward Compatibility

- Existing server configurations are automatically migrated
- API modules remain unchanged to preserve existing functionality
- Settings file format is preserved
- User workflows remain identical

## Error Handling

The new architecture provides improved error handling:

- Provider-specific error messages
- Graceful degradation when providers are unavailable
- Clear indication of missing or misconfigured providers
- Detailed logging for troubleshooting

## Performance Considerations

- Providers are loaded on-demand
- Registration happens at plugin load time
- No performance impact on users who don't use cloud storage
- Memory usage scales with active providers only

## Security Considerations

- Provider isolation prevents cross-provider data leakage
- Credential handling remains within provider boundaries
- Each provider can implement its own security measures
- Migration preserves existing security configurations
