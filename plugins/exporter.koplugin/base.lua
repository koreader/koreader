--[[--
Base for highlight exporters.

Each target should inherit from this class and implement *at least* an `export` function.

@module baseexporter
]]

local DataStorage = require("datastorage")
local Device = require("device")
local util = require("util")
local _ = require("gettext")

local BaseExporter = {
    clipping_dir = DataStorage:getFullDataDir() .. "/clipboard"
}

function BaseExporter:new(o)
    o = o or {}
    assert(type(o.name) == "string", "name is mandatory")
    setmetatable(o, self)
    self.__index = self
    return o:_init()
end

function BaseExporter:_init()
    self.extension = self.extension or self.name
    self.is_remote = self.is_remote or false
    self.version = self.version or "1.0.0"
    self.shareable = self.is_remote and nil or Device:canShareText()
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
Export timestamp

@treturn string timestamp
]]
function BaseExporter:getTimeStamp()
    local ts = self.timestamp or os.time()
    return os.date("%Y-%m-%d-%H-%M-%S", ts)
end

--[[--
Exporter version

@treturn string version
]]
function BaseExporter:getVersion()
    return self.name .. "/" .. self.version
end

--[[--
Loads settings for the exporter
]]
function BaseExporter:loadSettings()
    local plugin_settings = G_reader_settings:readSetting("exporter") or {}
    self.settings = plugin_settings[self.name] or {}
end

--[[--
Saves settings for the exporter
]]
function BaseExporter:saveSettings()
    local plugin_settings = G_reader_settings:readSetting("exporter") or {}
    plugin_settings[self.name] = self.settings
    G_reader_settings:saveSetting("exporter", plugin_settings)
    self.new_settings = true
end

--[[--
Exports a table of booknotes to local format or remote service

@param t table of booknotes
@treturn bool success
]]
function BaseExporter:export(t) end

--[[--
File path where the exporter writes its output

@param t table of booknotes
@treturn string absolute path or nil
]]
function BaseExporter:getFilePath(t)
    if self.is_remote then return end
    local plugin_settings = G_reader_settings:readSetting("exporter") or {}
    local clipping_dir = plugin_settings.clipping_dir or self.clipping_dir
    local title
    if #t == 1 then
        title = t[1].output_filename
        if plugin_settings.clipping_dir_book then
            clipping_dir = util.splitFilePathName(t[1].file):sub(1, -2)
        end
    else
        title = self.all_books_title or "all-books"
    end
    local filename = string.format("%s-%s.%s", self:getTimeStamp(), title, self.extension)
    return clipping_dir .. "/" .. util.getSafeFilename(filename)
end

--[[--
Configuration menu for the exporter

@treturn table menu with exporter settings
]]
function BaseExporter:getMenuTable()
    return {
        text = self.name:gsub("^%l", string.upper),
        checked_func = function()
            return self:isEnabled()
        end,
        callback = function()
            self:toggleEnabled()
        end,
    }
end

--[[--
Checks if the exporter is ready to export

@treturn bool ready
]]
function BaseExporter:isReadyToExport()
    return true
end

--[[--
Checks if the exporter was enabled by the user and it is ready to export

@treturn bool enabled
]]
function BaseExporter:isEnabled()
    return self.settings.enabled and self:isReadyToExport()
end

--[[--
Toggles exporter enabled state if it's ready to export
]]
function BaseExporter:toggleEnabled()
    if self:isReadyToExport() then
        self.settings.enabled = not self.settings.enabled
        self:saveSettings()
    end
end

--[[--
Shares text with other apps
]]
function BaseExporter:shareText(text, title)
    local reason = _("Share") .. " " .. self.name
    Device:doShareText(text, reason, title, self.mimetype)
end

return BaseExporter
