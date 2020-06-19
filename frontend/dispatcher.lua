local CreOptions = require("ui/data/creoptions")
local Event = require("ui/event")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Dispatcher = {
    initialized = false,
}

--[[--
contains a list of a dispatchable settings
each setting contains:
    category: one of none, toggle, absolutenumber, incrementalnumber, or string.
    event: what to call.
    title: for use in ui.
and optionally
    min/max: for number
    default
    args: allowed values for string.
    toggle: display name for args
--]]--
local settingsList = {
    --CreOptions
    screen_mode = {category="string"},
    visible_pages = {category="string"},
    h_page_margins = {category="string"},
    sync_t_b_page_margins = {category="string"},
    t_page_margin = {category="absolutenumber"},
    b_page_margin = {category="absolutenumber"},
    view_mode = {category="string", title="View Mode (CRengine)"},
    block_rendering_mode = {category="string"},
    render_dpi = {category="string"},
    line_spacing = {category="absolutenumber"},
    font_size = {category="absolutenumber", title="Font Size (CRengine)"},
    font_weight = {category="string"},
    --font_gamma = {category="string"},
    font_hinting = {category="string"},
    font_kerning = {category="string"},
    status_line = {category="string"},
    embedded_css = {category="string"},
    embedded_fonts = {category="string"},
    smooth_scaling = {category="string"},
    nightmode_images = {category="string"},
}

--[[--
    add settings from CreOptions / KoptOptions
--]]--
function Dispatcher:init()
    local parseoptions = function(base, i)
        for y=1,#base[i].options do
            local option = base[i].options[y]
            if settingsList[option.name] ~= nil then
                if settingsList[option.name].event == nil then
                    settingsList[option.name].event = option.event
                end
                if settingsList[option.name].title == nil then
                    settingsList[option.name].title = option.name_text
                end
                if settingsList[option.name].category == "string" then
                    if settingsList[option.name].toggle == nil then
                        settingsList[option.name].toggle = option.toggle or option.labels or option.values
                        for z=1,#settingsList[option.name].toggle do
                            if type(settingsList[option.name].toggle[z]) == "table" then
                                settingsList[option.name].toggle[z] = settingsList[option.name].toggle[z][1]
                            end
                        end
                    end
                    if settingsList[option.name].args == nil then
                        settingsList[option.name].args = option.args or option.values
                    end
                elseif settingsList[option.name].category == "absolutenumber" then
                    if settingsList[option.name].min == nil then
                        settingsList[option.name].min = option.args[1]
                    end
                    if settingsList[option.name].max == nil then
                        settingsList[option.name].max = option.args[#option.args]
                    end
                    if settingsList[option.name].default == nil then
                        settingsList[option.name].default = option.default_value
                    end
                end
            end
        end
    end
    for i=1,#CreOptions do
        parseoptions(CreOptions, i)
    end
    Dispatcher.initialized = true
end

--[[--
Add a submenu to edit which items are dispatched
arguments are:
    1) self
    2) the table representing the submenu (can be empty)
    3) the name of the parent of the settings table (must be a child of self)
    4) the name of the settings table
example usage:
    Dispatcher.addSubMenu(self, sub_items, "profiles", "profile1")
--]]--
function Dispatcher:addSubMenu(menu, location, settings)
    if not Dispatcher.initialized then Dispatcher:init() end
    table.insert(menu, {
        text = _("None"),
        separator = true,
        checked_func = function()
            return next(self[location][settings]) == nil
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
                      if self[location][settings] ~= nil
                      and self[location][settings][k] then
                          self[location][settings][k] = nil
                      else
                          self[location][settings][k] = true
                      end
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
                        return T(settingsList[k].title, self[location][settings][k] or "")
                    end,
                    checked_func = function()
                    return self[location][settings] ~= nil and self[location][settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            width = Screen:getWidth() * 0.6,
                            value = self[location][settings][k] or settingsList[k].default or 0,
                            value_min = settingsList[k].min,
                            value_step = 1,
                            value_hold_step = 2,
                            value_max = settingsList[k].max,
                            default_value = 0,
                            title_text = T(settingsList[k].title, self[location][settings][k] or ""),
                            callback = function(spin)
                                self[location][settings][k] = spin.value
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
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
                        return T(settingsList[k].title, self[location][settings][k] or "")
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
                            title_text = T(settingsList[k].title, self[location][settings][k] or ""),
                            text = _([[If set to 0 and called by a gesture the amount of the gesture will be used]]),
                            callback = function(spin)
                                self[location][settings][k] = spin.value
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                })
            elseif settingsList[k].category == "string" then
                local sub_item_table = {}
                for i=1,#settingsList[k].args do
                    table.insert(sub_item_table, {
                        text = tostring(settingsList[k].toggle[i]),
                        checked_func = function()
                            return self[location][settings] ~= nil
                            and self[location][settings][k] ~= nil
                            and self[location][settings][k] == settingsList[k].args[i]
                        end,
                        callback = function()
                            self[location][settings][k] = settingsList[k].args[i]
                        end,
                    })
                end
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, self[location][settings][k])
                    end,
                    checked_func = function()
                        return self[location][settings] ~= nil
                        and self[location][settings][k] ~= nil
                    end,
                    sub_item_table = sub_item_table,
                    keep_menu_open = true,
                    hold_callback = function(touchmenu_instance)
                        self[location][settings][k] = nil
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                })
            end
        end
end

function Dispatcher:execute(settings, gesture)
    for k, v in pairs(settings) do
        if settingsList[k].conditions == nil or settingsList[k].conditions == true then
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
