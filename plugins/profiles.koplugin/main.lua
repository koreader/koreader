local DataStorage = require("datastorage")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local T = FFIUtil.template

local Profiles = WidgetContainer:new{
    name = "profiles",
}

local last_profile = 1
local number_of_profiles = 2

function Profiles:init()
    logger.info("Profiles:init()")
    self.ui.menu:registerToMainMenu(self)
end

function Profiles:addToMainMenu(menu_items)
    logger.info("Profiles:addToMainMenu")
    menu_items.profiles = {
        text = _("Profiles"),
        sub_item_table = {
            {
                text = _("Profile 1"),
                keep_menu_open = true,
                callback = function()
                    -- Profile configuration via GUI not yet implemented
                    logger.dbg("Profile 1 menu callback")
                end,
            },
            {
                text = _("Profile 2"),
                keep_menu_open = true,
                callback = function()
                    -- Profile configuration via GUI not yet implemented
                    logger.dbg("Profile 2 menu callback")
                end,
            },
            {
                text = _("Load next profile"),
                callback = function()
                    self.ui:handleEvent(Event:new("LoadNextProfile"))
                end,
            },
            {
                text = _("Load previous profile"),
                callback = function()
                    self.ui:handleEvent(Event:new("LoadPreviousProfile"))
                end,
            },
        },
    }
end

function Profiles:loadProfile(profile_number)
    local profile_path = T(_("%1/profiles/profile_%2.lua"), DataStorage:getFullDataDir(), profile_number)
    logger.dbg("Executing profile file", profile_path)
    local ok, err = xpcall(dofile, debug.traceback, profile_path)
    if not ok then
        logger.dbg("Problem executing profile:", err)
    end
end

function Profiles:onLoadNextProfile()
    last_profile = last_profile + 1
    if last_profile > number_of_profiles then
        last_profile = 1
    end
    self:loadProfile(last_profile)
end

function Profiles:onLoadPreviousProfile()
    last_profile = last_profile - 1
    if last_profile <= 0 then
        last_profile = 1
    end
    self:loadProfile(last_profile)
end

return Profiles
