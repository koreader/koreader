--[[--
Widget that shows a message and OK/Cancel buttons

Example:

    UIManager:show(ConfirmBox:new{
        text = _("Save the document?"),
        ok_text = _("Save"),  -- ok_text defaults to _("OK")
        ok_callback = function()
            -- save document
        end,
    })

]]

local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ButtonTable = require("ui/widget/buttontable")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")


local ConfirmBox = InputContainer:new{
    modal = true,
    text = _("no text"),
    face = Font:getFace("infofont", 25),
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
    ok_callback = function() end,
    cancel_callback = function() end,
    margin = 5,
    padding = 5,
}

function ConfirmBox:init()
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
    local content = HorizontalGroup:new{
        align = "center",
        ImageWidget:new{
            file = "resources/info-i.png"
        },
        HorizontalSpan:new{ width = 10 },
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
                    text = self.ok_text,
                    callback = function()
                        self.ok_callback()
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
            VerticalGroup:new{
                align = "left",
                content,
                button_table,
            }
        }
    }
end

function ConfirmBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function ConfirmBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
end

function ConfirmBox:onClose()
    -- Call cancel_callback, parent may expect a choice
    self.cancel_callback()
    UIManager:close(self)
    return true
end

function ConfirmBox:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        self:onClose()
        return true
    end
    return false
end

function ConfirmBox:onSelect()
    logger.dbg("selected:", self.selected.x)
    if self.selected.x == 1 then
        self:ok_callback()
    else
        self:cancel_callback()
    end
    UIManager:close(self)
    return true
end

return ConfirmBox
