local ffiUtil = require("ffi/util")

local Configurable = {}

function Configurable:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Configurable:reset()
    for key, value in pairs(self) do
        local value_type = type(value)
        if value_type == "number" or value_type == "string" then
            self[key] = nil
        end
    end
end

function Configurable:hash(list)
    for key, value in ffiUtil.orderedPairs(self) do
        local value_type = type(value)
        if value_type == "number" or value_type == "string" then
            table.insert(list, value)
        end
    end
end

function Configurable:loadDefaults(config_options)
    -- reset configurable before loading new options
    self:reset()
    local prefix = config_options.prefix.."_"
    for i=1, #config_options do
        local options = config_options[i].options
        for j=1,#options do
            local key = options[j].name
            local settings_key = prefix..key
            local default = G_reader_settings:readSetting(settings_key)
            self[key] = default or options[j].default_value
            if not self[key] then
                self[key] = options[j].default_arg
            end
        end
    end
end

function Configurable:loadSettings(settings, prefix)
    for key, value in pairs(self) do
        local value_type = type(value)
        if value_type == "number" or value_type == "string"
            or value_type == "table" then
            local saved_value = settings:readSetting(prefix..key)
            if saved_value ~= nil then
                self[key] = saved_value
            end
        end
    end
end

function Configurable:saveSettings(settings, prefix)
    for key, value in pairs(self) do
        local value_type = type(value)
        if value_type == "number" or value_type == "string"
            or value_type == "table" then
            settings:saveSetting(prefix..key, value)
        end
    end
end

return Configurable
