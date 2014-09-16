local InputContainer = require("ui/widget/container/inputcontainer")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderExcludeScreensaver = InputContainer:new{
    menu_title = _("Exclude book from screensaver"),
    exclude = 0
}

function ReaderExcludeScreensaver:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderExcludeScreensaver:onReadSettings(config)
    self.exclude = config:readSetting("exclude_screensaver") or 0
end

function ReaderExcludeScreensaver:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.typeset, {
        text = _("Use this book's cover as screensaver"),
        checked_func = function() return self.exclude == 0 end,
        callback = function()
            self.exclude = 1 - self.exclude
            self.ui.doc_settings:saveSetting("exclude_screensaver", self.exclude)
            self.ui:saveSettings()
        end
    })
end

return ReaderExcludeScreensaver
