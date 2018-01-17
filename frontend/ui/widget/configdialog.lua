local Button = require("ui/widget/button")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local FixedTextWidget = require("ui/widget/fixedtextwidget")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

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
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Option Item",
            },
        }
    else
        self.active_key_events = {
            Select = { {"Press"}, doc = "chose selected item" },
        }
    end
end

function OptionTextItem:onTapSelect()
    if not self.enabled then return true end
    for _, item in pairs(self.items) do
        item[1].color = Blitbuffer.COLOR_WHITE
    end
    self[1].color = Blitbuffer.COLOR_BLACK
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.events, self.current_item)
    UIManager:setDirty(self.config, function()
        return "ui", self[1].dimen
    end)
    return true
end

function OptionTextItem:onHoldSelect()
    self.config:onMakeDefault(self.name, self.name_text,
                    self.values or self.args,
                    self.values or self.item_text,
                    self.current_item)
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
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Option Item",
            },

        }
    end
end

function OptionIconItem:onTapSelect()
    if not self.enabled then return true end
    for _, item in pairs(self.items) do
        --item[1][1].invert = false
        item[1].color = Blitbuffer.COLOR_WHITE
    end
    --self[1][1].invert = true
    self[1].color = Blitbuffer.COLOR_BLACK
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.events, self.current_item)
    UIManager:setDirty(self.config, function()
        return "ui", self[1].dimen
    end)
    return true
end

function OptionIconItem:onHoldSelect()
    self.config:onMakeDefault(self.name, self.name_text,
                    self.values, self.values, self.current_item)
    return true
end

local ConfigOption = CenterContainer:new{}
function ConfigOption:init()
    -- make default styles
    local default_name_font_size = 20
    local default_item_font_size = 16
    local default_items_spacing = 40
    local default_option_height = 50
    local default_option_padding = Size.padding.large
    local max_option_name_width = 0
    local txt_width = 0
    local padding_small = Size.padding.small
    local padding_button = Size.padding.button
    for c = 1, #self.options do
        local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "cfont"
        local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
        local text = self.options[c].name_text
        local face = Font:getFace(name_font_face, name_font_size)
        if text ~= nil then
            txt_width = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text).x
        end
        max_option_name_width = math.max(max_option_name_width, txt_width)
    end
    local default_name_align_right = math.max((max_option_name_width + Screen:scaleBySize(10))/Screen:getWidth(), 0.33)
    default_name_align_right = math.min(default_name_align_right, 0.5)
    local default_item_align_center = 1 - default_name_align_right

    -- fill vertical group of config tab
    local vertical_group = VerticalGroup:new{}
    table.insert(vertical_group, VerticalSpan:new{
        width = default_option_padding,
    })
    -- @TODO restore setting when there are more advanced settings
    --local show_advanced = G_reader_settings:readSetting("show_advanced") or false
    local show_advanced = true
    for c = 1, #self.options do
        local show_default = not self.options[c].advanced or show_advanced
        if self.options[c].show ~= false and show_default then
            local name_align = self.options[c].name_align_right and self.options[c].name_align_right or default_name_align_right
            local item_align = self.options[c].item_align_center and self.options[c].item_align_center or default_item_align_center
            local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "cfont"
            local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
            local item_font_face = self.options[c].item_font_face and self.options[c].item_font_face or "cfont"
            local item_font_size = self.options[c].item_font_size and self.options[c].item_font_size or default_item_font_size
            local option_height = Screen:scaleBySize(self.options[c].height and self.options[c].height or
                    default_option_height + (self.options[c].height or 30) * ((self.options[c].row_count or 1) -1))
            local item_spacing_width = Screen:scaleBySize(self.options[c].spacing and self.options[c].spacing or default_items_spacing)
            local enabled = true
            if item_align == 1.0 then
                name_align = 0
            end
            if name_align + item_align > 1 then
                name_align = 0.5
                item_align = 0.5
            end
            if self.options[c].enabled_func then
                enabled = self.options[c].enabled_func(self.config.configurable)
            end
            local horizontal_group = HorizontalGroup:new{}
            if self.options[c].name_text then
                local text = self.options[c].name_text
                local face = Font:getFace(name_font_face, name_font_size)
                local width_name_text = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text).x
                if math.floor(name_align * Screen:getWidth()) - 2*padding_small < width_name_text then
                    text = RenderText:truncateTextByWidth(text, face, name_align * Screen:getWidth() - 2*padding_small)
                end

                local option_name_container = RightContainer:new{
                    dimen = Geom:new{ w = Screen:getWidth()*name_align, h = option_height},
                }
                local option_name = Button:new{
                    text = text,
                    bordersize = 0,
                    face = face,
                    enabled = enabled,
                    padding = padding_small,
                    text_font_face = name_font_face,
                    text_font_size = name_font_size,
                    text_font_bold = false,
                    hold_callback = self.options[c].name_text_hold_callback,
                }
                table.insert(option_name_container, option_name)
                table.insert(horizontal_group, option_name_container)
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
                    logger.dbg("different data types in option")
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
                    local min_diff
                    if type(val) == "table" then
                        min_diff = value_diff(val[1], self.options[c].values[1][1])
                    else
                        min_diff = value_diff(val, self.options[c].values[1])
                    end

                    local diff
                    for index, val_ in pairs(self.options[c].values) do
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
                local items_width = 0
                for d = 1, #self.options[c].item_text do
                    local item = OptionTextItem:new{
                        TextWidget:new{
                            text = self.options[c].item_text[d],
                            face = Font:getFace(item_font_face,
                            option_items_fixed and item_font_size[d]
                            or item_font_size),
                        }
                    }
                    items_width = items_width + item:getSize().w
                end
                local max_item_spacing = (Screen:getWidth() * item_align - items_width) / items_count
                local width = math.min(max_item_spacing, item_spacing_width)

                if max_item_spacing < item_spacing_width / 2 then
                    width = item_spacing_width / 2
                end
                local items_spacing = HorizontalSpan:new{
                    width = width
                }
                local max_item_text_width = (Screen:getWidth() * item_align - items_count * width) / items_count
                for d = 1, #self.options[c].item_text do
                    local option_item
                    if option_items_fixed then
                        option_item = OptionTextItem:new{
                            FixedTextWidget:new{
                                text = self.options[c].item_text[d],
                                face = Font:getFace(item_font_face, item_font_size[d]),
                                fgcolor = Blitbuffer.gray(enabled and 1.0 or 0.5),
                            },
                            padding = padding_button,
                            color = d == current_item and Blitbuffer.gray(enabled and 1.0 or 0.5) or Blitbuffer.COLOR_WHITE,
                            enabled = enabled,
                        }
                    else
                        local text = self.options[c].item_text[d]
                        local face = Font:getFace(item_font_face, item_font_size)
                        local width_item_text = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text).x
                        if max_item_text_width < width_item_text then
                            text = RenderText:truncateTextByWidth(text, face, max_item_text_width)
                        end
                        option_item = OptionTextItem:new{
                            TextWidget:new{
                                text = text,
                                face = face,
                                fgcolor = Blitbuffer.gray(enabled and 1.0 or 0.5),
                            },
                            padding = -padding_button,
                            color = d == current_item and Blitbuffer.gray(enabled and 1.0 or 0.5) or Blitbuffer.COLOR_WHITE,
                            enabled = enabled,
                        }
                    end
                    option_items[d] = option_item
                    option_item.items = option_items
                    option_item.name = self.options[c].name
                    option_item.name_text = self.options[c].name_text
                    option_item.item_text = self.options[c].item_text
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
                    width = math.min(max_item_spacing, item_spacing_width)
                }
                for d = 1, #self.options[c].item_icons do
                    local option_item = OptionIconItem:new{
                        icon = ImageWidget:new{
                            file = self.options[c].item_icons[d],
                            dim = not enabled,
                        },
                        padding = -padding_button,
                        color = d == current_item and Blitbuffer.gray(enabled and 1.0 or 0.5) or Blitbuffer.COLOR_WHITE,
                        enabled = enabled,
                    }
                    option_items[d] = option_item
                    option_item.items = option_items
                    option_item.name = self.options[c].name
                    option_item.name_text = self.options[c].name_text
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
                local max_toggle_width = Screen:getWidth() * item_align * 0.85
                local toggle_width = Screen:scaleBySize(self.options[c].width or max_toggle_width)
                local row_count = self.options[c].row_count or 1
                local toggle_height = Screen:scaleBySize(self.options[c].height
                                                         or 30 * row_count)
                local switch = ToggleSwitch:new{
                    width = math.min(max_toggle_width, toggle_width),
                    height = toggle_height,
                    font_face = item_font_face,
                    font_size = item_font_size,
                    name = self.options[c].name,
                    name_text = self.options[c].name_text,
                    toggle = self.options[c].toggle,
                    alternate = self.options[c].alternate,
                    values = self.options[c].values,
                    args = self.options[c].args,
                    event = self.options[c].event,
                    events = self.options[c].events,
                    config = self.config,
                    enabled = enabled,
                    row_count = row_count,
                }
                local position = current_item
                switch:setPosition(position)
                table.insert(option_items_group, switch)
            end

            if self.options[c].buttonprogress then
                local max_buttonprogress_width = Screen:getWidth() * item_align * 0.85
                local buttonprogress_width = Screen:scaleBySize(self.options[c].width or max_buttonprogress_width)
                local switch = ButtonProgressWidget:new{
                    width = math.min(max_buttonprogress_width, buttonprogress_width),
                    height = option_height,
                    font_face = item_font_face,
                    font_size = item_font_size,
                    num_buttons = #self.options[c].values,
                    position = self.options[c].default_pos,
                    callback = function(arg)
                        UIManager:scheduleIn(0.05, function()
                            self.config:onConfigChoice(self.options[c].name, self.options[c].values[arg])
                            self.config:onConfigEvent(self.options[c].event, self.options[c].args[arg])
                            UIManager:setDirty("all")
                        end)
                    end,
                    hold_callback = function(arg)
                        self.config:onMakeDefault(self.options[c].name, self.options[c].name_text, self.options[c].values,
                            self.options[c].args, arg)
                    end,
                    show_parrent = self.config,
                    enabled = enabled,
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

local ConfigPanel = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, }
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

local MenuBar = FrameContainer:new{
    bordersize = 0,
    padding = 0,
    background = Blitbuffer.COLOR_WHITE,
}
function MenuBar:init()
    local icon_sep_width = Size.padding.button
    local line_thickness = Size.line.thick
    local config_options = self.config_dialog.config_options
    local menu_items = {}
    local icon_width = Screen:scaleBySize(40)
    local icon_height = icon_width
    local icons_width = (icon_width + 2*icon_sep_width) * #config_options
    local icons_height = icon_height
    for c = 1, #config_options do
        local menu_icon = IconButton:new{
            show_parent = self.config_dialog,
            icon_file = config_options[c].icon,
            width = icon_width,
            height = icon_height,
            scale_for_dpi = false,
            callback = function()
                self.config_dialog:handleEvent(Event:new("ShowConfigPanel", c))
            end,
        }
        menu_items[c] = menu_icon
    end

    local available_width = Screen:getWidth() - icons_width
    -- local padding = math.floor(available_width / #menu_items / 2) -- all for padding
    -- local padding = math.floor(available_width / #menu_items / 2 / 2) -- half padding, half spacing ?
    local padding = math.min(math.floor(available_width / #menu_items / 2), Screen:scaleBySize(20)) -- as in TouchMenuBar
    if padding > 0 then
        for c = 1, #menu_items do
            menu_items[c].padding_left = padding
            menu_items[c].padding_right = padding
            menu_items[c]:update()
        end
        available_width = available_width - 2*padding*#menu_items
    end
    local spacing_width = math.ceil(available_width / (#menu_items+1))

    local icon_sep_black = LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{
            w = icon_sep_width,
            h = icons_height,
        }
    }
    local icon_sep_white = LineWidget:new{
        background = Blitbuffer.COLOR_WHITE,
        dimen = Geom:new{
            w = icon_sep_width,
            h = icons_height,
        }
    }
    local spacing = HorizontalSpan:new{
        width = spacing_width,
    }
    local spacing_line = LineWidget:new{
        dimen = Geom:new{
            w = spacing_width,
            h = line_thickness,
        }
    }
    local sep_line = LineWidget:new{
        dimen = Geom:new{
            w = icon_sep_width,
            h = line_thickness,
        }
    }
    local menu_bar = HorizontalGroup:new{}
    local line_bar = HorizontalGroup:new{}

    for c = 1, #menu_items do
        table.insert(menu_bar, spacing)
        table.insert(line_bar, spacing_line)
        if c == self.panel_index then
            table.insert(menu_bar, icon_sep_black)
            table.insert(line_bar, sep_line)
            table.insert(menu_bar, menu_items[c])
            table.insert(line_bar, LineWidget:new{
                background = Blitbuffer.COLOR_WHITE,
                dimen = Geom:new{
                    w = menu_items[c]:getSize().w,
                    h = line_thickness,
                }
            })
            table.insert(menu_bar, icon_sep_black)
            table.insert(line_bar, sep_line)
        else
            table.insert(menu_bar, icon_sep_white)
            table.insert(line_bar, sep_line)
            table.insert(menu_bar, menu_items[c])
            table.insert(line_bar, LineWidget:new{
                dimen = Geom:new{
                    w = menu_items[c]:getSize().w,
                    h = line_thickness,
                }
            })
            table.insert(menu_bar, icon_sep_white)
            table.insert(line_bar, sep_line)
        end
    end
    table.insert(menu_bar, spacing)
    table.insert(line_bar, spacing_line)

    self.dimen = Geom:new{ w = Screen:getWidth(), h = icons_height}
    local vertical_menu = VerticalGroup:new{
        line_bar,
        menu_bar,
    }
    table.insert(self, vertical_menu)

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
        self.ges_events.SwipeCloseMenu = {
            GestureRange:new{
                ges = "swipe",
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
    self.config_menubar = MenuBar:new{
        config_dialog = self,
        panel_index = self.panel_index,
    }
    self.config_panel = ConfigPanel:new{
        index = self.panel_index,
        config_dialog = self,
    }
    self.dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
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

function ConfigDialog:onCloseWidget()
    UIManager:setDirty("all", function()
        return "partial", self.dialog_frame.dimen
    end)
end

function ConfigDialog:onShowConfigPanel(index)
    self.panel_index = index
    local old_dimen = self.dialog_frame.dimen and self.dialog_frame.dimen:copy()
    self:update()
    UIManager:setDirty("all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dialog_frame.dimen)
            or self.dialog_frame.dimen
        return "ui", refresh_dimen
    end)
    return true
end

function ConfigDialog:onConfigChoice(option_name, option_value)
    self.configurable[option_name] = option_value
    self.ui:handleEvent(Event:new("StartActivityIndicator"))
    return true
end

function ConfigDialog:onConfigEvent(option_event, option_arg)
    self.ui:handleEvent(Event:new(option_event, option_arg))
    return true
end

function ConfigDialog:onConfigEvents(option_events, arg_index)
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
        self:update()
        UIManager:setDirty("all")
    end)
end

function ConfigDialog:onMakeDefault(name, name_text, values, labels, position)
    if name == "font_fine_tune" then
        return
    end

    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default %1 to %2?"),
            (name_text or ""),
            labels[position]
        ),
        ok_text = T(_("Set default")),
        ok_callback = function()
            name = self.config_options.prefix.."_"..name
            G_reader_settings:saveSetting(name, values[position])
        end,
    })
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

function ConfigDialog:onSwipeCloseMenu(arg, ges_ev)
    local range = {
        x = DTAP_ZONE_CONFIG.x * Screen:getWidth(),
        y = DTAP_ZONE_CONFIG.y * Screen:getHeight(),
        w = DTAP_ZONE_CONFIG.w * Screen:getWidth(),
        h = DTAP_ZONE_CONFIG.h * Screen:getHeight(),
    }
    if ges_ev.direction == "south" and (ges_ev.pos:intersectWith(self.dialog_frame.dimen)
        or ges_ev.pos:intersectWith(range)) then
        self:closeDialog()
        return true
    end
end

function ConfigDialog:onClose()
    self:closeDialog()
    return true
end

return ConfigDialog
