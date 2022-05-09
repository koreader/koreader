--[[--
Base for highlight exporters.

Each target should inherit from this class and implement *at least* an `export` function.

@module baseexporter
]]

local BaseExporter = {
    clipping_dir = require("datastorage"):getDataDir() .. "/clipboard"
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
    self:loadSettings()
    return self
end

--[[--
Called after loading the exporter and its settings.

You can use it if the exporter requires some tweaks before it is able to show their own UI settings
]]
function BaseExporter:onInit()
end

--[[--
Export timestamp

@treturn string timestamp
]]
function BaseExporter:getTimeStamp()
    local ts = self.timestamp or os.time()
    return os.date("%Y-%m-%d %H:%M:%S", ts)
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
    if not self.is_remote then
        return string.format("%s/%s-%s.%s",
            self.clipping_dir,
            self:getTimeStamp(),
            #t == 1 and t[1].title or "all-books",
            self.extension)
    end
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

return BaseExporter
