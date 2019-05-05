local Button = require("ui/widget/button")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local FixedTextWidget = require("ui/widget/fixedtextwidget")
local FocusManager = require("ui/widget/focusmanager")
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
local dump = require("dump")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local OptionTextItem = InputContainer:new{}

function OptionTextItem:init()
    local text_widget = self[1]

    self.underline_container = UnderlineContainer:new{
        text_widget,
        padding = self.underline_padding, -- vertical padding between text and underline
        color = self.color,
    }
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = self.padding_left,
        padding_right = self.padding_right,
        bordersize = 0,
        self.underline_container,
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
    end
end

function OptionTextItem:onFocus()
    self.underline_container.color = Blitbuffer.COLOR_BLACK
end

function OptionTextItem:onUnfocus()
    self.underline_container.color = Blitbuffer.COLOR_WHITE
end

function OptionTextItem:onTapSelect()
    if not self.enabled then return true end
    for _, item in pairs(self.items) do
        item.underline_container.color = Blitbuffer.COLOR_WHITE
    end
    self.underline_container.color = Blitbuffer.COLOR_BLACK
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.events, self.current_item)
    UIManager:setDirty(self.config, function()
        return "fast", self[1].dimen
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
    self.underline_container = UnderlineContainer:new{
        self.icon,
        padding = self.underline_padding,
        color = self.color,
    }
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = self.padding_left,
        padding_right = self.padding_right,
        bordersize = 0,
        self.underline_container,
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
    end
end

function OptionIconItem:onFocus()
    self.icon.invert = true
end

function OptionIconItem:onUnfocus()
    self.icon.invert = false
end

function OptionIconItem:onTapSelect()
    if not self.enabled then return true end
    for _, item in pairs(self.items) do
        --item[1][1].invert = false
        item.underline_container.color = Blitbuffer.COLOR_WHITE
    end
    --self[1][1].invert = true
    self.underline_container.color = Blitbuffer.COLOR_BLACK
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.events, self.current_item)
    UIManager:setDirty(self.config, function()
        return "fast", self[1].dimen
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
    local default_item_font_size = 16 -- font size for letters, toggles and buttonprogress
    local default_items_spacing = 40  -- spacing between letters (font sizes) and icons
    local default_option_height = 50  -- height of each line
    -- The next ones are already scaleBySize()'d:
    local default_option_vpadding = Size.padding.large -- vertical padding at top and bottom
    local default_option_hpadding = Size.padding.fullscreen
        -- horizontal padding at left and right, and between name and option items
    local padding_small = Size.padding.small   -- internal padding for options names (left)
    local padding_button = Size.padding.button -- padding for underline below letters and icons

    -- @TODO restore setting when there are more advanced settings
    --local show_advanced = G_reader_settings:readSetting("show_advanced") or false
    local show_advanced = true

    -- Get the width needed by the longest option name shown on the left
    local max_option_name_width = 0
    for c = 1, #self.options do
        -- Ignore names of options that won't be shown
        local show_default = not self.options[c].advanced or show_advanced
        if self.options[c].show ~= false and show_default then
            local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "cfont"
            local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
            local text = self.options[c].name_text
            local face = Font:getFace(name_font_face, name_font_size)
            local txt_width = 0
            if text ~= nil then
                txt_width = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text).x
            end
            max_option_name_width = math.max(max_option_name_width, txt_width)
        end
    end
    -- Have option names take min 25% and max 50% of screen width
    -- They will carry the left default_option_hpadding, but the in-between
    -- one (and the right one) will be carried by the option items.
    -- (Both these variables are between 0 and 1 and represent a % of screen width)
    local default_name_align_right = (max_option_name_width + default_option_hpadding + 2*padding_small) / Screen:getWidth()
    default_name_align_right = math.max(default_name_align_right, 0.25)
    default_name_align_right = math.min(default_name_align_right, 0.5)
    local default_item_align_center = 1 - default_name_align_right

    -- fill vertical group of config tab
    local vertical_group = VerticalGroup:new{}
    table.insert(vertical_group, VerticalSpan:new{
        width = default_option_vpadding,
    })

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

            -- Deal with the name on the left
            if self.options[c].name_text then
                -- the horizontal padding on the left will be ensured by the RightContainer
                local name_widget_width = math.floor(name_align * Screen:getWidth())
                local name_text_max_width = name_widget_width - default_option_hpadding - 2*padding_small
                local text = self.options[c].name_text
                local face = Font:getFace(name_font_face, name_font_size)
                local width_name_text = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text).x
                if width_name_text > name_text_max_width then
                    text = RenderText:truncateTextByWidth(text, face, name_text_max_width)
                end

                local option_name_container = RightContainer:new{
                    dimen = Geom:new{ w = name_widget_width, h = option_height},
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
                    hold_callback = function()
                        if self.options[c].name_text_hold_callback then
                            self.options[c].name_text_hold_callback(self.config.configurable, self.options[c],
                                self.config.config_options.prefix)
                        end
                    end,
                }
                table.insert(option_name_container, option_name)
                table.insert(horizontal_group, option_name_container)
            end

            -- Deal with the option widget on the right
            -- The horizontal padding between name and this option widget, and
            -- the one on the right, are ensured by this CenterContainer
            local option_widget_outer_width = math.floor(item_align * Screen:getWidth())
            local option_widget_width = option_widget_outer_width - 2*default_option_hpadding
            local option_items_container = CenterContainer:new{
                dimen = Geom:new{
                    w = option_widget_outer_width,
                    h = option_height
                }
            }
            local option_items_group = HorizontalGroup:new{}
            local option_items_fixed = false
            local option_items = {}
            if type(self.options[c].item_font_size) == "table" then
                option_items_group.align = "bottom"
                option_items_fixed = true
            end

            -- Find out currently selected and default items indexes
            local current_item = nil
            local default_item = self.options[c].default_pos
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
                local default_option_name = self.config.config_options.prefix.."_"..self.options[c].name
                local default_value = G_reader_settings:readSetting(default_option_name)
                if default_value and self.options[c].values then
                    local val = default_value
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
                            default_item = index
                            break
                        end
                        if diff <= min_diff then
                            min_diff = diff
                            default_item = index
                        end
                    end
                end
            end

            -- Deal with the various kind of config widgets

            -- Plain letters (ex: font sizes)
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
                local max_item_spacing = (option_widget_width - items_width) / items_count
                local width = math.min(max_item_spacing, item_spacing_width)
                if max_item_spacing < item_spacing_width / 2 then
                    width = item_spacing_width / 2
                end
                local horizontal_half_padding = width / 2
                local max_item_text_width = (option_widget_width - items_count * width) / items_count
                for d = 1, #self.options[c].item_text do
                    local option_item
                    if option_items_fixed then
                        option_item = OptionTextItem:new{
                            FixedTextWidget:new{
                                text = self.options[c].item_text[d],
                                face = Font:getFace(item_font_face, item_font_size[d]),
                                fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                            },
                            underline_padding = padding_button,
                            padding_left = d > 1 and horizontal_half_padding,
                            padding_right = d < #self.options[c].item_text and horizontal_half_padding,
                            color = d == current_item and (enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY) or Blitbuffer.COLOR_WHITE,
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
                                fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                            },
                            underline_padding = -padding_button,
                            padding_left = d > 1 and horizontal_half_padding,
                            padding_right = d < #self.options[c].item_text and horizontal_half_padding,
                            color = d == current_item and (enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY) or Blitbuffer.COLOR_WHITE,
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
                end
            end

            -- Icons (ex: columns, text align, with PDF)
            if self.options[c].item_icons then
                local items_count = #self.options[c].item_icons
                local first_item = OptionIconItem:new{
                    icon = ImageWidget:new{
                        file = self.options[c].item_icons[1]
                    }
                }
                local max_item_spacing = (option_widget_width -
                        first_item:getSize().w * items_count) / items_count
                local horizontal_half_padding = math.min(max_item_spacing, item_spacing_width) / 2
                for d = 1, #self.options[c].item_icons do
                    local option_item = OptionIconItem:new{
                        icon = ImageWidget:new{
                            file = self.options[c].item_icons[d],
                            dim = not enabled,
                        },
                        underline_padding = -padding_button,
                        padding_left = d > 1 and horizontal_half_padding,
                        padding_right = d < #self.options[c].item_icons and horizontal_half_padding,
                        color = d == current_item and (enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY) or Blitbuffer.COLOR_WHITE,
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
                end
            end

            -- Toggles (ex: mostly everything else)
            if self.options[c].toggle then
                local max_toggle_width = option_widget_width
                local toggle_width = self.options[c].width and Screen:scaleBySize(self.options[c].width)
                                        or max_toggle_width
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
                    delay_repaint = self.options[c].delay_repaint,
                    config = self.config,
                    enabled = enabled,
                    row_count = row_count,
                }
                local position = current_item
                switch:setPosition(position)
                table.insert(option_items_group, switch)
            end

            -- Progress bar (ex: contrast)
            if self.options[c].buttonprogress then
                local max_buttonprogress_width = option_widget_width
                local buttonprogress_width = self.options[c].width and Screen:scaleBySize(self.options[c].width)
                                                or max_buttonprogress_width
                local switch
                switch = ButtonProgressWidget:new{
                    width = math.min(max_buttonprogress_width, buttonprogress_width),
                    height = option_height,
                    padding = 0,
                    thin_grey_style = true,
                    font_face = item_font_face,
                    font_size = item_font_size,
                    num_buttons = #self.options[c].values,
                    position = self.options[c].default_pos,
                    callback = function(arg)
                        if arg == "-" or arg == "+" then
                            self.config:onConfigFineTuneChoose(self.options[c].values, self.options[c].name,
                                self.options[c].event, self.options[c].args, self.options[c].events, arg, self.options[c].delay_repaint)
                        else
                            self.config:onConfigChoose(self.options[c].values, self.options[c].name,
                                self.options[c].event, self.options[c].args, self.options[c].events, arg, self.options[c].delay_repaint)
                        end
                        UIManager:setDirty(self.config, function()
                            return "fast", switch.dimen
                        end)
                    end,
                    hold_callback = function(arg)
                        if arg == "-" or arg == "+" then
                            self.config:onMakeFineTuneDefault(self.options[c].name, self.options[c].name_text, self.options[c].values,
                                self.options[c].labels or self.options[c].args, arg)
                        else
                            self.config:onMakeDefault(self.options[c].name, self.options[c].name_text, self.options[c].values,
                                self.options[c].labels or self.options[c].args, arg)
                        end
                    end,
                    show_parrent = self.config,
                    enabled = enabled,
                    fine_tune = self.options[c].fine_tune,
                }
                switch:setPosition(current_item, default_item)
                table.insert(option_items_group, switch)
            end

            -- Add it to our CenterContainer
            table.insert(option_items_container, option_items_group)
            --add line of item to the second last place in the focusmanager so the menubar stay at the bottom
            table.insert(self.config.layout, #self.config.layout,self:_itemGroupToLayoutLine(option_items_group))
            table.insert(horizontal_group, option_items_container)
            table.insert(vertical_group, horizontal_group)
        end -- if self.options[c].show ~= false
    end -- for c = 1, #self.options

    table.insert(vertical_group, VerticalSpan:new{ width = default_option_vpadding })
    self[1] = vertical_group
    self.dimen = vertical_group:getSize()
end

function ConfigOption:_itemGroupToLayoutLine(option_items_group)
    local layout_line  = {}
    for k, v in pairs(option_items_group) do
        --pad the beginning of the line in the layout to align it with the current selected tab
        if type(k) == "number" then
            layout_line[k + self.config.panel_index-1] = v
        end
    end
    for k, v in pairs(layout_line) do
        --remove item_spacing (all widget have the name property)
        if not v.name then
            table.remove(layout_line,k)
        end
    end
    return layout_line
end

local ConfigPanel = FrameContainer:new{
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
}

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
    table.insert(self.config_dialog.layout,menu_items) --for the focusmanager
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

local ConfigDialog = FocusManager:new{
    --is_borderless = false,
    panel_index = 1,
    is_fresh = true,
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
    end
    if Device:hasDPad() then
        self.key_events.Select = { {"Press"}, doc = "select current menu item" }
    end
end

function ConfigDialog:updateConfigPanel(index)

end

function ConfigDialog:update()
    self.layout = {}
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
    -- Reset the focusmanager cursor
    self.selected.y=#self.layout
    self.selected.x=self.panel_index

    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        self.dialog_frame,
    }
end

function ConfigDialog:onCloseWidget()
    -- NOTE: As much as we would like to flash here, don't, because of adverse interactions with touchmenu that might lead to a double flash...
    UIManager:setDirty(nil, function()
        return "partial", self.dialog_frame.dimen
    end)
end

function ConfigDialog:onShowConfigPanel(index)
    self.panel_index = index
    local old_dimen = self.dialog_frame.dimen and self.dialog_frame.dimen:copy()
    self:update()
    -- NOTE: Keep that one as UI to avoid delay when both this and the topmenu are shown.
    --       Plus, this is also called for each tab anyway, so that wouldn't have been great.
    UIManager:setDirty(self.is_fresh and self or "all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dialog_frame.dimen)
            or self.dialog_frame.dimen
        self.is_fresh = false
        return "ui", refresh_dimen
    end)
    return true
end

function ConfigDialog:onConfigChoice(option_name, option_value)
    self.configurable[option_name] = option_value
    self.ui:handleEvent(Event:new("StartActivityIndicator"))
    return true
end

function ConfigDialog:onConfigEvent(option_event, option_arg, refresh_callback)
    self.ui:handleEvent(Event:new(option_event, option_arg, refresh_callback))
    return true
end

function ConfigDialog:onConfigEvents(option_events, arg_index)
    for i=1, #option_events do
        option_events[i].args = option_events[i].args or {}
        self.ui:handleEvent(Event:new(option_events[i].event, option_events[i].args[arg_index]))
    end
    return true
end

function ConfigDialog:onConfigChoose(values, name, event, args, events, position, delay_repaint)
    UIManager:tickAfterNext(function()
        -- Repainting may be delayed depending on options
        local refresh_dialog_func = function()
            self.skip_paint = nil
            if self.config_options.needs_redraw_on_change then
                -- Some Kopt document event handlers just save their setting,
                -- and need a full repaint for kopt to load these settings,
                -- notice the change, and redraw the document
                UIManager:setDirty("all", "partial")
            else
                -- CreDocument event handlers do their own refresh:
                -- we can just redraw our frame
                UIManager:setDirty(self, function()
                    return "ui", self.dialog_frame.dimen
                end)
            end
        end
        local refresh_callback = nil
        if type(delay_repaint) == "number" then -- timeout
            UIManager:scheduleIn(delay_repaint, refresh_dialog_func)
            self.skip_paint = true
        elseif delay_repaint then -- anything but nil or false: provide a callback
            -- This needs the config option to have an "event" key
            -- The event handler is responsible for calling this callback when
            -- it considers it appropriate
            refresh_callback = refresh_dialog_func
            self.skip_paint = true
        end
        if values then
            self:onConfigChoice(name, values[position])
        end
        if event then
            args = args or {}
            self:onConfigEvent(event, args[position], refresh_callback)
        end
        if events then
            self:onConfigEvents(events, position)
        end
        -- Even if each toggle refreshes itself when toggled, we still
        -- need to update and repaint the whole config panel, as other
        -- toggles may have their state (enabled/disabled) modified
        -- after this toggle update.
        self:update()
        if not delay_repaint then -- immediate refresh
            refresh_dialog_func()
        end
    end)
end

-- Tweaked variant used with the fine_tune variant of buttonprogress (direction can only be "-" or "+")
function ConfigDialog:onConfigFineTuneChoose(values, name, event, args, events, direction, delay_repaint)
    UIManager:tickAfterNext(function()
        -- Repainting may be delayed depending on options
        local refresh_dialog_func = function()
            self.skip_paint = nil
            if self.config_options.needs_redraw_on_change then
                -- Some Kopt document event handlers just save their setting,
                -- and need a full repaint for kopt to load these settings,
                -- notice the change, and redraw the document
                UIManager:setDirty("all", "partial")
            else
                -- CreDocument event handlers do their own refresh:
                -- we can just redraw our frame
                UIManager:setDirty(self, function()
                    return "ui", self.dialog_frame.dimen
                end)
            end
        end
        local refresh_callback = nil
        if type(delay_repaint) == "number" then -- timeout
            UIManager:scheduleIn(delay_repaint, refresh_dialog_func)
            self.skip_paint = true
        elseif delay_repaint then -- anything but nil or false: provide a callback
            -- This needs the config option to have an "event" key
            -- The event handler is responsible for calling this callback when
            -- it considers it appropriate
            refresh_callback = refresh_dialog_func
            self.skip_paint = true
        end
        if values then
            local value
            if direction == "-" then
                value = self.configurable[name] or values[1]
                value = value - 1
                if value < 0 then
                    value = 0
                end
            else
                value = self.configurable[name] or values[#values]
                value = value + 1
            end
            self:onConfigChoice(name, value)
        end
        if event then
            args = args or {}
            local arg
            if direction == "-" then
                arg = self.configurable[name] or args[1]
                if not values then
                    arg = arg - 1
                    if arg < 0 then
                        arg = 0
                    end
                end
            else
                arg = self.configurable[name] or args[#args]
                if not values then
                    arg = arg + 1
                end
            end
            self:onConfigEvent(event, arg, refresh_callback)
        end
        if events then
            self:onConfigEvents(events, direction)
        end
        -- Even if each toggle refreshes itself when toggled, we still
        -- need to update and repaint the whole config panel, as other
        -- toggles may have their state (enabled/disabled) modified
        -- after this toggle update.
        self:update()
        if not delay_repaint then -- immediate refresh
            refresh_dialog_func()
        end
    end)
end

function ConfigDialog:onMakeDefault(name, name_text, values, labels, position)
    local display_value = labels[position]
    if name == "font_fine_tune" then
        return
    -- known table value, make it pretty
    elseif name == "h_page_margins" then
        display_value = T(_([[

  left:  %1
  right: %2
]]),
        display_value[1], display_value[2])
    end
    -- generic fallback to support table values
    if type(display_value) == "table" then
        display_value = dump(display_value)
    end

    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default %1 to %2?"),
            (name_text or ""),
            display_value
        ),
        ok_text = T(_("Set default")),
        ok_callback = function()
            name = self.config_options.prefix.."_"..name
            G_reader_settings:saveSetting(name, values[position])
            self:update()
            UIManager:setDirty(self, function()
                return "ui", self.dialog_frame.dimen
            end)
        end,
    })
end

-- Tweaked variant used with the fine_tune variant of buttonprogress (direction can only be "-" or "+")
-- NOTE: This sets the defaults to the *current* value, as the -/+ buttons have no fixed value ;).
function ConfigDialog:onMakeFineTuneDefault(name, name_text, values, labels, direction)
    local display_value = self.configurable[name] or direction == "-" and labels[1] or labels[#labels]

    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default %1 to %2?"),
            (name_text or ""),
            display_value
        ),
        ok_text = T(_("Set default")),
        ok_callback = function()
            name = self.config_options.prefix.."_"..name
            G_reader_settings:saveSetting(name, self.configurable[name])
            self:update()
            UIManager:setDirty(self, function()
                return "ui", self.dialog_frame.dimen
            end)
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

function ConfigDialog:onSelect()
    self:getFocusItem():handleEvent(Event:new("TapSelect"))
    return true
end

return ConfigDialog
