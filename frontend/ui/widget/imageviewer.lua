local InputContainer = require("ui/widget/container/inputcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local CloseButton = require("ui/widget/closebutton")
local ButtonTable = require("ui/widget/buttontable")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

--[[
Display image with some simple manipulation options
]]
local ImageViewer = InputContainer:new{
    -- Allow for providing same different input types as ImageWidget :
    -- a path to a file
    file = nil,
    -- or an already made BlitBuffer (ie: made by Mupdf.renderImageFile())
    image = nil,
    -- whether provided BlitBuffer should be free(), normally true
    -- unless our caller wants to reuse it's provided image
    image_disposable = true,

    fullscreen = false, -- false will add some padding around widget (so footer can be visible)
    with_title_bar = true,
    title_text = _("Viewing image"), -- default title text

    width = nil,
    height = nil,
    stretched = true, -- start with image stretched (Best fit)
    rotated = false,
    -- we use this global setting for rotation angle to have the same angle as reader
    rotation_angle = DLANDSCAPE_CLOCKWISE_ROTATION and 90 or 270,

    title_face = Font:getFace("tfont", 22),
    title_padding = Screen:scaleBySize(5),
    title_margin = Screen:scaleBySize(2),
    image_padding = Screen:scaleBySize(2),
    button_padding = Screen:scaleBySize(14),

    -- Reference to current ImageWidget instance, for cleaning
    _image_wg = nil,
}

function ImageViewer:init()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close viewer" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
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
    self:update()
end

function ImageViewer:_clean_image_wg()
    -- To be called before re-using / not needing self._image_wg
    -- otherwise ressources used by its blitbuffer won't be freed
    if self._image_wg then
        logger.dbg("ImageViewer:_clean_image_wg()")
        self._image_wg:free()
        self._image_wg = nil
    end
end

function ImageViewer:update()
    self:_clean_image_wg() -- clean previous if any
    local orig_dimen = self.main_frame and self.main_frame.dimen or Geom:new{}
    self.align = "center"
    self.region = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if self.fullscreen then
        self.height = Screen:getHeight()
        self.width = Screen:getWidth()
    else
        self.height = Screen:getHeight() - Screen:scaleBySize(40)
        self.width = Screen:getWidth() - Screen:scaleBySize(40)
    end

    local buttons = {
        {
            {
                text = self.stretched and _("Original size") or _("Best fit"),
                callback = function()
                    self.stretched = not self.stretched and true or false
                    self:update()
                end,
            },
            {
                text = self.rotated and _("No rotation") or _("Rotate"),
                callback = function()
                    self.rotated = not self.rotated and true or false
                    self:update()
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(self)
                end,
            },
        },
    }
    local button_table = ButtonTable:new{
        width = self.width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    local button_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = button_table:getSize().h,
        },
        button_table,
    }

    -- height available to our image
    local img_container_h = self.height - button_table:getSize().h

    local title_bar, title_sep
    if self.with_title_bar then
        local title_text = FrameContainer:new{
            padding = self.title_padding,
            margin = self.title_margin,
            bordersize = 0,
            TextWidget:new{
                text = self.title_text,
                face = self.title_face,
                bold = true,
                width = self.width,
            }
        }
        title_bar = OverlapGroup:new{
            dimen = {
                w = self.width,
                h = title_text:getSize().h
            },
            title_text,
            CloseButton:new{ window = self, },
        }
        title_sep = LineWidget:new{
            dimen = Geom:new{
                w = self.width,
                h = Screen:scaleBySize(2),
            }
        }
        -- adjust height available to our image
        img_container_h = img_container_h - title_bar:getSize().h - title_sep:getSize().h
    end

    local max_image_h = img_container_h - self.image_padding*2
    local max_image_w = self.width - self.image_padding*2

    -- Do a first rendering without our h/w to get native image size and see if it needs to be reduced
    self._image_wg = ImageWidget:new{
        file = self.file,
        image = self.image,
        image_disposable = false, -- we may re-use self.image
        alpha = true,
        pre_rotate = self.rotated and self.rotation_angle or 0,
    }
    local imwg_size = self._image_wg:getSize()
    if self.stretched or imwg_size.w > max_image_w or imwg_size.h > max_image_h then
        -- 2nd rendering if it needs to be stretched to fit our size
        self:_clean_image_wg() -- clean previous ImageWidget._bb
        self._image_wg = ImageWidget:new{
            file = self.file,
            image = self.image,
            image_disposable = false, -- we may re-use self.image
            alpha = true,
            width = max_image_w,
            height = max_image_h,
            autostretch = true,
            pre_rotate = self.rotated and self.rotation_angle or 0,
        }
    end

    local image_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = img_container_h,
        },
        self._image_wg,
    }

    local frame_elements
    if self.with_title_bar then
        frame_elements = VerticalGroup:new{
            align = "left",
            title_bar,
            title_sep,
            image_container,
            button_container,
        }
    else
        frame_elements = VerticalGroup:new{
            align = "left",
            image_container,
            button_container,
        }
    end
    self.main_frame = FrameContainer:new{
        radius = not self.fullscreen and 8 or nil,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        frame_elements,
    }
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        FrameContainer:new{
            bordersize = 0,
            padding = Screen:scaleBySize(5),
            self.main_frame,
        }
    }
    UIManager:setDirty("all", function()
        local update_region = self.main_frame.dimen:combine(orig_dimen)
        logger.dbg("update image region", update_region)
        return "partial", update_region
    end)
end

function ImageViewer:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.main_frame.dimen
    end)
    return true
end

function ImageViewer:onTap(arg, ges)
    if ges.pos:notIntersectWith(self.main_frame.dimen) then
        self:onClose()
        return true
    end
    return true
end

function ImageViewer:onSwipe(arg, ges)
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    return true
end

function ImageViewer:onClose()
    UIManager:close(self)
    return true
end

function ImageViewer:onAnyKeyPressed()
    self:onClose()
    return true
end

function ImageViewer:onCloseWidget()
    -- clean all our BlitBuffer objects when UIManager:close() was called
    self:_clean_image_wg()
    if self.image and self.image_disposable and self.image.free then
        logger.dbg("ImageViewer:free(self.image)")
        self.image:free()
        self.image = nil
    end
    UIManager:setDirty(nil, function()
        return "partial", self.main_frame.dimen
    end)
    return true
end

return ImageViewer
