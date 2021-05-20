--[[--
Displays a button that toggles between states. Used in bottom configuration panel.

@usage
    local ToggleSwitch = require("ui/widget/toggleswitch")
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local Screen = Device.screen

local ToggleLabel = TextWidget:new{
    bold = true,
    bgcolor = Blitbuffer.COLOR_WHITE,
    fgcolor = Blitbuffer.COLOR_BLACK,
}

local ToggleSwitch = InputContainer:new{
    width = Screen:scaleBySize(216),
    height = Size.item.height_default,
    bgcolor = Blitbuffer.COLOR_WHITE, -- unfocused item color
    fgcolor = Blitbuffer.COLOR_DARK_GRAY, -- focused item color
    font_face = "cfont",
    font_size = 16,
    enabled = true,
    row_count = 1,
}

function ToggleSwitch:init()
    -- Item count per row
    self.n_pos = math.ceil(#self.toggle / self.row_count)
    self.position = nil

    self.toggle_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        radius = Size.radius.window,
        bordersize = Size.border.thin,
        padding = Size.padding.small,
        dim = not self.enabled,
    }

    self.toggle_content = VerticalGroup:new{}
    for i = 1, self.row_count do
        table.insert(self.toggle_content, HorizontalGroup:new{})
    end

    local item_padding = Size.padding.default -- only used to check if text truncate needed
    local item_border_size = Size.border.thin
    local frame_inner_width = self.width - 2*self.toggle_frame.padding - 2* self.toggle_frame.bordersize
    -- We'll need to adjust items width and distribute the accumulated fractional part to some
    -- of them for proper visual alignment
    local item_width_real = frame_inner_width / self.n_pos - 2*item_border_size
    local item_width = math.floor(item_width_real)
    local item_width_adjust = item_width_real - item_width
    -- Note: the height provided by ConfigDialog might be smaller than needed,
    -- it gets too thin if we account for padding & border
    local item_height = self.height / self.row_count
    local item_width_to_add = 0
    for i = 1, #self.toggle do
        local real_item_width = item_width
        item_width_to_add = item_width_to_add + item_width_adjust
        if item_width_to_add >= 1 then
            -- One pixel wider to better align the entire widget
            real_item_width = item_width + math.floor(item_width_to_add)
            item_width_to_add = item_width_to_add - math.floor(item_width_to_add)
        end
        local text = self.toggle[i]
        local face = Font:getFace(self.font_face, self.font_size)
        local label = ToggleLabel:new{
            text = text,
            face = face,
            max_width = real_item_width - item_padding,
        }
        local content = CenterContainer:new{
            dimen = Geom:new{
                w = real_item_width,
                h = item_height,
            },
            label,
        }
        local button = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            color = Blitbuffer.COLOR_DARK_GRAY,
            margin = 0,
            radius = Size.radius.window,
            bordersize = item_border_size,
            padding = 0,
            content,
        }
        table.insert(self.toggle_content[math.ceil(i / self.n_pos)], button)
    end
    self.toggle_frame[1] = self.toggle_content
    self[1] = self.toggle_frame
    self.dimen = Geom:new(self.toggle_frame:getSize())
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Toggle switch",
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold switch",
            },
        }
    end
end

function ToggleSwitch:update()
    local pos = self.position
    for i = 1, #self.toggle_content do
        local row = self.toggle_content[i]
        for j = 1, #row do
            local cell = row[j]
            if pos == (i - 1) * self.n_pos + j then
                cell.color = self.fgcolor
                cell.background = self.fgcolor
                cell[1][1].fgcolor = Blitbuffer.COLOR_WHITE
            else
                cell.color = self.bgcolor
                cell.background = self.bgcolor
                cell[1][1].fgcolor = Blitbuffer.COLOR_BLACK
            end
        end
    end
end

function ToggleSwitch:setPosition(position)
    self.position = position
    self:update()
end

function ToggleSwitch:togglePosition(position, update)
    if self.n_pos == 2 and self.alternate ~= false then
        self.position = (self.position+1)%self.n_pos
        self.position = self.position == 0 and self.n_pos or self.position
    elseif self.n_pos == 1 then
        self.position = self.position == 1 and 0 or 1
    else
        self.position = position
    end
    if update then
        self:update()
    end
end

function ToggleSwitch:circlePosition()
    if self.position then
        self.position = (self.position+1)%self.n_pos
        self.position = self.position == 0 and self.n_pos or self.position
        self:update()
    end
end

function ToggleSwitch:calculatePosition(gev)
    local x = (gev.pos.x - self.dimen.x) / self.dimen.w * self.n_pos
    if BD.mirroredUILayout() then
        x = self.n_pos - x
    end
    local y = (gev.pos.y - self.dimen.y) / self.dimen.h * self.row_count
    return math.max(1, math.ceil(x)) + math.min(self.row_count-1, math.floor(y)) * self.n_pos
end

function ToggleSwitch:onTapSelect(arg, gev)
    if not self.enabled then
        if self.readonly ~= true then
            return true
        else
            return
        end
    end
    if gev then
        local position = self:calculatePosition(gev)
        if self.toggle[position] ~= "⋮" then
            self:togglePosition(position, true)
        else
            self:togglePosition(position, false)
        end
    else
        self:circlePosition()
    end

    --[[
    if self.values then
        self.values = self.values or {}
        self.config:onConfigChoice(self.name, self.values[self.position])
    end
    if self.event then
        self.args = self.args or {}
        self.config:onConfigEvent(self.event, self.args[self.position])
    end
    if self.events then
        self.config:onConfigEvents(self.events, self.position)
    end
    --]]
    if self.callback then
        self.callback(self.position)
    end
    if self.toggle[self.position] ~= "⋮" then
        if #self.values == 0 then -- this is a toggle which is not selectable (eg. increase, decrease)
            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_FINE)
        else
            Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_TOGGLE)
        end
        self.config:onConfigChoose(self.values, self.name,
            self.event, self.args, self.events, self.position, self.hide_on_apply)

        UIManager:setDirty(self.config, function()
            return "ui", self.dimen
        end)

        UIManager:tickAfterNext(function()
            Notification:setNotifySource(Notification.SOURCE_OTHER) -- only allow events, if they are activated
        end)
    end
    return true
end

function ToggleSwitch:onHoldSelect(arg, gev)
    local position = self:calculatePosition(gev)
    if self.toggle[position] == "⋮" then
        return true
    end
    if self.name == "font_fine_tune" then
        --- @note Ugly hack for the only widget that uses a dual toggle for fine-tuning (others prefer a buttonprogress)
        self.config:onMakeFineTuneDefault("font_size", _("Font Size"),
                        self.values or self.args, self.toggle, position == 1 and "-" or "+")
    else
        self.config:onMakeDefault(self.name, self.name_text,
                        self.values or self.args, self.toggle, position)
    end
    return true
end

function ToggleSwitch:onFocus()
    self.toggle_frame.background = Blitbuffer.COLOR_BLACK
    return true
end

function ToggleSwitch:onUnfocus()
    self.toggle_frame.background = Blitbuffer.COLOR_WHITE
    return true
end

return ToggleSwitch
