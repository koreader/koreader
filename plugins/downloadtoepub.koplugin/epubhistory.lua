local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")
local logger = require("logger")

local History = {
    history_file = "downloadtoepub_history.lua",
    lua_settings = nil,
}

History.STACK = "stack"
History.MAX_ITEMS = 100

function History:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o
end

function History:init()
    self.lua_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.history_file))
end

function History:add(url, download_path)
    -- Add to the history by pushing to the first element of the list.
    -- The history stack should only contain one entry of a given ID.
    local stack = self.lua_settings:readSetting(History.STACK) or {}
    -- Add the new entry to the stack table.
    table.insert(stack, {
            url = url,
            download_path = download_path,
            timestamp = os.time(os.date("!*t"))
    })
    -- Sort the table by the timestamp key.
    table.sort(stack, function(a,b) return a.timestamp > b.timestamp end)
    -- Delete duplicate entries, given by puzzle id, by looping through
    -- the stack and keeping the first occurance (i.e.: newest) of
    -- a URL.
    local new_stack = {}
    local duplicates = {}
    local index = 1
    for i, value in ipairs(stack) do
        if duplicates[value.url] == nil then
            duplicates[value.url] = true
            table.insert(new_stack, value)
            index = index + 1
        end
        if index > History.MAX_ITEMS then
            break;
        end
    end
    -- Save 'er.
    self.lua_settings:saveSetting(History.STACK, new_stack)
    self.lua_settings:flush()
end

function History:get()
    local stack = self.lua_settings:readSetting(History.STACK) or {}
    return stack
end

function History:save()

end

function History:clear()
    self.lua_settings:saveSetting(History.STACK, {})
    self.lua_settings:flush()
end

return History
