--[[--
ImageViewer displays an image with some simple manipulation options.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

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
    -- A caption can be toggled with tap on title_text (so, it needs with_title_bar=true):
    caption = nil,
    caption_visible = true, -- caption visible by default
    caption_tap_area = nil,

    width = nil,
    height = nil,
    scale_factor = 0, -- start with image scaled for best fit
    rotated = false,

    title_face = Font:getFace("x_smalltfont"),
    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    caption_face = Font:getFace("xx_smallinfofont"),
    caption_padding = Size.padding.large,
    image_padding = Size.margin.small,
    button_padding = Size.padding.default,

    -- sensitivity for hold (trigger full refresh) vs pan (move image)
    pan_threshold = Screen:scaleBySize(5),

    _scale_to_fit = nil, -- state of toggle between our 2 pre-defined scales (scale to fit / original size)
    _panning = false,
    -- Default centering on center of image if oversized
    _center_x_ratio = 0.5,
    _center_y_ratio = 0.5,

    -- Reference to current ImageWidget instance, for cleaning
    _image_wg = nil,
}

function ImageViewer:init()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close viewer" },
            ZoomIn = { {Device.input.group.PgBack}, doc = "Zoom In" },
            ZoomOut = { {Device.input.group.PgFwd}, doc = "Zoom out" },
        }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = range } },
            -- Zoom in/out (Pinch & Spread are not triggered if user is too
            -- slow and Hold event is decided first)
            Spread = { GestureRange:new{ ges = "spread", range = range } },
            Pinch = { GestureRange:new{ ges = "pinch", range = range } },
            -- All the following gestures will allow easy panning
            -- Hold happens if we hold at start
            -- Pan happens if we don't hold at start, but hold at end
            -- Swipe happens if we don't hold at any moment
            Hold = { GestureRange:new{ ges = "hold", range = range } },
            HoldRelease = { GestureRange:new{ ges = "hold_release", range = range } },
            Pan = { GestureRange:new{ ges = "pan", range = range } },
            PanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
            Swipe = { GestureRange:new{ ges = "swipe", range = range } },
        }
    end
    self:update()
end

function ImageViewer:_clean_image_wg()
    -- To be called before re-using / not needing self._image_wg
    -- otherwise resources used by its blitbuffer won't be freed
    if self._image_wg then
        logger.dbg("ImageViewer:_clean_image_wg()")
        self._image_wg:free()
        self._image_wg = nil
    end
end

function ImageViewer:update()
    self:_clean_image_wg() -- clean previous if any
    if self._scale_to_fit == nil then -- initialize our toggle
        self._scale_to_fit = self.scale_factor == 0 and true or false
    end
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
                text = self._scale_to_fit and _("Original size") or _("Scale"),
                callback = function()
                    self.scale_factor = self._scale_to_fit and 1 or 0
                    self._scale_to_fit = not self._scale_to_fit
                    -- Reset center ratio (may have been modified if some panning was done)
                    self._center_x_ratio = 0.5
                    self._center_y_ratio = 0.5
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
        width = self.width - 2*self.button_padding,
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
        -- Toggler (white arrow) for caption, on the left of title
        local ctoggler
        local ctoggler_width = 0
        if self.caption then
            local ctoggler_text
            if self.caption_visible then
                ctoggler_text = "▽ " -- white arrow (nicer than smaller black arrow ▼)
            else
                ctoggler_text = "▷ " -- white arrow (nicer than smaller black arrow ►)
            end
            -- paddings chosen to align nicely with titlew
            ctoggler = FrameContainer:new{
                bordersize = 0,
                padding = self.title_padding,
                padding_top = self.title_padding + Size.padding.small,
                padding_right = 0,
                TextWidget:new{
                    text = ctoggler_text,
                    face = self.title_face,
                }
            }
            ctoggler_width = ctoggler:getSize().w
        end
        local closeb = CloseButton:new{ window = self, padding_top = Size.padding.tiny, }
        local title_tbw = TextBoxWidget:new{
            text = self.title_text,
            face = self.title_face,
            -- bold = true, -- we're already using a bold font
            width = self.width - 2*self.title_padding - 2*self.title_margin - closeb:getSize().w - ctoggler_width,
        }
        local title_tbw_padding_bottom = self.title_padding + Size.padding.small
        if self.caption and self.caption_visible then
            title_tbw_padding_bottom = 0 -- save room between title and caption
        end
        local titlew = FrameContainer:new{
            padding = self.title_padding,
            padding_top = self.title_padding + Size.padding.small,
            padding_bottom = title_tbw_padding_bottom,
            padding_left = ctoggler and ctoggler_width or self.title_padding,
            margin = self.title_margin,
            bordersize = 0,
            title_tbw,
        }
        if self.caption then
            self.caption_tap_area = titlew
        end
        title_bar = OverlapGroup:new{
            dimen = {
                w = self.width,
                h = titlew:getSize().h
            },
            titlew,
            closeb
        }
        if ctoggler then
            table.insert(title_bar, 1, ctoggler)
        end
        if self.caption and self.caption_visible then
            local caption_tbw = TextBoxWidget:new{
                text = self.caption,
                face = self.caption_face,
                width = self.width - 2*self.title_padding - 2*self.title_margin - 2*self.caption_padding,
            }
            local captionw = FrameContainer:new{
                padding = self.caption_padding,
                padding_top = 0, -- don't waste vertical room for bigger image
                padding_bottom = 0,
                margin = self.title_margin,
                bordersize = 0,
                caption_tbw,
            }
            title_bar = VerticalGroup:new{
                align = "left",
                title_bar,
                captionw
            }
        end
        title_sep = LineWidget:new{
            dimen = Geom:new{
                w = self.width,
                h = Size.line.thick,
            }
        }
        -- adjust height available to our image
        img_container_h = img_container_h - title_bar:getSize().h - title_sep:getSize().h
    end

    local max_image_h = img_container_h - self.image_padding*2
    local max_image_w = self.width - self.image_padding*2

    local rotation_angle = 0
    if self.rotated then
        -- in portrait mode, rotate according to this global setting so we are
        -- like in landscape mode
        local rotate_clockwise = DLANDSCAPE_CLOCKWISE_ROTATION
        if Screen:getWidth() > Screen:getHeight() then
            -- in landscape mode, counter-rotate landscape rotation so we are
            -- back like in portrait mode
            rotate_clockwise = not rotate_clockwise
        end
        rotation_angle = rotate_clockwise and 90 or 270
    end

    self._image_wg = ImageWidget:new{
        file = self.file,
        image = self.image,
        image_disposable = false, -- we may re-use self.image
        alpha = true,
        width = max_image_w,
        height = max_image_h,
        rotation_angle = rotation_angle,
        scale_factor = self.scale_factor,
        center_x_ratio = self._center_x_ratio,
        center_y_ratio = self._center_y_ratio,
    }

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
            padding = Size.padding.default,
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
        return "full", self.main_frame.dimen
    end)
    return true
end

function ImageViewer:onTap(_, ges)
    if ges.pos:notIntersectWith(self.main_frame.dimen) then
        self:onClose()
        return true
    end
    if self.caption_tap_area and ges.pos:intersectWith(self.caption_tap_area.dimen) then
        self.caption_visible = not self.caption_visible
        self:update()
    end
    return true
end

function ImageViewer:panBy(x, y)
    if self._image_wg then
        -- ImageWidget:panBy() returns new center ratio, so we update ours,
        -- so we'll be centered the same way when we zoom in or out
        self._center_x_ratio, self._center_y_ratio = self._image_wg:panBy(x, y)
    end
end

-- Panning events
function ImageViewer:onSwipe(_, ges)
    -- Panning with swipe is less accurate, as we don't get both coordinates,
    -- only start point + direction (with only 45� granularity)
    local direction = ges.direction
    local distance = ges.distance
    local sq_distance = math.sqrt(distance*distance/2)
    if direction == "north" then
        if ges.pos.x < Screen:getWidth() * 1/16 or ges.pos.x > Screen:getWidth() * 15/16 then
            -- allow for zooming with vertical swipe on screen sides
            -- (for devices without multi touch where pinch and spread don't work)
            local inc = ges.distance / Screen:getHeight()
            self:onZoomIn(inc)
        else
            self:panBy(0, distance)
        end
    elseif direction == "south" then
        if ges.pos.x < Screen:getWidth() * 1/16 or ges.pos.x > Screen:getWidth() * 15/16 then
            -- allow for zooming with vertical swipe on screen sides
            local dec = ges.distance / Screen:getHeight()
            self:onZoomOut(dec)
        else
            self:panBy(0, -distance)
        end
    elseif direction == "east" then
        self:panBy(-distance, 0)
    elseif direction == "west" then
        self:panBy(distance, 0)
    elseif direction == "northeast" then
        self:panBy(-sq_distance, sq_distance)
    elseif direction == "northwest" then
        self:panBy(sq_distance, sq_distance)
    elseif direction == "southeast" then
        self:panBy(-sq_distance, -sq_distance)
    elseif direction == "southwest" then
        self:panBy(sq_distance, -sq_distance)
    end
    return true
end

function ImageViewer:onHold(_, ges)
    -- Start of pan
    self._panning = true
    self._pan_relative_x = ges.pos.x
    self._pan_relative_y = ges.pos.y
    return true
end

function ImageViewer:onHoldRelease(_, ges)
    -- End of pan
    if self._panning then
        self._panning = false
        self._pan_relative_x = ges.pos.x - self._pan_relative_x
        self._pan_relative_y = ges.pos.y - self._pan_relative_y
        if math.abs(self._pan_relative_x) < self.pan_threshold and math.abs(self._pan_relative_y) < self.pan_threshold then
            -- Hold with no move (or less than pan_threshold): use this to trigger full refresh
            UIManager:setDirty(nil, "full")
        else
            self:panBy(-self._pan_relative_x, -self._pan_relative_y)
        end
    end
    return true
end

function ImageViewer:onPan(_, ges)
    self._panning = true
    self._pan_relative_x = ges.relative.x
    self._pan_relative_y = ges.relative.y
    return true
end

function ImageViewer:onPanRelease(_, ges)
    if self._panning then
        self._panning = false
        self:panBy(-self._pan_relative_x, -self._pan_relative_y)
    end
    return true
end

-- Zoom events
function ImageViewer:onZoomIn(inc)
    if self.scale_factor == 0 then
        -- Get the scale_factor made out for best fit
        self.scale_factor = self._image_wg:getScaleFactor()
    end
    if not inc then inc = 0.2 end -- default for key zoom event
    if self.scale_factor + inc < 100 then -- avoid excessive zoom
        self.scale_factor = self.scale_factor + inc
        self:update()
    end
    return true
end

function ImageViewer:onZoomOut(dec)
    if self.scale_factor == 0 then
        -- Get the scale_factor made out for best fit
        self.scale_factor = self._image_wg:getScaleFactor()
    end
    if not dec then dec = 0.2 end -- default for key zoom event
    if self.scale_factor - dec > 0.01 then -- avoid excessive unzoom
        self.scale_factor = self.scale_factor - dec
        self:update()
    end
    return true
end

function ImageViewer:onSpread(_, ges)
    -- We get the position where spread was done
    -- First, get center ratio we would have had if we did a pan to there,
    -- so we can have the zoom centered on there
    if self._image_wg then
        self._center_x_ratio, self._center_y_ratio = self._image_wg:getPanByCenterRatio(ges.pos.x - Screen:getWidth()/2, ges.pos.y - Screen:getHeight()/2)
    end
    -- Set some zoom increase value from pinch distance
    local inc = ges.distance / Screen:getWidth()
    self:onZoomIn(inc)
    return true
end

function ImageViewer:onPinch(_, ges)
    -- With Pinch, unlike Spread, it feels more natural if we keep the same center point.
    -- Set some zoom decrease value from pinch distance
    local dec = ges.distance / Screen:getWidth()
    self:onZoomOut(dec)
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
