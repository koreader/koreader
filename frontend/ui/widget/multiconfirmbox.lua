--[[--
Widget that shows a message and choice1/choice2/Cancel buttons

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
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
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
    margin = 5,
    padding = 5,
}

function MultiConfirmBox:init()
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
            VerticalGroup:new{
                align = "left",
                content,
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
