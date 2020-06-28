local DataStorage = require("datastorage")
local FontRepo = require "fontrepo"

local function getKey()
    local user_key_path = DataStorage:getSettingsDir() .. "gfonts-api.txt"
    local keyfile = io.open(user_key_path, "r")
    if keyfile then
        local key = keyfile:read("*a")
        keyfile:close()
        return key
    end
    return "AIzaSyDQZaihK8Lb7jJ3DYyrQrpyyJF7tyvrqAs"
end

local blacklist = {
    "Noto Sans",
    "Noto Sans HK",
    "Noto Sans JP",
    "Noto Sans KR",
    "Noto Sans SC",
    "Noto Sans TC",
    "Noto Serif",
    "Noto Serif HK",
    "Noto Serif JP",
    "Noto Serif KR",
    "Noto Serif SC",
    "Noto Serif TC",
}

local repo = FontRepo:new{
    id = "Google Fonts",
    url = "https://www.googleapis.com/webfonts/v1/webfonts?",
    key = getKey(),
}

function repo:fontTable()
    local t = self:getFontTable()
    -- remove blacklisted entries
    for _, family in ipairs(blacklist) do
        for index, font in ipairs(t.items) do
            if family == font.family then
                table.remove(t.items, index)
            end
        end
    end
    return t.items
end

return repo
