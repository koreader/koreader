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
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
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

    title_face = Font:getFace("x_smalltfont"),
    text_face = Font:getFace("x_smallinfofont"),
    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
}

function TextViewer:init()
    local orig_dimen = self.frame and self.frame.dimen or Geom:new{}
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
            Close = { {"Back"}, doc = "close text viewer" }
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

    local closeb = CloseButton:new{ window = self, padding_top = Size.padding.tiny, }
    local title_text = TextBoxWidget:new{
        text = self.title,
        face = self.title_face,
        bold = true,
        width = self.width - 2*self.title_padding - 2*self.title_margin - closeb:getSize().w,
    }
    local titlew = FrameContainer:new{
        padding = self.title_padding,
        -- TextBoxWidget has less text top & bottom padding than TextWidget
        -- (for a reasonable line height with multi lines), but we
        -- can get the same as TextWidget by simply adding Size.padding.small
        padding_top = self.title_padding + Size.padding.small,
        padding_bottom = self.title_padding + Size.padding.small,
        margin = self.title_margin,
        bordersize = 0,
        title_text
    }
    titlew = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = titlew:getSize().h
        },
        titlew,
        closeb,
    }

    local separator = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }

    local buttons
    if self.buttons_table == nil then
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(self)
                    end,
                },
            },
        }
    else
        buttons = self.buttons_table
    end
    local button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local textw_height = self.height - titlew:getSize().h - separator:getSize().h - button_table:getSize().h

    self.scroll_text_w = ScrollTextWidget:new{
        text = self.text,
        face = self.text_face,
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
            align = "left",
            titlew,
            separator,
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
        local update_region = self.frame.dimen:combine(orig_dimen)
        logger.dbg("update region", update_region)
        return "partial", update_region
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
