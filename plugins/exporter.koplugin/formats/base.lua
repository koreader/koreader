local DataStorage = require("datastorage")

local BaseExporter = {}

function BaseExporter:new(o)
    o = o or {}
    o.id = "exporter"
    o.name = o.name or "generic"
    o.extension = o.extension or o.name or "export"
    o.clipping_dir = DataStorage:getDataDir() .. "/clipboard"
    o.is_remote = o.is_remote or false
    setmetatable(o, self)
    self.__index = self
    return o:init()
end

function BaseExporter:init()
    self:loadSettings()

    return self
end

function BaseExporter:isEnabled()
    return self.settings.enabled
end

function BaseExporter:toggleEnabled()
    self.settings.enabled = not self.settings.enabled
    self:saveSettings()
end

function BaseExporter:loadSettings()
    local plugin_settings = G_reader_settings:readSetting(self.id) or {}
    self.settings = plugin_settings[self.name] or {}
end

function BaseExporter:saveSettings()
    local plugin_settings = G_reader_settings:readSetting(self.id) or {}
    plugin_settings[self.name] = self.settings
    G_reader_settings:saveSetting(self.id, plugin_settings)
end

function BaseExporter:export(t) end

function BaseExporter:getTimeStamp()
    local ts = self.timestamp or os.time()
    return os.date("%Y-%m-%d %H:%M:%S", ts)
end

function BaseExporter:getFilePath(title)
    if title then
        return self.clipping_dir .. "/" .. self:getTimeStamp() .. "-" .. title .. "." .. self.extension
    else
        return self.clipping_dir .. "/" .. self:getTimeStamp() .. "-all-books." .. self.extension
    end
end

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

return BaseExporter
