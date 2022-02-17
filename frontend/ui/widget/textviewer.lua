--[[--
Displays some text in a scrollable view.

@usage
    local textviewer = TextViewer:new{
        title = _("I can scroll!"),
        text = _("I'll need to be longer than this example to scroll."),
    }
    UIManager:show(textviewer)
]]
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local TextViewer = InputContainer:new{
    modal = true,
    title = nil,
    text = nil,
    width = nil,
    height = nil,
    buttons_table = nil,
    -- See TextBoxWidget for details about these options
    -- We default to justified and auto_para_direction to adapt
    -- to any kind of text we are given (book descriptions,
    -- bookmarks' text, translation results...).
    -- When used to display more technical text (HTML, CSS,
    -- application logs...), it's best to reset them to false.
    alignment = "left",
    justified = true,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = true,
    alignment_strict = false,

    title_face = nil, -- use default from TitleBar
    title_multilines = nil, -- see TitleBar for details
    title_shrink_font_to_fit = nil, -- see TitleBar for details
    text_face = Font:getFace("x_smallinfofont"),
    fgcolor = Blitbuffer.COLOR_BLACK,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
}

function TextViewer:init()
    -- calculate window dimension
    self.align = "center"
    self.region = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.width = self.width or Screen:getWidth() - Screen:scaleBySize(30)
    self.height = self.height or Screen:getHeight() - Screen:scaleBySize(30)

    if Device:hasKeys() then
        self.key_events = {
            Close = { {Device.input.group.Back}, doc = "close text viewer" }
        }
    end

    if Device:isTouchDevice() then
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                },
            },
        }
    end

    local titlebar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        title_face = self.title_face,
        title_multilines = self.title_multilines,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local buttons = self.buttons_table or
        {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(self)
                    end,
                },
            },
        }
    local button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local textw_height = self.height - titlebar:getHeight() - button_table:getSize().h

    self.scroll_text_w = ScrollTextWidget:new{
        text = self.text,
        face = self.text_face,
        fgcolor = self.fgcolor,
        width = self.width - 2*self.text_padding - 2*self.text_margin,
        height = textw_height - 2*self.text_padding -2*self.text_margin,
        dialog = self,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
    }
    self.textw = FrameContainer:new{
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w
    }

    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            titlebar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = button_table:getSize().h,
                },
                button_table,
            }
        }
    }
    self.movable = MovableContainer:new{
        ignore_events = {"swipe"},
        self.frame,
    }
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
end

function TextViewer:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
end

function TextViewer:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    return true
end

function TextViewer:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function TextViewer:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function TextViewer:onClose()
    UIManager:close(self)
    return true
end

function TextViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        else
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
    end
    -- Let our MovableContainer handle swipe outside of text
    return self.movable:onMovableSwipe(arg, ges)
end

return TextViewer
