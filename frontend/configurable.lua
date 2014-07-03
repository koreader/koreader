local Configurable = {}

function Configurable:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Configurable:reset()
    for key,value in pairs(self) do
        if type(value) == "number" or type(value) == "string" then
            self[key] = nil 
        end
    end
end

function Configurable:hash(sep)
    local hash = ""
    local excluded = {multi_threads = true,}
    for key,value in pairs(self) do
        if type(value) == "number" or type(value) == "string" then 
            hash = hash..sep..value
        end
    end
    return hash
end

function Configurable:loadDefaults(config_options)
    -- reset configurable before loading new options
    self:reset()
    for i=1,#config_options do
        local options = config_options[i].options
        for j=1,#config_options[i].options do
            local key = config_options[i].options[j].name
            local settings_key = config_options.prefix.."_"..key
            local default = G_reader_settings:readSetting(settings_key)
            self[key] = default or config_options[i].options[j].default_value
            if not self[key] then
                self[key] = config_options[i].options[j].default_arg
            end
        end
    end
end

function Configurable:loadSettings(settings, prefix)
    for key,value in pairs(self) do
        if type(value) == "number" or type(value) == "string"
            or type(value) == "table" then
            local saved_value = settings:readSetting(prefix..key)
            self[key] = (saved_value == nil) and self[key] or saved_value
            --Debug("Configurable:loadSettings", "key", key, "saved value", 
            --saved_value,"Configurable.key", self[key])
        end
    end
    --Debug("loaded config:", dump(Configurable))
end

function Configurable:saveSettings(settings, prefix)
    for key,value in pairs(self) do
        if type(value) == "number" or type(value) == "string"
            or type(value) == "table" then
            settings:saveSetting(prefix..key, value)
        end
    end
end

return Configurable
