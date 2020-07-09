local CreOptions = require("ui/data/creoptions")
local Device = require("device")
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
    A true value for the correct section to display in.
--]]--
local settingsList = {
    --Device settings
    show_frontlight_dialog = { category="toggle", event="ShowFlDialog", title=_("Show frontlight dialog"), Device=true, condition=Device:hasFrontlight()},
    toggle_frontlight = { category="toggle", event="ToggleFrontlight", title=_("Toggle frontlight"), Device=true, condition=Device:hasFrontlight()},
    toggle_gsensor = { category="toggle", event="ToggleGSensor", title=_("Toggle accelerometer"), Device=true, condition=Device:canToggleGSensor()},
    wifi_on = { category="toggle", event="InfoWifiOn", title=_("Turn on Wi-Fi"), Device=true, condition=Device:hasWifiToggle()},
    wifi_off = { category="toggle", event="InfoWifiOff", title=_("Turn off Wi-Fi"), Device=true, condition=Device:hasWifiToggle()},
    toggle_wifi = { category="toggle", event="ToggleWifi", title=_("Toggle Wi-Fi"), Device=true, condition=Device:hasWifiToggle()},

    --CreOptions
    rotation_mode = {category="string", Device=true},
    visible_pages = {category="string", Crengine=true},
    h_page_margins = {category="string", Crengine=true},
    sync_t_b_page_margins = {category="string", Crengine=true},
    t_page_margin = {category="absolutenumber", Crengine=true},
    b_page_margin = {category="absolutenumber", Crengine=true},
    view_mode = {category="string", Crengine=true},
    block_rendering_mode = {category="string", Crengine=true},
    render_dpi = {category="string", Crengine=true},
    line_spacing = {category="absolutenumber", Crengine=true},
    font_size = {category="absolutenumber", title="Font Size", Crengine=true},
    font_weight = {category="string", Crengine=true},
    --font_gamma = {category="string", Crengine=true},
    font_hinting = {category="string", Crengine=true},
    font_kerning = {category="string", Crengine=true},
    status_line = {category="string", Crengine=true},
    embedded_css = {category="string", Crengine=true},
    embedded_fonts = {category="string", Crengine=true},
    smooth_scaling = {category="string", Crengine=true},
    nightmode_images = {category="string", Crengine=true},
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
                        settingsList[option.name].toggle = option.toggle or option.labels
                        if settingsList[option.name].toggle == nil then
                        settingsList[option.name].toggle = {}
                            for z=1,#option.values do
                                if type(option.values[z]) == "table" then
                                    settingsList[option.name].toggle[z] = option.values[z][1]
                                end
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

function Dispatcher:addItem(menu, location, settings, section)
    for k, v in pairs(settingsList) do
        if settingsList[k][section] == true and
        (settingsList[k].condition == nil or settingsList[k].condition) then
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
    for _,section in ipairs({"Device", "Crengine",}) do
        local submenu = {}
         Dispatcher.addItem(self, submenu, location, settings, section)
        table.insert(menu, {
            text = section,
            sub_item_table = submenu,
        })
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
