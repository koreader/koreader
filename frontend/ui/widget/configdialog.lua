local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local FixedTextWidget = require("ui/widget/fixedtextwidget")
local ProgressWidget = require("ui/widget/progresswidget")
local ToggleSwitch = require("ui/widget/toggleswitch")
local Font = require("ui/font")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local RectSpan = require("ui/widget/rectspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")

local MenuBarItem = InputContainer:new{}
function MenuBarItem:init()
    self.dimen = self[1]:getSize()
    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Menu Item",
            },
        }
    else
        self.active_key_events = {
            Select = { {"Press"}, doc = "chose selected item" },
        }
    end
end

function MenuBarItem:onTapSelect()
    UIManager:scheduleIn(0.0, function() self:invert(true) end)
    UIManager:scheduleIn(0.1, function()
        UIManager:sendEvent(Event:new("ShowConfigPanel", self.index))
    end)
    UIManager:scheduleIn(0.5, function() self:invert(false) end)
    return true
end

function MenuBarItem:invert(invert)
    self[1].invert = invert
    UIManager:setDirty(self.config, "partial")
end

local OptionTextItem = InputContainer:new{}
function OptionTextItem:init()
    local text_widget = self[1]

    self[1] = UnderlineContainer:new{
        text_widget,
        padding = self.padding,
        color = self.color,
    }
    self.dimen = self[1]:getSize()
    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Option Item",
            },
        }
    else
        self.active_key_events = {
            Select = { {"Press"}, doc = "chose selected item" },
        }
    end
end

function OptionTextItem:onTapSelect()
    for _, item in pairs(self.items) do
        item[1].color = 0
    end
    self[1].color = 15
    self.config:onConfigChoose(self.values, self.name, self.event, self.args, self.events, self.current_item)
    UIManager:setDirty(self.config, "partial")
    return true
end

local OptionIconItem = InputContainer:new{}
function OptionIconItem:init()
    self.dimen = self.icon:getSize()
    self[1] = UnderlineContainer:new{
        self.icon,
        padding = self.padding,
        color = self.color,
    }
    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Option Item",
            },
        }
    end
end

function OptionIconItem:onTapSelect()
    for _, item in pairs(self.items) do
        --item[1][1].invert = false
        item[1].color = 0
    end
    --self[1][1].invert = true
    self[1].color = 15
    self.config:onConfigChoose(self.values, self.name, self.event, self.args, self.events, self.current_item)
    UIManager:setDirty(self.config, "partial")
    return true
end

local ConfigOption = CenterContainer:new{}
function ConfigOption:init()
    local default_name_font_size = 20
    local default_item_font_size = 16
    local default_items_spacing = 30
    local default_option_height = 50
    local default_option_padding = 15
    local vertical_group = VerticalGroup:new{}
    table.insert(vertical_group, VerticalSpan:new{
        width = Screen:scaleByDPI(default_option_padding),
    })
    for c = 1, #self.options do
        if self.options[c].show ~= false then
            local name_align = self.options[c].name_align_right and self.options[c].name_align_right or 0.33
            local item_align = self.options[c].item_align_center and self.options[c].item_align_center or 0.66
            local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "cfont"
            local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
            local item_font_face = self.options[c].item_font_face and self.options[c].item_font_face or "cfont"
            local item_font_size = self.options[c].item_font_size and self.options[c].item_font_size or default_item_font_size
            local option_height = Screen:scaleByDPI(self.options[c].height and self.options[c].height or default_option_height)
            local item_spacing_with = self.options[c].spacing and self.options[c].spacing or default_items_spacing
            local items_spacing = HorizontalSpan:new{
                width = Screen:scaleByDPI(item_spacing_with)
            }
            local horizontal_group = HorizontalGroup:new{}
            if self.options[c].name_text then
                local option_name_container = RightContainer:new{
                    dimen = Geom:new{ w = Screen:getWidth()*name_align, h = option_height},
                }
                local option_name =    TextWidget:new{
                        text = self.options[c].name_text,
                        face = Font:getFace(name_font_face, name_font_size),
                }
                table.insert(option_name_container, option_name)
                table.insert(horizontal_group, option_name_container)
            end

            if self.options[c].widget == "ProgressWidget" then
                local widget_container = CenterContainer:new{
                    dimen = Geom:new{
                        w = Screen:getWidth()*self.options[c].widget_align_center,
                        h = option_height
                    }
                }
                local widget = ProgressWidget:new{
                    width = self.options[c].width,
                    height = self.options[c].height,
                    percentage = self.options[c].percentage,
                }
                table.insert(widget_container, widget)
                table.insert(horizontal_group, widget_container)
            end

            local option_items_container = CenterContainer:new{
                dimen = Geom:new{w = Screen:getWidth()*item_align, h = option_height}
            }
            local option_items_group = HorizontalGroup:new{}
            local option_items_fixed = false
            local option_items = {}
            if type(self.options[c].item_font_size) == "table" then
                option_items_group.align = "bottom"
                option_items_fixed = true
            end
            -- make current index according to configurable table
            local current_item = nil
            local function value_diff(val1, val2, name)
                if type(val1) ~= type(val2) then
                    error("different data types in option", name)
                end
                if type(val1) == "number" then
                    return math.abs(val1 - val2)
                elseif type(val1) == "string" then
                    return val1 == val2 and 0 or 1
                end
            end
            if self.options[c].name then
                if self.options[c].values then
                    -- check if current value is stored in configurable or calculated in runtime
                    local val = self.options[c].current_func and self.options[c].current_func()
                                or self.config.configurable[self.options[c].name]
                    local min_diff = nil
                    if type(val) == "table" then
                        min_diff = value_diff(val[1], self.options[c].values[1][1])
                    else
                        min_diff = value_diff(val, self.options[c].values[1])
                    end

                    local diff = nil
                    for index, val_ in pairs(self.options[c].values) do
                        local diff = nil
                        if type(val) == "table" then
                            diff = value_diff(val[1], val_[1])
                        else
                            diff = value_diff(val, val_)
                        end
                        if val == val_ then
                            current_item = index
                            break
                        end
                        if diff <= min_diff then
                            min_diff = diff
                            current_item = index
                        end
                    end
                elseif self.options[c].args then
                    -- check if current arg is stored in configurable or calculated in runtime
                    local arg = self.options[c].current_func and self.options[c].current_func()
                                or self.config.configurable[self.options[c].name]
                    for idx, arg_ in pairs(self.options[c].args) do
                        if arg_ == arg then
                            current_item = idx
                            break
                        end
                    end
                end
            end
            if self.options[c].item_text then
                local items_count = #self.options[c].item_text
                local middle_index = math.ceil(items_count/2)
                local middle_item = OptionTextItem:new{
                    TextWidget:new{
                        text = self.options[c].item_text[middle_index],
                        face = Font:getFace(item_font_face,
                            option_items_fixed and item_font_size[middle_index]
                            or item_font_size),
                    }
                }
                local max_item_spacing = (Screen:getWidth() * item_align -
                        middle_item:getSize().w * items_count) / items_count
                local items_spacing = HorizontalSpan:new{
                    width = math.min(max_item_spacing, Screen:scaleByDPI(item_spacing_with))
                }
                for d = 1, #self.options[c].item_text do
                    local option_item = nil
                    if option_items_fixed then
                        option_item = OptionTextItem:new{
                            FixedTextWidget:new{
                                text = self.options[c].item_text[d],
                                face = Font:getFace(item_font_face, item_font_size[d]),
                            },
                            padding = 3,
                            color = d == current_item and 15 or 0,
                        }
                    else
                        option_item = OptionTextItem:new{
                            TextWidget:new{
                                text = self.options[c].item_text[d],
                                face = Font:getFace(item_font_face, item_font_size),
                            },
                            padding = -3,
                            color = d == current_item and 15 or 0,
                        }
                    end
                    option_items[d] = option_item
                    option_item.items = option_items
                    option_item.name = self.options[c].name
                    option_item.values = self.options[c].values
                    option_item.args = self.options[c].args
                    option_item.event = self.options[c].event
                    option_item.current_item = d
                    option_item.config = self.config
                    table.insert(option_items_group, option_item)
                    if d ~= #self.options[c].item_text then
                        table.insert(option_items_group, items_spacing)
                    end
                end
            end

            if self.options[c].item_icons then
                local items_count = #self.options[c].item_icons
                local first_item = OptionIconItem:new{
                    icon = ImageWidget:new{
                        file = self.options[c].item_icons[1]
                    }
                }
                local max_item_spacing = (Screen:getWidth() * item_align -
                        first_item:getSize().w * items_count) / items_count
                local items_spacing = HorizontalSpan:new{
                    width = math.min(max_item_spacing, Screen:scaleByDPI(item_spacing_with))
                }
                for d = 1, #self.options[c].item_icons do
                    local option_item = OptionIconItem:new{
                        icon = ImageWidget:new{
                            file = self.options[c].item_icons[d]
                        },
                        padding = -2,
                        color = d == current_item and 15 or 0,
                    }
                    option_items[d] = option_item
                    option_item.items = option_items
                    option_item.name = self.options[c].name
                    option_item.values = self.options[c].values
                    option_item.args = self.options[c].args
                    option_item.event = self.options[c].event
                    option_item.current_item = d
                    option_item.config = self.config
                    table.insert(option_items_group, option_item)
                    if d ~= #self.options[c].item_icons then
                        table.insert(option_items_group, items_spacing)
                    end
                end
            end

            if self.options[c].toggle then
                local max_toggle_width = Screen:getWidth() / 2
                local toggle_width = Screen:scaleByDPI(self.options[c].width or 216)
                local switch = ToggleSwitch:new{
                    width = math.min(max_toggle_width, toggle_width),
                    name = self.options[c].name,
                    toggle = self.options[c].toggle,
                    alternate = self.options[c].alternate,
                    values = self.options[c].values,
                    args = self.options[c].args,
                    event = self.options[c].event,
                    events = self.options[c].events,
                    config = self.config,
                }
                local position = current_item
                switch:setPosition(position)
                table.insert(option_items_group, switch)
            end

            table.insert(option_items_container, option_items_group)
            table.insert(horizontal_group, option_items_container)
            table.insert(vertical_group, horizontal_group)
        end -- if
    end -- for
    table.insert(vertical_group, VerticalSpan:new{ width = default_option_padding })
    self[1] = vertical_group
    self.dimen = vertical_group:getSize()
end

local ConfigPanel = FrameContainer:new{ background = 0, bordersize = 0, }
function ConfigPanel:init()
    local config_options = self.config_dialog.config_options
    local default_option = config_options.default_options and config_options.default_options
                            or config_options[1].options
    local panel = ConfigOption:new{
        options = self.index and config_options[self.index].options or default_option,
        config = self.config_dialog,
    }
    self.dimen = panel:getSize()
    table.insert(self, panel)
end

local MenuBar = FrameContainer:new{ background = 0, }
function MenuBar:init()
    local config_options = self.config_dialog.config_options
    local menu_items = {}
    local icons_width = 0
    local icons_height = 0
    for c = 1, #config_options do
        local menu_icon = ImageWidget:new{
            file = config_options[c].icon
        }
        local icon_dimen = menu_icon:getSize()
        icons_width = icons_width + icon_dimen.w
        icons_height = icon_dimen.h > icons_height and icon_dimen.h or icons_height

        menu_items[c] = MenuBarItem:new{
            menu_icon,
            index = c,
            config = self.config_dialog,
        }
    end

    local spacing = HorizontalSpan:new{
        width = (Screen:getWidth() - icons_width) / (#menu_items+1)
    }

    local menu_bar = HorizontalGroup:new{}

    for c = 1, #menu_items do
        table.insert(menu_bar, spacing)
        table.insert(menu_bar, menu_items[c])
    end
    table.insert(menu_bar, spacing)

    self.dimen = Geom:new{ w = Screen:getWidth(), h = icons_height}
    table.insert(self, menu_bar)
end

--[[
Widget that displays config menubar and config panel

 +----------------+
 |                |
 |                |
 |                |
 |                |
 |                |
 +----------------+
 |                |
 |  Config Panel  |
 |                |
 +----------------+
 |    Menu Bar    |
 +----------------+

--]]

local ConfigDialog = InputContainer:new{
    --is_borderless = false,
    panel_index = 1,
}

function ConfigDialog:init()
    ------------------------------------------
    -- start to set up widget layout ---------
    ------------------------------------------
    self.config_menubar = MenuBar:new{
        config_dialog = self,
    }
    self:update()
    ------------------------------------------
    -- start to set up input event callback --
    ------------------------------------------
    if Device:isTouchDevice() then
        self.ges_events.TapCloseMenu = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
    if Device:hasKeys() then
        -- set up keyboard events
        self.key_events.Close = { {"Back"}, doc = "close config menu" }
        -- we won't catch presses to "Right"
        self.key_events.FocusRight = nil
    end
    self.key_events.Select = { {"Press"}, doc = "select current menu item" }
end

function ConfigDialog:updateConfigPanel(index)

end

function ConfigDialog:update()
    self.config_panel = ConfigPanel:new{
        index = self.panel_index,
        config_dialog = self,
    }
    self.dialog_frame = FrameContainer:new{
        background = 0,
        VerticalGroup:new{
            self.config_panel,
            self.config_menubar,
        },
    }

    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        self.dialog_frame,
    }
end

function ConfigDialog:onShowConfigPanel(index)
    self.panel_index = index
    self:update()
    UIManager.repaint_all = true
    return true
end

function ConfigDialog:onConfigChoice(option_name, option_value)
    --DEBUG("config option value", option_name, option_value)
    self.configurable[option_name] = option_value
    self.ui:handleEvent(Event:new("StartActivityIndicator"))
    return true
end

function ConfigDialog:onConfigEvent(option_event, option_arg)
    --DEBUG("config option event", option_event, option_arg)
    self.ui:handleEvent(Event:new(option_event, option_arg))
    return true
end

function ConfigDialog:onConfigEvents(option_events, arg_index)
    --DEBUG("config option events", option_events, arg_index)
    for i=1, #option_events do
        option_events[i].args = option_events[i].args or {}
        self.ui:handleEvent(Event:new(option_events[i].event, option_events[i].args[arg_index]))
    end
    return true
end

function ConfigDialog:onConfigChoose(values, name, event, args, events, position)
    UIManager:scheduleIn(0.05, function()
        if values then
            self:onConfigChoice(name, values[position])
        end
        if event then
            args = args or {}
            self:onConfigEvent(event, args[position])
        end
        if events then
            self:onConfigEvents(events, position)
        end
        UIManager.repaint_all = true
    end)
end

function ConfigDialog:closeDialog()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function ConfigDialog:onTapCloseMenu(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dialog_frame.dimen) then
        self:closeDialog()
        return true
    end
end

function ConfigDialog:onClose()
    self:closeDialog()
    return true
end

return ConfigDialog
