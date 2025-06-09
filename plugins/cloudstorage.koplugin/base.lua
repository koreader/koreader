--[[--
Base for cloud storage providers.

Each provider should inherit from this class and implement *at least* a `list` function.

@module basecloudstorage
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local BaseCloudStorage = {
    settings_dir = DataStorage:getSettingsDir()
}

function BaseCloudStorage:new(o)
    o = o or {}
    logger.dbg("BaseCloudStorage:new", o.name)
    assert(type(o.name) == "string", "name is mandatory")
    setmetatable(o, self)
    self.__index = self
    return o:_init()
end

function BaseCloudStorage:_init()
    self.version = self.version or "1.0.0"
    self:loadSettings()
    if type(self.init_callback) == "function" then
        local changed, settings = self:init_callback(self.settings)
        if changed then
            self.settings = settings
            self:saveSettings()
        end
    end
    return self
end

--[[--
Provider version

@treturn string version
]]
function BaseCloudStorage:getVersion()
    return self.name .. "/" .. self.version
end

--[[--
Loads settings for the provider
]]
function BaseCloudStorage:loadSettings()
    local settings_file = self.settings_dir .. "/cloudstorage_" .. self.name .. ".lua"
    self.settings = LuaSettings:open(settings_file)
end

--[[--
Saves settings for the provider
]]
function BaseCloudStorage:saveSettings()
    if self.settings then
        self.settings:flush()
        self.new_settings = true
    end
end

--[[--
Lists files and folders in a cloud storage location

@param address string server address
@param username string username
@param password string password
@param path string path to list
@param folder_mode bool whether in folder selection mode
@treturn table list of items or nil, error
]]
function BaseCloudStorage:list(address, username, password, path, folder_mode)
    error("list function must be implemented by provider")
end

--[[--
Downloads a file from cloud storage

@param item table file item to download
@param address string server address
@param username string username
@param password string password
@param local_path string local file path to save to
@param callback_close function callback when download completes
]]
function BaseCloudStorage:download(item, address, username, password, local_path, callback_close)
    logger.warn("download function not implemented by provider", self.name)
end

--[[--
Synchronizes files from cloud storage to local folder

@param item table server configuration
@param address string server address
@param username string username
@param password string password
@param on_progress function progress callback
@treturn table sync results
]]
function BaseCloudStorage:sync(item, address, username, password, on_progress)
    logger.warn("sync function not implemented by provider", self.name)
    return nil
end

--[[--
Uploads a file to cloud storage

@param url_base string base URL for upload
@param address string server address
@param username string username
@param password string password
@param file_path string local file path to upload
@param callback_close function callback when upload completes
]]
function BaseCloudStorage:upload(url_base, address, username, password, file_path, callback_close)
    logger.warn("upload function not implemented by provider", self.name)
end

--[[--
Creates a folder in cloud storage

@param url_base string base URL
@param address string server address
@param username string username
@param password string password
@param folder_name string name of folder to create
@param callback_close function callback when creation completes
]]
function BaseCloudStorage:create_folder(url_base, address, username, password, folder_name, callback_close)
    logger.warn("create_folder function not implemented by provider", self.name)
end

--[[--
Shows provider-specific information

@param item table server configuration
]]
function BaseCloudStorage:info(item)
    local info_text = string.format("Provider: %s\nVersion: %s", self.name, self:getVersion())
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{text = info_text})
end

--[[--
Checks if the provider is ready for operation

@treturn bool ready
]]
function BaseCloudStorage:isReadyToOperate()
    return true
end

--[[--
Gets configuration fields for the provider

@treturn table configuration fields
]]
function BaseCloudStorage:getConfigFields()
    return self.config_fields or {}
end

--[[--
Gets configuration title for the provider

@treturn string title
]]
function BaseCloudStorage:getConfigTitle()
    return self.config_title or string.format("Configure %s", self.name)
end

--[[--
Gets configuration info for the provider

@treturn string info text
]]
function BaseCloudStorage:getConfigInfo()
    return self.config_info
end

return BaseCloudStorage
