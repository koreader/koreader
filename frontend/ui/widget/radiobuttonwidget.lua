--[[--
Widget that allows selecting an entry from a @{ui.widget.radiobuttontable|RadioButton} list.


Example:
    local RadioButtonWidget = require("ui/widget/radiobuttonwidget")

    local radio_buttons = {
        { {text = _("Radio 1"), provider = 1} },
        { {text = _("Radio 2"), provider = 2, checked = true} },
        { {text = _("Radio 3"), provider = "identifier"} },
    }
    UIManager:show(RadioButtonWidget:new{
        title_text = _("Example Title"),
        info_text = _("Some more information"),
        cancel_text = _("Close"),
        ok_text = _("Apply"),
        width_factor = 0.9,
        radio_buttons = radio_buttons,
        callback = function(radio)
            if radio.provider == 1 then
                -- do something here
            elseif radio.provider == 2 then
                -- do some other things here
            elseif radio.provider == "identifier" then
                -- or do a third thing here
            end
        end,
    })
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local RadioButtonWidget = FocusManager:extend{
    title_text = "",
    info_text = nil,
    width = nil,
    width_factor = nil,
    height = nil,
    radio_buttons = nil, -- row x column table
    cancel_text = _("Close"),
    ok_text = _("Apply"),
    cancel_callback = nil,
    callback = nil,
    close_callback = nil,
    keep_shown_on_apply = false,
    default_provider = nil,
    extra_text = nil,
    extra_callback = nil,
    colorful = false, -- should be set to true if any of the buttons' text is colorful
    -- output
    provider = nil, -- provider of the checked button
    row = nil, -- row of the checked button
    col = nil, -- column of the checked button
}

function RadioButtonWidget:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if not self.width then
        if not self.width_factor then
            self.width_factor = 0.6
        end
        self.width = math.floor(math.min(self.screen_width, self.screen_height) * self.width_factor)
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                w = self.screen_width,
                h = self.screen_height,
            }
        },
    }

    -- Check if any of our buttons use color text...
    -- NOTE: There are so few callers that require this, that we just let them set the colorful field themselves...
    --[[
    for row, t in ipairs(self.radio_buttons) do
        for col, w in ipairs(t) do
            if w.fgcolor and not Blitbuffer.isColor8(w.fgcolor) then
                self.colorful = true
                break
            end
            if w.bgcolor and not Blitbuffer.isColor8(w.bgcolor) then
                self.colorful = true
                break
            end
        end
        if self.colorful then
            break
        end
    end
    --]]

    self:update()
end

function RadioButtonWidget:update()
    self.layout = {}
    if self.default_provider then
        local row, col = self:getButtonIndex(self.default_provider)
        self.radio_buttons[row][col].text = self.radio_buttons[row][col].text .. "\u{A0}\u{A0}★"
    end

    local value_widget = RadioButtonTable:new{
        radio_buttons = self.radio_buttons,
        width = math.floor(self.width * 0.9),
        focused = true,
        scroll = false,
        parent = self,
        face = self.face,
    }
    self:mergeLayoutInVertical(value_widget)
    local value_group = HorizontalGroup:new{
        align = "center",
        value_widget,
    }

    local title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title_text,
        title_shrink_font_to_fit = true,
        info_text = self.info_text,
        show_parent = self,
    }

    local buttons = {
        {
            {
                text = self.cancel_text,
                callback = function()
                    if self.cancel_callback then
                        self.cancel_callback()
                    end
                    self:onClose()
                end,
            },
            {
                text = self.ok_text,
                callback = function()
                    if self.callback then
                        self.provider = value_widget.checked_button.provider
                        self.row, self.col = self:getButtonIndex(self.provider)
                        self.callback(self)
                    end
                    if not self.keep_shown_on_apply then
                        self:onClose()
                    end
                end,
            },
        }
    }

    if self.extra_text then
        table.insert(buttons,{
            {
                text = self.extra_text,
                callback = function()
                    if self.extra_callback then
                        self.provider = value_widget.checked_button.provider
                        self.row, self.col = self:getButtonIndex(self.provider)
                        self.extra_callback(self)
                    end
                    if not self.keep_shown_on_apply then
                        self:onClose()
                    end
                end,
            },
        })
    end

    local ok_cancel_buttons = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self:mergeLayoutInVertical(ok_cancel_buttons)
    local vgroup = VerticalGroup:new{
        align = "left",
        title_bar,
    }
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = value_group:getSize().h + 4 * Size.padding.large,
        },
        value_group
    })
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = ok_cancel_buttons:getSize().h,
        },
        ok_cancel_buttons
    })
    self.widget_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        vgroup,
    }
    self.movable = MovableContainer:new{
        self.widget_frame,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        self.movable,
    }

    -- If the device doesn't support Kaleido wfm, or color is disabled, don't bother tweaking the wfm
    if self.colorful and not (Screen:isColorEnabled() and Device:hasKaleidoWfm()) then
        self.colorful = false
    end

    UIManager:setDirty(self, function()
        return self.colorful and "full" or "ui", self.widget_frame.dimen
    end)
end

function RadioButtonWidget:getButtonIndex(provider)
    for i = 1, #self.radio_buttons do -- rows
        for j = 1, #self.radio_buttons[i] do -- columns
            if self.radio_buttons[i][j].provider == provider then
                return i, j
            end
        end
    end
end

function RadioButtonWidget:hasMoved()
    local offset = self.movable:getMovedOffset()
    return offset.x ~= 0 or offset.y ~= 0
end

function RadioButtonWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.widget_frame.dimen
    end)
end

function RadioButtonWidget:onShow()
    UIManager:setDirty(self, function()
        return self.colorful and "full" or "ui", self.widget_frame.dimen
    end)
    return true
end

function RadioButtonWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.widget_frame.dimen) then
        self:onClose()
    end
    return true
end

function RadioButtonWidget:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return RadioButtonWidget
