--[[--
Widget that shows a confirmation alert with a message and Cancel/OK buttons

Example:

    UIManager:show(ConfirmBox:new{
        text = _("Save the document?"),
        ok_text = _("Save"),  -- ok_text defaults to _("OK")
        ok_callback = function()
            -- save document
        end,
    })

It is strongly recommended to set a custom `ok_text` describing the action to be
confirmed, as demonstrated in the example above. No ok_text should be specified
if the resulting phrase would be longer than three words.

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
local Screen = Device.screen

local ConfirmBox = InputContainer:new{
    modal = true,
    text = _("no text"),
    face = Font:getFace("infofont"),
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
    ok_callback = function() end,
    cancel_callback = function() end,
    other_buttons = nil,
    margin = Size.margin.default,
    padding = Size.padding.default,
    dismissable = true, -- set to false if any button callback is required
}

function ConfirmBox:init()
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

    local buttons = {{
        text = self.cancel_text,
        callback = function()
            self.cancel_callback()
            UIManager:close(self)
        end,
    }, {
        text = self.ok_text,
        callback = function()
            self.ok_callback()
            UIManager:close(self)
        end,
    },}

    if self.other_buttons ~= nil then
        for __, button in ipairs(self.other_buttons) do
            assert(type(button.text) == "string")
            assert(button.callback == nil or type(button.callback) == "function")
            table.insert(buttons, {
                text = button.text,
                callback = function()
                    if button.callback ~= nil then
                        button.callback()
                    end
                    UIManager:close(self)
                end,
            })
        end
    end

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = { buttons },
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
