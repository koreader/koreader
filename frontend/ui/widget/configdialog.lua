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
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local serpent = require("ffi/serpent")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local OptionTextItem = InputContainer:extend{}

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
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }
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

    Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_ICON)
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.current_item, self.hide_on_apply)

    UIManager:setDirty(self.config, function()
        return "fast", self[1].dimen
    end)

    UIManager:tickAfterNext(function()
        Notification:resetNotifySource()
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

local OptionIconItem = InputContainer:extend{}

function OptionIconItem:init()
    self.underline_container = UnderlineContainer:new{
        self.icon,
        padding = self.underline_padding,
        color = self.color,
    }
    self[1] = FrameContainer:new{
        padding = 0,
        padding_top = self.underline_padding,
        padding_left = self.padding_left,
        padding_right = self.padding_right,
        bordersize = 0,
        self.underline_container,
    }
    self.dimen = self[1]:getSize()
    -- we need this table per-instance, so we declare it here
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },

    }
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

    Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_ICON)
    self.config:onConfigChoose(self.values, self.name,
                    self.event, self.args,
                    self.current_item, self.hide_on_apply)

    UIManager:setDirty(self.config, function()
        return "fast", self[1].dimen
    end)

    UIManager:tickAfterNext(function()
        Notification:resetNotifySource()
    end)
    return true
end

function OptionIconItem:onHoldSelect()
    self.config:onMakeDefault(self.name, self.name_text,
                    self.values, self.labels or self.values, self.current_item)
    return true
end

local ConfigOption = CenterContainer:extend{}

function ConfigOption:init()
    -- make default styles
    local default_name_font_size = 20
    local default_item_font_size = 16 -- font size for letters, toggles and buttonprogress
    local default_items_spacing = 40  -- spacing between letters (font sizes) and icons
    local default_option_height = 50  -- height of each line
    local max_icon_height = Screen:scaleBySize(DGENERIC_ICON_SIZE)  -- max height of icons
    -- The next ones are already scaleBySize()'d:
    local default_option_vpadding = Size.padding.large -- vertical padding at top and bottom
    local default_option_hpadding = Size.padding.fullscreen
        -- horizontal padding at left and right, and between name and option items
    local padding_small = Size.padding.small   -- internal padding for options names (left)
    local padding_button = Size.padding.button -- padding for underline below letters and icons

    --- @todo Restore setting when there are more advanced settings.
    --local show_advanced = G_reader_settings:isTrue("show_advanced")
    local show_advanced = true

    -- Get the width needed by the longest option name shown on the left
    local max_option_name_width = 0
    for c = 1, #self.options do
        -- Ignore names of options that won't be shown
        local show_default = not self.options[c].advanced or show_advanced
        local show = self.options[c].show
        -- Prefer show_func over show if there's one
        -- Or may be not, as show_func is always used to show/hide some widget depending
        -- on the value of another widget: it's best to keep it accounted for the names
        -- max width, and avoid stuff moving when toggling options.
        --[[
        if self.options[c].show_func then
            show = self.options[c].show_func(self.config.configurable, self.config.document)
        end
        ]]--
        if show ~= false and show_default then
            local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "cfont"
            local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
            local text = self.options[c].name_text_func
                         and self.options[c].name_text_func(self.config.configurable, self.config.document)
                          or self.options[c].name_text
            local face = Font:getFace(name_font_face, name_font_size)
            local txt_width = 0
            if text ~= nil then
                local tmp = TextWidget:new{
                    text = text,
                    face = face,
                }
                txt_width = tmp:getWidth()
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
        local show = self.options[c].show
        -- Prefer show_func over show if there's one
        if self.options[c].show_func then
            show = self.options[c].show_func(self.config.configurable, self.config.document)
        end
        if show ~= false and show_default then
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
                enabled = self.options[c].enabled_func(self.config.configurable, self.config.document)
            end
            local horizontal_group = HorizontalGroup:new{}

            -- Deal with the name on the left
            local name_text = self.options[c].name_text_func
                              and self.options[c].name_text_func(self.config.configurable, self.config.document)
                               or self.options[c].name_text
            if name_text then
                -- the horizontal padding on the left will be ensured by the RightContainer
                local name_widget_width = math.floor(name_align * Screen:getWidth())
                -- We don't remove default_option_hpadding from name_text_max_width
                -- to give more to text and avoid truncation: as it is right aligned,
                -- the text can grow on the left.
                local name_text_max_width = name_widget_width
                local face = Font:getFace(name_font_face, name_font_size)
                local option_name_container = RightContainer:new{
                    dimen = Geom:new{ w = name_widget_width, h = option_height },
                }
                local option_name = Button:new{
                    text = name_text,
                    max_width = name_text_max_width,
                    bordersize = 0,
                    face = face,
                    enabled = enabled,
                    allow_hold_when_disabled = self.options[c].name_text_hold_callback ~= nil,
                    padding = padding_small,
                    text_font_face = name_font_face,
                    text_font_size = name_font_size,
                    text_font_bold = false,
                    hold_callback = function()
                        if self.options[c].name_text_hold_callback then
                            self.options[c].name_text_hold_callback(self.config.configurable, self.options[c],
                                self.config.config_options.prefix, self.config.document)
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
                logger.dbg("ConfigOption:init() from option", self.options[c].name)
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
                    -- If we want to have the ⋮ toggle selected when the value
                    -- is different from the predefined values:
                    -- if diff ~= 0 and self.options[c].alternate ~= false and self.options[c].more_options_param then
                    --     current_item = #self.options[c].values + 1
                    -- end
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
                        option_item = OptionTextItem:new{
                            TextWidget:new{
                                text = text,
                                max_width = max_item_text_width,
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
                    option_item.name_text = name_text or self.options[c].alt_name_text
                    option_item.item_text = self.options[c].item_text
                    option_item.values = self.options[c].values
                    option_item.args = self.options[c].args
                    option_item.event = self.options[c].event
                    option_item.current_item = d
                    option_item.hide_on_apply = self.options[c].hide_on_apply
                    option_item.config = self.config
                    option_item.document = self.document
                    table.insert(option_items_group, option_item)
                end
            end

            -- Icons (ex: columns, text align, with PDF)
            local item_icons = self.options[c].item_icons_func and
                               self.options[c].item_icons_func(self.config.configurable, self.config.document) or
                               self.options[c].item_icons
            if item_icons then
                local items_count = #item_icons
                local icon_max_height = math.min(option_height, max_icon_height)
                local icon_max_width = math.floor(option_widget_width / items_count)
                local icon_size = math.min(icon_max_height, icon_max_width)
                local max_item_spacing = (option_widget_width - icon_size * items_count) / items_count
                local horizontal_half_padding = math.min(max_item_spacing, item_spacing_width) / 2
                -- Our icons have a bottom padding that makes 10% to 20% of their height (5-9px in our 48px images)
                -- We don't want the underline to be that far away from the image content,
                -- so we use some negative padding to eat a bit on their padding.
                local underline_padding = - math.floor(0.05 * icon_size)
                for d = 1, items_count do
                    local option_item = OptionIconItem:new{
                        icon = IconWidget:new{
                            icon = item_icons[d],
                            dim = not enabled,
                            width = icon_size,
                            height = icon_size,
                        },
                        underline_padding = underline_padding,
                        padding_left = d > 1 and horizontal_half_padding,
                        padding_right = d < items_count and horizontal_half_padding,
                        color = d == current_item and (enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY) or Blitbuffer.COLOR_WHITE,
                        enabled = enabled,
                    }
                    option_items[d] = option_item
                    option_item.items = option_items
                    option_item.name = self.options[c].name
                    option_item.name_text = name_text or self.options[c].alt_name_text
                    option_item.values = self.options[c].values
                    option_item.labels = self.options[c].labels
                    option_item.args = self.options[c].args
                    option_item.event = self.options[c].event
                    option_item.current_item = d
                    option_item.hide_on_apply = self.options[c].hide_on_apply
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
                                                         or (30 * row_count))
                local toggle = {} -- keep options intact
                for i = 1, #self.options[c].toggle do
                    toggle[i] = self.options[c].toggle[i]
                end
                if self.options[c].more_options then
                    table.insert(toggle, "⋮")
                end
                local switch = ToggleSwitch:new{
                    width = math.min(max_toggle_width, toggle_width),
                    height = toggle_height,
                    font_face = item_font_face,
                    font_size = item_font_size,
                    name = self.options[c].name,
                    name_text = name_text,
                    toggle = toggle,
                    alternate = self.options[c].alternate,
                    values = self.options[c].values,
                    args = self.options[c].args,
                    event = self.options[c].event,
                    hide_on_apply = self.options[c].hide_on_apply,
                    config = self.config,
                    enabled = enabled,
                    row_count = row_count,
                    callback = function(arg)
                        if toggle[arg] == "⋮" then
                            if self.options[c].show_true_value_func and not self.options[c].more_options_param.show_true_value_func then
                                self.options[c].more_options_param.show_true_value_func = self.options[c].show_true_value_func
                            end
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_MORE)
                            local default_value_original
                            if self.options[c].more_options_param and self.options[c].more_options_param.names then
                                local option1 = self.config:findOptionByName(self.options[c].more_options_param.names[1])
                                local option2 = self.config:findOptionByName(self.options[c].more_options_param.names[2])
                                default_value_original = { option1.default_value, option2.default_value }
                            else
                                default_value_original = self.options[c].default_value
                            end
                            self.config:onConfigMoreChoose(self.options[c].values, default_value_original, self.options[c].name,
                                self.options[c].event, arg, name_text, self.options[c].more_options_param)
                            UIManager:tickAfterNext(function()
                                Notification:resetNotifySource()
                            end)
                        end
                    end
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
                    name = self.options[c].name,
                    num_buttons = #self.options[c].values,
                    position = self.options[c].default_pos,
                    callback = function(arg)
                        if arg == "-" or arg == "+" then
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_FINE)
                            self.config:onConfigFineTuneChoose(self.options[c].values, self.options[c].name,
                                self.options[c].event, self.options[c].args, arg, self.options[c].hide_on_apply,
                                self.options[c].fine_tune_param)
                        elseif arg == "⋮" then
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_MORE)
                            local default_value_original
                            if self.options[c].more_options_param and self.options[c].more_options_param.names then
                                local option1 = self.config:findOptionByName(self.options[c].more_options_param.names[1])
                                local option2 = self.config:findOptionByName(self.options[c].more_options_param.names[2])
                                default_value_original = { option1.default_value, option2.default_value }
                            else
                                default_value_original = self.options[c].default_value
                            end
                            self.config:onConfigMoreChoose(self.options[c].values, default_value_original, self.options[c].name,
                                self.options[c].event, arg, name_text, self.options[c].more_options_param)
                        else
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_PROGRESS)
                            self.config:onConfigChoose(self.options[c].values, self.options[c].name,
                                self.options[c].event, self.options[c].args, arg, self.options[c].hide_on_apply)
                        end

                        UIManager:setDirty(self.config, function()
                            return "fast", switch.dimen
                        end)
                        UIManager:tickAfterNext(function()
                            Notification:resetNotifySource()
                        end)
                    end,
                    hold_callback = function(arg)
                        if arg == "-" or arg == "+" then
                            self.config:onMakeFineTuneDefault(self.options[c].name, name_text, self.options[c].values,
                                self.options[c].labels or self.options[c].args, arg)
                        elseif arg ~= "⋮" then
                            self.config:onMakeDefault(self.options[c].name, name_text, self.options[c].values,
                                self.options[c].labels or self.options[c].args, arg)
                        end
                    end,
                    show_parent = self.config,
                    enabled = enabled,
                    fine_tune = self.options[c].fine_tune,
                    fine_tune_param = self.options[c].fine_tune_param,
                    more_options = self.options[c].more_options,
                    more_options_param = self.options[c].more_options_param,
                }
                switch:setPosition(current_item, default_item)
                table.insert(option_items_group, switch)
            end

            -- Add it to our CenterContainer
            table.insert(option_items_container, option_items_group)
            --add line of item to the second last place in the focusmanager so the menubar stay at the bottom
            table.insert(self.config.layout, #self.config.layout, self:_itemGroupToLayoutLine(option_items_group))
            table.insert(horizontal_group, option_items_container)
            table.insert(vertical_group, horizontal_group)
        end -- if show ~= false
    end -- for c = 1, #self.options

    table.insert(vertical_group, VerticalSpan:new{ width = default_option_vpadding })
    self[1] = vertical_group
    self.dimen = vertical_group:getSize()
end

function ConfigOption:_itemGroupToLayoutLine(option_items_group)
    local layout_line  = {}
    -- Insert items (skpping item_spacing without a .name attribute),
    local j = 1 -- no nil in row head
    for i, v in ipairs(option_items_group) do
        if v.name then
            if v.layout and v.disableFocusManagement then -- it is a FocusManager
                -- merge child layout to one row layout
                -- currently child widgets are all one row
                -- needs improvement if we ever implement widgets with two or more rows
                for _, row in ipairs(v.layout) do
                    for _, widget in ipairs(row) do
                        layout_line[j] = widget
                        j = j + 1
                    end
                end
                v:disableFocusManagement(self.config)
            else
                layout_line[j] = v
                j = j + 1
            end
        end
    end
    return layout_line
end

local ConfigPanel = FrameContainer:extend{
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
        document = self.document,
    }
    self.dimen = panel:getSize()
    table.insert(self, panel)
end

local MenuBar = FrameContainer:extend{
    bordersize = 0,
    padding = 0,
    background = Blitbuffer.COLOR_WHITE,
}

function MenuBar:init()
    local icon_sep_width = Size.padding.button
    local line_thickness = Size.line.thick
    local config_options = self.config_dialog.config_options
    local icon_width = Screen:scaleBySize(DGENERIC_ICON_SIZE)
    local icon_height = icon_width
    local icons_width = (icon_width + 2*icon_sep_width) * #config_options
    local bar_height = icon_height + 2*Size.padding.default
    if not self.menu_items then
        self.menu_items = {}
        for c = 1, #config_options do
            local menu_icon = IconButton:new{
                show_parent = self.config_dialog,
                icon = config_options[c].icon,
                width = icon_width,
                height = icon_height,
                callback = function()
                    self.config_dialog:handleEvent(Event:new("ShowConfigPanel", c))
                end,
            }
            self.menu_items[c] = menu_icon
        end
    end
    table.insert(self.config_dialog.layout, self.menu_items) -- for the focusmanager
    local available_width = Screen:getWidth() - icons_width
    -- local padding = math.floor(available_width / #self.menu_items / 2) -- all for padding
    -- local padding = math.floor(available_width / #self.menu_items / 2 / 2) -- half padding, half spacing ?
    local padding = math.min(math.floor(available_width / #self.menu_items / 2), Screen:scaleBySize(20)) -- as in TouchMenuBar
    if padding > 0 then
        for c = 1, #self.menu_items do
            self.menu_items[c].padding_left = padding
            self.menu_items[c].padding_right = padding
            self.menu_items[c]:update()
        end
        available_width = available_width - 2*padding*#self.menu_items
    end
    local spacing_width = math.ceil(available_width / (#self.menu_items+1))

    local icon_sep_black = LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{
            w = icon_sep_width,
            h = bar_height,
        }
    }
    local icon_sep_white = LineWidget:new{
        background = Blitbuffer.COLOR_WHITE,
        dimen = Geom:new{
            w = icon_sep_width,
            h = bar_height,
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

    for c = 1, #self.menu_items do
        table.insert(menu_bar, spacing)
        table.insert(line_bar, spacing_line)
        if c == self.panel_index then
            table.insert(menu_bar, icon_sep_black)
            table.insert(line_bar, sep_line)
            table.insert(menu_bar, self.menu_items[c])
            table.insert(line_bar, LineWidget:new{
                background = Blitbuffer.COLOR_WHITE,
                dimen = Geom:new{
                    w = self.menu_items[c]:getSize().w,
                    h = line_thickness,
                }
            })
            table.insert(menu_bar, icon_sep_black)
            table.insert(line_bar, sep_line)
        else
            table.insert(menu_bar, icon_sep_white)
            table.insert(line_bar, sep_line)
            table.insert(menu_bar, self.menu_items[c])
            table.insert(line_bar, LineWidget:new{
                dimen = Geom:new{
                    w = self.menu_items[c]:getSize().w,
                    h = line_thickness,
                }
            })
            table.insert(menu_bar, icon_sep_white)
            table.insert(line_bar, sep_line)
        end
    end
    table.insert(menu_bar, spacing)
    table.insert(line_bar, spacing_line)

    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = bar_height }
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

local ConfigDialog = FocusManager:extend{
    --is_borderless = false,
    name = "ConfigDialog",
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
    if Device:hasKeys() then
        -- set up keyboard events
        local back_group = util.tableDeepCopy(Device.input.group.Back)
        if Device:hasFewKeys() then
            table.insert(back_group, "Left")
            self.key_events.Close = { { back_group } }
        else
            table.insert(back_group, "Menu")
            table.insert(back_group, "AA")
            self.key_events.Close = { { back_group } }
        end
    end
end

function ConfigDialog:updateConfigPanel(index) end

function ConfigDialog:update()
    self:moveFocusTo(1, 1, FocusManager.NOT_FOCUS) -- reset selected for re-created layout
    self.layout = {}

    if self.config_menubar then
        self.config_menubar:clear()
        self.config_menubar.panel_index = self.panel_index
        self.config_menubar:init()
    else
        self.config_menubar = MenuBar:new{
            config_dialog = self,
            panel_index = self.panel_index,
        }
    end
    if self.config_panel then
        self.config_panel:free()
    end
    self.config_panel = ConfigPanel:new{
        index = self.panel_index,
        config_dialog = self,
    }

    self.dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        padding_bottom = 0, -- ensured by MenuBar
        VerticalGroup:new{
            self.config_panel,
            self.config_menubar,
        },
    }

    -- Reset the focusmanager cursor
    self:moveFocusTo(self.panel_index, #self.layout, FocusManager.NOT_FOCUS)

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
    local old_layout_h = self.layout and #self.layout
    self:update()
    -- NOTE: Keep that one as UI to avoid delay when both this and the topmenu are shown.
    --       Plus, this is also called for each tab anyway, so that wouldn't have been great.
    -- NOTE: And we also only need to repaint what's behind us when switching to a smaller dialog...
    --       This is trickier than in touchmenu, because dimen appear to fluctuate before/after painting...
    --       So we've settled instead for the amount of lines in the panel, as line-height is constant.
    local keep_bg = old_layout_h and #self.layout >= old_layout_h
    UIManager:setDirty((self.is_fresh or keep_bg) and self or "all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dialog_frame.dimen)
            or self.dialog_frame.dimen
        self.is_fresh = false
        return "ui", refresh_dimen
    end)
    return true
end

function ConfigDialog:onConfigChoice(option_name, option_value)
    self.ui:handleEvent(Event:new("ConfigChange", option_name, option_value))
    return true
end

function ConfigDialog:onConfigEvent(option_event, option_arg, when_applied_callback)
    self.ui:handleEvent(Event:new(option_event, option_arg, when_applied_callback))
    return true
end

function ConfigDialog:onConfigChoose(values, name, event, args, position, hide_on_apply)
    UIManager:tickAfterNext(function()
        -- Repainting may be delayed depending on options
        local refresh_dialog_func = function()
            self.skip_paint = nil
            UIManager:setDirty(self, function()
                return "ui", self.dialog_frame.dimen
            end)
        end
        local when_applied_callback = nil
        if type(hide_on_apply) == "number" then -- timeout
            UIManager:scheduleIn(hide_on_apply, refresh_dialog_func)
            self.skip_paint = true
        elseif hide_on_apply then -- anything but nil or false: provide a callback
            -- This needs the config option to have an "event" key
            -- The event handler is responsible for calling this callback when
            -- it considers it appropriate
            when_applied_callback = refresh_dialog_func
            self.skip_paint = true
        end
        if values then
            self:onConfigChoice(name, values[position])
        end
        if event then
            args = args or {}
            self:onConfigEvent(event, args[position], when_applied_callback)
        end
        -- Even if each toggle refreshes itself when toggled, we still
        -- need to update and repaint the whole config panel, as other
        -- toggles may have their state (enabled/disabled) modified
        -- after this toggle update.
        self:update()
        if not hide_on_apply then -- immediate refresh
            refresh_dialog_func()
        end
    end)
end

-- Tweaked variant used with the fine_tune variant of buttonprogress (direction can only be "-" or "+")
function ConfigDialog:onConfigFineTuneChoose(values, name, event, args, direction, hide_on_apply, params)
    UIManager:tickAfterNext(function()
        -- Repainting may be delayed depending on options
        local refresh_dialog_func = function()
            self.skip_paint = nil
            UIManager:setDirty(self, function()
                return "ui", self.dialog_frame.dimen
            end)
        end
        local when_applied_callback = nil
        if type(hide_on_apply) == "number" then -- timeout
            UIManager:scheduleIn(hide_on_apply, refresh_dialog_func)
            self.skip_paint = true
        elseif hide_on_apply then -- anything but nil or false: provide a callback
            -- This needs the config option to have an "event" key
            -- The event handler is responsible for calling this callback when
            -- it considers it appropriate
            when_applied_callback = refresh_dialog_func
            self.skip_paint = true
        end
        if values then
            local value
            local step = params and params.value_step or 1
            if direction == "-" then
                value = self.configurable[name] or values[1]
                if type(value) == "table" then
                    -- Don't update directly this table: it might be a reference
                    -- to one of the original preset values tables
                    local updated = {}
                    for i=1, #value do
                        local v = value[i] - step
                        if v < 0 then
                            v = 0
                        end
                        table.insert(updated, v)
                    end
                    value = updated
                else
                    value = value - step
                    if value < 0 then
                        value = 0
                    end
                end
            else
                value = self.configurable[name] or values[#values]
                if type(value) == "table" then
                    local updated = {}
                    for i=1, #value do
                        table.insert(updated, value[i] + step)
                    end
                    value = updated
                else
                    value = value + step
                end
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
            self:onConfigEvent(event, arg, when_applied_callback)
        end
        -- Even if each toggle refreshes itself when toggled, we still
        -- need to update and repaint the whole config panel, as other
        -- toggles may have their state (enabled/disabled) modified
        -- after this toggle update.
        self:update()
        if not hide_on_apply then -- immediate refresh
            refresh_dialog_func()
        end
    end)
end

-- Tweaked variant used with the more options variant of buttonprogress and fine tune with numpicker
-- events are not supported
function ConfigDialog:onConfigMoreChoose(values, default_value_orig, name, event, args, name_text, more_options_param)
    if not more_options_param then
        more_options_param = {}
    end
    UIManager:tickAfterNext(function()
        -- Repainting may be delayed depending on options
        local refresh_dialog_func = function(keep_skip_paint)
            if self.skip_paint and not keep_skip_paint then
                self.skip_paint = nil
            end
            if self.skip_paint then
                -- Redraw anything below the now hidden ConfigDialog
                UIManager:setDirty("all", function()
                    return "partial", self.dialog_frame.dimen
                end)
            else
                UIManager:setDirty(self, function()
                    return "ui", self.dialog_frame.dimen
                end)
                -- FocusManager loses its marbles (we can only navigate on the row of the selected option) if we don't update the widget *again*...
                -- (possibly because of the layout nastiness happening in ConfigOption:init)
                if Device:hasDPad() then
                    self:update()
                end
            end
        end
        local hide_on_picker_show = more_options_param.hide_on_picker_show
        if hide_on_picker_show == nil then -- default to true if unset
            hide_on_picker_show = true
        end
        local when_applied_callback = nil
        if type(hide_on_picker_show) == "number" then -- timeout
            UIManager:scheduleIn(hide_on_picker_show, refresh_dialog_func)
            self.skip_paint = true
        elseif hide_on_picker_show then -- anything but nil or false: provide a callback
            -- This needs the config option to have an "event" key
            -- The event handler is responsible for calling this callback when
            -- it considers it appropriate
            when_applied_callback = refresh_dialog_func
            self.skip_paint = true
        end
        if values and event then
            if more_options_param.name then
                name = more_options_param.name
            end
            if more_options_param.name_text then
                name_text = more_options_param.name_text
            end
            if more_options_param.event then
                event = more_options_param.event
            end
            local widget
            if more_options_param.left_min then -- DoubleSpinWidget
                local DoubleSpinWidget = require("ui/widget/doublespinwidget")
                -- (No support for value_table - add it if needed)
                local curr_values, left_default, right_default
                if more_options_param.names then -- allows managing 2 different settings
                    curr_values = { self.configurable[more_options_param.names[1]],
                                    self.configurable[more_options_param.names[2]] }
                    left_default = G_reader_settings:readSetting(self.config_options.prefix.."_"..more_options_param.names[1])
                        or default_value_orig[1]
                    right_default = G_reader_settings:readSetting(self.config_options.prefix.."_"..more_options_param.names[2])
                        or default_value_orig[2]
                else
                    curr_values = self.configurable[name]
                    local default_values = G_reader_settings:readSetting(self.config_options.prefix.."_"..name)
                        or default_value_orig
                    left_default = default_values[1]
                    right_default = default_values[2]
                end
                widget = DoubleSpinWidget:new{
                    width_factor = more_options_param.widget_width_factor,
                    title_text =  name_text or _("Set values"),
                    info_text = more_options_param.info_text,
                    left_text = more_options_param.left_text,
                    right_text = more_options_param.right_text,
                    left_value = curr_values[1],
                    left_min = more_options_param.left_min,
                    left_max = more_options_param.left_max,
                    left_step = more_options_param.left_step,
                    left_hold_step = more_options_param.left_hold_step,
                    right_value = curr_values[2],
                    right_min = more_options_param.right_min,
                    right_max = more_options_param.right_max,
                    right_step = more_options_param.right_step,
                    right_hold_step = more_options_param.right_hold_step,
                    left_default = left_default,
                    right_default = right_default,
                    keep_shown_on_apply = true,
                    unit = more_options_param.unit,
                    precision = more_options_param.precision,
                    close_callback = function()
                        if when_applied_callback then
                            when_applied_callback()
                            when_applied_callback = nil
                        end
                    end,
                    callback = function(left_value, right_value)
                        local value_tables = { left_value, right_value }
                        if more_options_param.names then
                            self:onConfigChoice(more_options_param.names[1], left_value)
                            self:onConfigChoice(more_options_param.names[2], right_value)
                        else
                            self:onConfigChoice(name, value_tables)
                        end
                        if event then
                            -- Repainting (with when_applied_callback) if hide_on_picker_show
                            -- is done in close_callback, but we want onConfigEvent to
                            -- show a message when settings applied: handlers that can do
                            -- it actually do it when provided a callback as argument
                            local dummy_callback = when_applied_callback and function() end
                            args = args or {}
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_MORE)
                            self:onConfigEvent(event, value_tables, dummy_callback)
                            UIManager:tickAfterNext(function()
                                Notification:resetNotifySource()
                            end)
                            self:update()
                        end
                    end,
                    extra_text = _("Set as default"),
                    extra_callback = function(left_value, right_value)
                        local value_tables = { left_value, right_value }
                        local values_string
                        if more_options_param.show_true_value_func then
                            values_string = more_options_param.show_true_value_func(value_tables)
                        else
                            values_string = T("%1, %2", left_value, right_value)
                        end
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Set default %1 to %2?"), (name_text or ""), values_string),
                            ok_text = T(_("Set as default")),
                            ok_callback = function()
                                local setting_name
                                if more_options_param.names then
                                    setting_name = self.config_options.prefix.."_"..more_options_param.names[1]
                                    G_reader_settings:saveSetting(setting_name, left_value)
                                    setting_name = self.config_options.prefix.."_"..more_options_param.names[2]
                                    G_reader_settings:saveSetting(setting_name, right_value)
                                else
                                    setting_name = self.config_options.prefix.."_"..name
                                    G_reader_settings:saveSetting(setting_name, value_tables)
                                end
                                widget.left_default = left_value
                                widget.right_default = right_value
                                widget:update()
                                self:update()
                                UIManager:setDirty(self, function()
                                    return "ui", self.dialog_frame.dimen
                                end)
                            end,
                        })
                    end,
                }
            else -- SpinWidget with single value
                local SpinWidget = require("ui/widget/spinwidget")
                local value_hold_step = 0
                if more_options_param.value_hold_step then
                    value_hold_step = more_options_param.value_hold_step
                elseif values and #values > 1 then
                    value_hold_step = values[2] - values[1]
                end
                local curr_items = self.configurable[name]
                local value_index
                local default_value = G_reader_settings:readSetting(self.config_options.prefix.."_"..name)
                    or default_value_orig
                if more_options_param.value_table then
                    local table_shift = more_options_param.value_table_shift or 0
                    value_index = curr_items + table_shift
                    default_value = default_value + table_shift
                end
                widget = SpinWidget:new{
                    width_factor = more_options_param.widget_width_factor,
                    title_text =  name_text or _("Set value"),
                    info_text = more_options_param.info_text,
                    value = curr_items,
                    value_index = value_index,
                    value_table = more_options_param.value_table,
                    value_min = more_options_param.value_min or values[1],
                    value_step = more_options_param.value_step or 1,
                    value_hold_step = value_hold_step,
                    value_max = more_options_param.value_max or values[#values],
                    unit = more_options_param.unit,
                    precision = more_options_param.precision,
                    default_value = default_value,
                    keep_shown_on_apply = true,
                    close_callback = function()
                        if when_applied_callback then
                            when_applied_callback()
                            when_applied_callback = nil
                        end
                    end,
                    callback = function(spin)
                        local spin_value
                        if more_options_param.value_table then
                            local table_shift = more_options_param.value_table_shift or 0
                            spin_value = spin.value_index - table_shift
                        else
                            spin_value = spin.value
                        end
                        self:onConfigChoice(name, spin_value)
                        if event then
                            -- Repainting (with when_applied_callback) if hide_on_picker_show
                            -- is done in close_callback, but we want onConfigEvent to
                            -- show a message when settings applied: handlers that can do
                            -- it actually do it when provided a callback as argument
                            local dummy_callback = when_applied_callback and function() end
                            args = args or {}
                            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_MORE)
                            self:onConfigEvent(event, spin_value, dummy_callback)
                            UIManager:tickAfterNext(function()
                                Notification:resetNotifySource()
                            end)
                            self:update()
                        end
                    end,
                    extra_text = _("Set as default"),
                    extra_callback = function(spin)
                        local value_string
                        if more_options_param.show_true_value_func then
                            value_string = more_options_param.show_true_value_func(spin.value)
                        else
                            value_string = spin.value
                        end
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Set default %1 to %2?"), (name_text or ""), value_string),
                            ok_text = T(_("Set as default")),
                            ok_callback = function()
                                local spin_value
                                if more_options_param.value_table then
                                    local table_shift = more_options_param.value_table_shift or 0
                                    spin_value = spin.value_index - table_shift
                                    widget.default_value = spin.value_index
                                else
                                    spin_value = spin.value
                                    widget.default_value = spin.value
                                end
                                G_reader_settings:saveSetting(self.config_options.prefix.."_"..name, spin_value)
                                widget:update()
                                self:update()
                                UIManager:setDirty(self, function()
                                    return "ui", self.dialog_frame.dimen
                                end)
                            end,
                        })
                    end,
                    option_text =  more_options_param.other_button and more_options_param.other_button.text,
                    option_callback =  more_options_param.other_button and function()
                        when_applied_callback = nil -- prevent bottom menu from being shown (before being hidden again)
                        widget:onClose()
                        local option = self:findOptionByName(more_options_param.other_button.other_option)
                        local default_value_original
                        if option.more_options_param.names then
                            local option1 = self:findOptionByName(option.more_options_param.names[1])
                            local option2 = self:findOptionByName(option.more_options_param.names[2])
                            default_value_original = { option1.default_value, option2.default_value }
                        else
                            default_value_original = option.default_value
                        end
                        self:onConfigMoreChoose(option.values, default_value_original, option.name,
                            option.event, nil, option.name_text, option.more_options_param)
                    end,
                }
            end
            UIManager:show(widget)
        end
        -- Even if skip_paint (to temporarily hide it), we need
        -- to issue setDirty for what's below to be painted
        refresh_dialog_func(true)
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
        display_value = serpent.block(display_value, { maxlevel = 6, indent = "  ", comment = false, nocode = true })
    end

    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default %1 to %2?"),
            (name_text or ""),
            display_value
        ),
        ok_text = T(_("Set as default")),
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
    local current_value = self.configurable[name] or direction == "-" and labels[1] or labels[#labels]

    local display_value
    -- known table value, make it pretty
    if name == "h_page_margins" then
            display_value = T(_([[

  left:  %1
  right: %2
]]),
        current_value[1], current_value[2])
    elseif type(current_value) == "table" then
        display_value = serpent.block(current_value, { maxlevel = 6, indent = "  ", comment = false, nocode = true })
    else
        display_value = current_value
    end

    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default %1 to %2?"),
            (name_text or ""),
            display_value
        ),
        ok_text = T(_("Set as default")),
        ok_callback = function()
            name = self.config_options.prefix.."_"..name
            G_reader_settings:saveSetting(name, current_value)
            self:update()
            UIManager:setDirty(self, function()
                return "ui", self.dialog_frame.dimen
            end)
        end,
    })
end

function ConfigDialog:findOptionByName(name)
    local option
    for i=1, #self.config_options do
        local options = self.config_options[i].options
        for j=1, #options do
            if options[j].name == name then
                option = options[j]
                break
            end
        end
        if option then
            break
        end
    end
    return option
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
    local DTAP_ZONE_CONFIG = G_defaults:readSetting("DTAP_ZONE_CONFIG")
    local range = Geom:new{
        x = DTAP_ZONE_CONFIG.x * Screen:getWidth(),
        y = DTAP_ZONE_CONFIG.y * Screen:getHeight(),
        w = DTAP_ZONE_CONFIG.w * Screen:getWidth(),
        h = DTAP_ZONE_CONFIG.h * Screen:getHeight(),
    }
    local DTAP_ZONE_CONFIG_EXT = G_defaults:readSetting("DTAP_ZONE_CONFIG_EXT")
    local range_ext = Geom:new{
        x = DTAP_ZONE_CONFIG_EXT.x * Screen:getWidth(),
        y = DTAP_ZONE_CONFIG_EXT.y * Screen:getHeight(),
        w = DTAP_ZONE_CONFIG_EXT.w * Screen:getWidth(),
        h = DTAP_ZONE_CONFIG_EXT.h * Screen:getHeight(),
    }
    if ges_ev.direction == "south" and (ges_ev.pos:intersectWith(self.dialog_frame.dimen)
        or ges_ev.pos:intersectWith(range) or ges_ev.pos:intersectWith(range_ext)) then
        self:closeDialog()
        return true
    end
end

function ConfigDialog:onClose()
    self:closeDialog()
    return true
end

return ConfigDialog
