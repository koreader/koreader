--local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
--local Event = require("ui/event")
--local FFIUtil = require("ffi/util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
--local T = FFIUtil.template

local Profiles = WidgetContainer:new{
    name = "profiles",
    profiles = {},
}

function Profiles:init()
    logger.info("Profiles:init()")
    self.profiles.profile1 = { ["page_jmp"]=2, ["toggle_bookmark"]=true, ["zoom"]="page"}
    self.ui.menu:registerToMainMenu(self)
end

function Profiles:addToMainMenu(menu_items)
    logger.info("Profiles:addToMainMenu")
    local sub_items = {}
    Dispatcher.addSubMenu(self, sub_items, "profiles", "profile1")
    menu_items.profiles = {
        text = _("Profiles"),
        sub_item_table = {
            {
                text = _("Profile 1"),
                keep_menu_open = false,
                sub_item_table = sub_items,
                hold_callback = function()
                    logger.dbg("Profile 1 menu callback")
                    Dispatcher.execute(self, self.profiles.profile1)
                end,
            },
        },
    }
end

return Profiles
