local Event = require("ui/event")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
--local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local Dispatcher = {}
--[[--
contains a list of a dispatchable settings
each setting contains:
    category: one of none, toggle, absolutenumber, incrementalnumber, or string.
    event: what to call.
    title: for use in ui.
and optionally
    min/max: for number
    values: allowed values for string.
    conditions: (is document open, etc.)
--]]--
local settingsList = {
    page_jmp = { ["category"]="incrementalnumber", ["event"]="GotoViewRel" , ["title"]=_("Go %1 pages"),["min"]=-50, ["max"]=50},
    prev_chapter = { ["category"]="none", ["event"]="GotoPrevChapter", ["title"]=_("Previous chapter"), },
    next_chapter = { ["category"]="none", ["event"]="GotoNextChapter", ["title"]=_("Next chapter"), },
    prev_bookmark = { ["category"]="none", ["event"]="GotoPreviousBookmarkFromPage", ["title"]=_("Previous bookmark"), },
    next_bookmark = { ["category"]="none", ["event"]="GotoNextBookmarkFromPage", ["title"]=_("Next bookmark"), },
    go_to = { ["category"]="none", ["event"]="ShowGotoDialog", ["title"]=_("Go to"), },
    skim = { ["category"]="none", ["event"]="ShowSkimtoDialog", ["title"]=_("Skim"), },
    back = { ["category"]="none", ["event"]="Back", ["title"]=_("Back"), },
--[[    previous_location = { ["category"]= , ["event"]= , ["title"]=_("Back to previous location"), },
    latest_bookmark = { ["category"]="none", ["event"]= , ["title"]=_("Go to latest bookmark"), },
    follow_nearest_link = { ["category"]= , ["event"]= , ["title"]=_("Follow nearest link"), },
    follow_nearest_internal_link = { ["category"]= , ["event"]= , ["title"]=_("Follow nearest internal link"), },
    clear_location_history = { ["category"]= , ["event"]= , ["title"]=_("Clear location history"), },
]]
    toc = { ["category"]="none", ["event"]="ShowToc", ["title"]=_("Table of contents"), },
    bookmarks = { ["category"]="none", ["event"]="ShowBookmark", ["title"]=_("Bookmarks"), },
--[[    reading_progress = { ["category"]= , ["event"]= , ["title"]=_("Reading progress"), },
    book_statistics = { ["category"]= , ["event"]= , ["title"]=_("Book statistics"), },
]]    book_status = { ["category"]="none", ["event"]="ShowBookStatus", ["title"]=_("Book status"), },
    book_info = { ["category"]="none", ["event"]="ShowBookInfo", ["title"]=_("Book information"), },
    book_description = { ["category"]="none", ["event"]="ShowBookDescription", ["title"]=_("Book description"), },
    book_cover = { ["category"]="none", ["event"]="ShowBookCover", ["title"]=_("Book cover"), },
--    stats_calendar_view = { ["category"]= , ["event"]= , ["title"]=_("Statistics calendar view"), },

    history = { ["category"]="none", ["event"]="ShowHist", ["title"]=_("History"), },
--    open_previous_document = { ["category"]= , ["event"]= , ["title"]=_("Open previous document"), },
--    filemanager = { ["category"]= , ["event"]= , ["title"]=_("File browser"), },
 --   favorites = { ["category"]= , ["event"]= , ["title"]=_("Favorites"), },

    dictionary_lookup = { ["category"]="none", ["event"]="ShowDictionaryLookup", ["title"]=_("Dictionary lookup"), },
    wikipedia_lookup = { ["category"]="none", ["event"]="ShowWikipediaLookup", ["title"]=_("Wikipedia lookup"), },
    fulltext_search = { ["category"]="none", ["event"]="ShowFulltextSearchInput", ["title"]=_("Fulltext search"), },
--[[    file_search = { ["category"]= , ["event"]= , ["title"]=_("File search"), },

    full_refresh = { ["category"]= , ["event"]= , ["title"]=_("Full screen refresh"), },
    night_mode = { ["category"]= , ["event"]= , ["title"]=_("Night mode"), },
    suspend = { ["category"]= , ["event"]= , ["title"]=_("Suspend"), },
    exit = { ["category"]= , ["event"]= , ["title"]=_("Exit KOReader"), },
    restart = { ["category"]= , ["event"]= , ["title"]=_("Restart KOReader"), },
    reboot = { ["category"]= , ["event"]= , ["title"]=_("Reboot the device"), },
    poweroff = { ["category"]= , ["event"]= , ["title"]=_("Power off"), },
    show_menu = { ["category"]= , ["event"]= , ["title"]=_("Show menu"), },
    show_config_menu = { ["category"]= , ["event"]= , ["title"]=_("Show bottom menu"), },
    show_frontlight_dialog = { ["category"]= , ["event"]= , ["title"]=_("Show frontlight dialog"), },
    toggle_frontlight = { ["category"]= , ["event"]= , ["title"]=_("Toggle frontlight"), },
    increase_frontlight = { ["category"]= , ["event"]= , ["title"]=_("Increase frontlight brightness"), },
    decrease_frontlight = { ["category"]= , ["event"]= , ["title"]=_("Decrease frontlight brightness"), },
    increase_frontlight_warmth = { ["category"]= , ["event"]= , ["title"]=_("Increase frontlight warmth"), },
    decrease_frontlight_warmth = { ["category"]= , ["event"]= , ["title"]=_("Decrease frontlight warmth"), },
    toggle_hold_corners = { ["category"]= , ["event"]= , ["title"]=_("Toggle hold corners"), },
    toggle_gsensor = { ["category"]= , ["event"]= , ["title"]=_("Toggle accelerometer"), },
    toggle_rotation = { ["category"]= , ["event"]= , ["title"]=_("Toggle rotation"), },

    wifi_on = { ["category"]= , ["event"]= , ["title"]=_("Turn on Wi-Fi"), },
    wifi_off = { ["category"]= , ["event"]= , ["title"]=_("Turn off Wi-Fi"), },
    toggle_wifi = { ["category"]= , ["event"]= , ["title"]=_("Toggle Wi-Fi"), },
]]
    toggle_bookmark = { ["category"]="none", ["event"]="ToggleBookmark", ["title"]=_("Toggle bookmark"), },
--[[    toggle_page_flipping = { ["category"]= , ["event"]= , ["title"]=_("Toggle page flipping"), },
    toggle_reflow = { ["category"]= , ["event"]= , ["title"]=_("Toggle reflow"), },
    toggle_inverse_reading_order = { ["category"]= , ["event"]= , ["title"]=_("Toggle page turn direction"), },
]]
    zoom = { ["category"]="string", ["event"]="SetZoomMode", ["title"]=_("Zoom to"), ["values"]={"contentwidth", "contentheight", "pagewidth", "pageheight", "column", "content", "page"} },
--[[
    increase_font = { ["category"]= , ["event"]= , ["title"]=_("Increase font size"), },
    decrease_font = { ["category"]= , ["event"]= , ["title"]=_("Decrease font size"), },

    folder_up = { ["category"]= , ["event"]= , ["title"]=_("Folder up"), },
]]    show_plus_menu = { ["category"]="none", ["event"]="ShowPlusMenu", ["title"]=_("Show plus menu"), },
    folder_shortcuts = { ["category"]="none", ["event"]="ShowFolderShortcutsDialog", ["title"]=_("Folder shortcuts"), },
--[[    cycle_highlight_action = { ["category"]= , ["event"]= , ["title"]=_("Cycle highlight action"), },
    cycle_highlight_style = { ["category"]= , ["event"]= , ["title"]=_("Cycle highlight style"), },
    wallabag_download = { ["category"]= , ["event"]= , ["title"]=_("Wallabag retrieval"), },
]]
}

--[[--
Add a submenu to edit which items are dispatched
arguments are:
    1) self
    2) the table representing the submenu (can be empty)
    3) the name of the parent of the settings table (must be a child of self)
    4) the name of the settings table
    5) optionally a function to call when the settings are changed (to save them etc)
example usage:
    Dispatcher.addSubMenu(self, sub_items, "profiles", "profile1")
--]]--
function Dispatcher:addSubMenu(menu, location, settings, dispatchCallback)
    table.insert(menu, {
        text = _("None"),
       checked_func = function()
           return  next(self[location][settings]) == nil
       end,
        callback = function(touchmenu_instance)
            self[location][settings] = {}
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    for k, v in pairs(settingsList) do
            if settingsList[k].category == "none" then
                table.insert(menu, {
                   text = settingsList[k].title,
                   checked_func = function()
                   return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                   end,
                   callback = function(touchmenu_instance)
                      if self[location][settings] ~= nil and self[location][settings][k] then self[location][settings][k] = nil else self[location][settings][k] = true end
                      if touchmenu_instance then touchmenu_instance:updateItems() end
                  end,
               })
            elseif settingsList[k].category == "toggle" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, self[location][settings][k])
                    end,
                    checked_func = function()
                    return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        self[location][settings][k] = not self[location][settings][k]
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            elseif settingsList[k].category == "absolutenumber" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, self[location][settings][k] or 0)
                    end,
                    checked_func = function()
                    return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            width = Screen:getWidth() * 0.6,
                            value = self[location][settings][k] or 0,
                            value_min = settingsList[k].min,
                            value_step = 1,
                            value_hold_step = 2,
                            value_max = settingsList[k].max,
                            default_value = 0,
                            title_text = T(settingsList[k].title, self[location][settings][k] or 0),
                            callback = function(spin)
                                self[location][settings][k] = spin.value
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            elseif settingsList[k].category == "incrementalnumber" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, self[location][settings][k] or 0)
                    end,
                    checked_func = function()
                    return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            width = Screen:getWidth() * 0.6,
                            value = self[location][settings][k] or 0,
                            value_min = settingsList[k].min,
                            value_step = 1,
                            value_hold_step = 2,
                            value_max = settingsList[k].max,
                            default_value = 0,
                            title_text = T(settingsList[k].title, self[location][settings][k] or 0),
                            text = _([[If set to 0 and called by a gesture the amount of the gesture will be used]]),
                            callback = function(spin)
                                self[location][settings][k] = spin.value
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            elseif settingsList[k].category == "string" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, self[location][settings][k])
                    end,
                    checked_func = function()
                    return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        --TODO use a proper list picker widget
                        --UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end
        end
end

function Dispatcher:execute(settings, gesture)
logger.dbg("step 1:", settings)
    for k, v in pairs(settings) do
logger.dbg("step 2",k,v)
        if settingsList[k].conditions == nil or settingsList[k].conditions == true then
logger.dbg("step 3")
            if settingsList[k].category == "none" then
                self.ui:handleEvent(Event:new(settingsList[k].event))
            end
            if settingsList[k].category == "toggle"
            or settingsList[k].category == "absolutenumber"
            or settingsList[k].category == "string" then
                self.ui:handleEvent(Event:new(settingsList[k].event, v))
            end
            if settingsList[k].category == "incrementalnumber" then
                if v then
                    self.ui:handleEvent(Event:new(settingsList[k].event, v))
                else
                    self.ui:handleEvent(Event:new(settingsList[k].event, gesture))
                end
            end
        end
    end
end

return Dispatcher
