local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local dirname = require("ffi/util").dirname
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")

local DocSettingTweak = WidgetContainer:new{
    name = 'docsettingtweak',
}

local directory_defaults = {
}

function DocSettingTweak:onDocSettingsLoad(doc_settings, docfile)
    if next(doc_settings.data) == nil then
        local base = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
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
