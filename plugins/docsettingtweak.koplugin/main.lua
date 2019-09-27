local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local dirname = require("ffi/util").dirname
local util = require("util")

local DocSettingTweak = WidgetContainer:new{
    name = 'docsettingtweak',
}

local directory_defaults = {
}

function DocSettingTweak:onDocSettingsLoad(doc_settings, docfile)
    if next(doc_settings.data) == nil then
--        local defaults = G_reader_settings:readSetting("directory_defaults")
        local base = G_reader_settings:readSetting("home_dir") or "/"
        local directory = docfile and docfile ~= "" and dirname(docfile)
        while directory:sub(1, #base) == base do
            if directory_defaults[directory] then
                doc_settings.data = util.tableDeepCopy(directory_defaults[directory])
                break
            else
                directory = dirname(directory)
            end
        end
    end
    return true
end

return DocSettingTweak
