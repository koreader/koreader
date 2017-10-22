--[[--
Widget that shows a message and cancel/choice1/choice2 buttons

Example:

    UIManager:show(MultiConfirmBox:new{
        text = T( _("Set %1 as fallback font?"), face),
        choice1_text = _("Default"),
        choice1_callback = function()
            -- set as default font
        end,
        choice2_text = _("Fallback"),
        choice2_callback = function()
            -- set as fallback font
        end,
    })
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen

local MultiConfirmBox = InputContainer:new{
    modal = true,
    text = _("no text"),
    face = Font:getFace("infofont"),
    choice1_text = _("Choice 1"),
    choice2_text = _("Choice 2"),
    cancel_text = _("Cancel"),
    choice1_callback = function() end,
    choice2_callback = function() end,
    cancel_callback = function() end,
    margin = Size.margin.default,
    padding = Size.padding.default,
    dismissable = true, -- set to false if any button callback is required
}

function MultiConfirmBox:init()
    if self.dismissable then
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
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
            self.key_events = {
                Close = { {"Back"}, doc = "cancel" }
            }
        end
    end
    local content = HorizontalGroup:new{
        align = "center",
        ImageWidget:new{
            file = "resources/info-i.png",
            scale_for_dpi = true,
        },
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        TextBoxWidget:new{
            text = self.text,
            face = self.face,
            width = Screen:getWidth()*2/3,
        }
    }

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = {
            {
                {
                    text = self.cancel_text,
                    callback = function()
                        self.cancel_callback()
                        UIManager:close(self)
                    end,
                },
                {
                    text = self.choice1_text,
                    callback = function()
                        self.choice1_callback()
                        UIManager:close(self)
                    end,
                },
                {
                    text = self.choice2_text,
                    callback = function()
                        self.choice2_callback()
                        UIManager:close(self)
                    end,
                },
            },
        },
        zero_sep = true,
        show_parent = self,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            margin = self.margin,
            padding = self.padding,
            padding_bottom = 0, -- no padding below buttontable
            VerticalGroup:new{
                align = "left",
                content,
                -- Add same vertical space after than before content
                VerticalSpan:new{ width = self.margin + self.padding },
                button_table,
            }
        }
    }
end

function MultiConfirmBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function MultiConfirmBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
end

function MultiConfirmBox:onClose()
    UIManager:close(self)
    return true
end

function MultiConfirmBox:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        self:onClose()
        return true
    end
    return false
end

function MultiConfirmBox:onSelect()
    logger.dbg("selected:", self.selected.x)
    if self.selected.x == 1 then
        self:choice1_callback()
    elseif self.selected.x == 2 then
        self:choice2_callback()
    elseif self.selected.x == 0 then
        self:cancle_callback()
    end
    UIManager:close(self)
    return true
end

return MultiConfirmBox
