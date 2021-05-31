--[[--
ImageViewer displays an image with some simple manipulation options.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local ImageViewer = InputContainer:new{
    -- Allow for providing same different input types as ImageWidget :
    -- a path to a file
    file = nil,
    -- or an already made BlitBuffer (ie: made by Mupdf.renderImageFile())
    image = nil,
    -- whether the provided BlitBuffer should be free'd. Usually true,
    -- unless our caller wants to reuse the image it provided
    image_disposable = true,

    -- 'image' can alternatively be a table (list) of multiple BlitBuffers
    -- (or functions returning BlitBuffers).
    -- The table will have its .free() called onClose according to
    -- the image_disposable provided here.
    -- Each BlitBuffer in the table (or returned by functions) will be free'd
    -- if the table itself has an image_disposable field set to true.

    -- With images list, when switching image, whether to keep previous
    -- image pan & zoom
    images_keep_pan_and_zoom = true,

    fullscreen = false, -- false will add some padding around widget (so footer can be visible)
    with_title_bar = true,
    title_text = _("Viewing image"), -- default title text
    -- A caption can be toggled with tap on title_text (so, it needs with_title_bar=true):
    caption = nil,
    caption_visible = true, -- caption visible by default
    caption_tap_area = nil,
    -- Start with buttons hidden (tap on screen will toggle their visibility)
    buttons_visible = false,

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
    _images_list = nil,
    _images_list_disposable = nil,

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
        local diagonal = math.sqrt( math.pow(Screen:getWidth(), 2) + math.pow(Screen:getHeight(), 2) )
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
            -- Allow saving the image as Screenshoter does (with two fingers tap,
            -- swipe being reserved for panning - on non multitouch Devices, this
            -- is also available with a tap in the bottom left corner)
            TapDiagonal = { GestureRange:new{ ges = "two_finger_tap",
                    scale = {diagonal - Screen:scaleBySize(200), diagonal}, rate = 1.0,
                }
            },
        }
    end
    if self.fullscreen then
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    end

    -- if self.image is a list of images, swap it with first image to be displayed
    if type(self.image) == "table" then
        self._images_list = self.image
        self.image = self._images_list[1]
        if type(self.image) == "function" then
            self.image = self.image()
        end
        self._images_list_cur = 1
        self._images_list_nb = #self._images_list
        self._images_orig_scale_factor = self.scale_factor
        -- also swap disposable status
        self._images_list_disposable = self.image_disposable
        self.image_disposable = self._images_list.image_disposable
    end

    -- Widget layout
    if self._scale_to_fit == nil then -- initialize our toggle
        self._scale_to_fit = self.scale_factor == 0
    end
    local orig_dimen = Geom:new{}
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

    -- Init the buttons no matter what
    local buttons = {
        {
            {
                id = "scale",
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
                id = "rotate",
                text = self.rotated and _("No rotation") or _("Rotate"),
                callback = function()
                    self.rotated = not self.rotated and true or false
                    self:update()
                end,
            },
            {
                id = "close",
                text = _("Close"),
                callback = function()
                    self:onClose()
                end,
            },
        },
    }
    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self.button_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    }

    if self.buttons_visible then
        self.button_table_size = self.button_table:getSize().h
    else
        self.button_table_size = 0
    end

    -- height available to our image
    self.img_container_h = self.height - self.button_table_size

    -- Init the title bar and its components no matter what
    -- Toggler (white arrow) for caption, on the left of title
    local ctoggler_text
    if self.caption_visible then
        ctoggler_text = "▽ " -- white arrow (nicer than smaller black arrow ▼)
    else
        ctoggler_text = "▷ " -- white arrow (nicer than smaller black arrow ►)
    end
    self.ctoggler_tw = TextWidget:new{
        text = ctoggler_text,
        face = self.title_face,
    }
    -- paddings chosen to align nicely with titlew
    self.ctoggler = FrameContainer:new{
        bordersize = 0,
        padding = self.title_padding,
        padding_top = self.title_padding + Size.padding.small,
        padding_right = 0,
        self.ctoggler_tw,
    }
    if self.caption then
        self.ctoggler_width = self.ctoggler:getSize().w
    else
        self.ctoggler_width = 0
    end
    self.closeb = CloseButton:new{ window = self, padding_top = Size.padding.tiny, }
    self.title_tbw = TextBoxWidget:new{
        text = self.title_text,
        face = self.title_face,
        -- bold = true, -- we're already using a bold font
        width = self.width - 2*self.title_padding - 2*self.title_margin - self.closeb:getSize().w - self.ctoggler_width,
    }
    local title_tbw_padding_bottom = self.title_padding + Size.padding.small
    if self.caption and self.caption_visible then
        title_tbw_padding_bottom = 0 -- save room between title and caption
    end
    self.titlew = FrameContainer:new{
        padding = self.title_padding,
        padding_top = self.title_padding + Size.padding.small,
        padding_bottom = title_tbw_padding_bottom,
        padding_left = self.caption and self.ctoggler_width or self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        self.title_tbw,
    }
    if self.caption then
        self.caption_tap_area = self.titlew
    end
    self.title_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.titlew:getSize().h
        },
        self.titlew,
        self.closeb
    }
    if self.caption then
        table.insert(self.title_bar, 1, self.ctoggler)
    end
    -- Init the caption no matter what
    self.caption_tbw = TextBoxWidget:new{
        text = self.caption or _("N/A"),
        face = self.caption_face,
        width = self.width - 2*self.title_padding - 2*self.title_margin - 2*self.caption_padding,
    }
    local captionw = FrameContainer:new{
        padding = self.caption_padding,
        padding_top = 0, -- don't waste vertical room for bigger image
        padding_bottom = 0,
        margin = self.title_margin,
        bordersize = 0,
        self.caption_tbw,
    }
    self.captioned_title_bar = VerticalGroup:new{
        align = "left",
        self.title_bar,
        captionw
    }

    if self.caption and self.caption_visible then
        self.full_title_bar = self.captioned_title_bar
    else
        self.full_title_bar = self.title_bar
    end
    self.title_sep = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    -- adjust height available to our image
    if self.with_title_bar then
        self.img_container_h = self.img_container_h - self.full_title_bar:getSize().h - self.title_sep:getSize().h
    end

    -- Init the progress bar no matter what
    -- progress bar
    local percent = 1
    if self._images_list and self._images_list_nb > 1 then
        percent = (self._images_list_cur - 1) / (self._images_list_nb - 1)
    end
    self.progress_bar = ProgressWidget:new{
        width = self.width - 2*self.button_padding,
        height = Screen:scaleBySize(5),
        percentage = percent,
        margin_h = 0,
        margin_v = 0,
        radius = 0,
        ticks = nil,
        last = nil,
    }
    self.progress_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.progress_bar:getSize().h + Size.padding.small,
        },
        self.progress_bar
    }

    if self._images_list then
        self.img_container_h = self.img_container_h - self.progress_container:getSize().h
    end

    -- Instantiate self._image_wg & self.image_container
    self:_new_image_wg()

    local frame_elements = VerticalGroup:new{ align = "left" }
    if self.with_title_bar then
        table.insert(frame_elements, self.full_title_bar)
        table.insert(frame_elements, self.title_sep)
    end
    table.insert(frame_elements, self.image_container)
    if self._images_list then
        table.insert(frame_elements, self.progress_container)
    end
    if self.buttons_visible then
        table.insert(frame_elements, self.button_container)
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
    -- NOTE: We use UI instead of partial, because we do NOT want to end up using a REAGL waveform...
    -- NOTE: Disabling dithering here makes for a perfect test-case of how well it works:
    --       page turns will show color quantization artefacts (i.e., banding) like crazy,
    --       while a long touch will trigger a dithered, flashing full-refresh that'll make everything shiny :).
    self.dithered = true
    UIManager:setDirty(self, function()
        local update_region = self.main_frame.dimen:combine(orig_dimen)
        return "ui", update_region, true
    end)
end

function ImageViewer:_clean_image_wg()
    -- To be called before re-using / disposing of self._image_wg,
    -- otherwise resources used by its blitbuffer won't be free'd
    if self._image_wg then
        logger.dbg("ImageViewer:_clean_image_wg")
        self._image_wg:free()
        self._image_wg = nil
    end
end

-- Used in init & update to instantiate a new ImageWidget & its container
function ImageViewer:_new_image_wg()
    -- If no buttons and no title are shown, use the full screen
    local max_image_h = self.img_container_h
    local max_image_w = self.width
    -- Otherwise, add paddings around image
    if self.buttons_visible or self.with_title_bar then
        max_image_h = self.img_container_h - self.image_padding*2
        max_image_w = self.width - self.image_padding*2
    end

    local rotation_angle = 0
    if self.rotated then
        -- in portrait mode, rotate according to this global setting so we are
        -- like in landscape mode
        -- NOTE: This is the sole user of this legacy global left!
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
        alpha = true, -- we might be showing images with an alpha channel (e.g., from Wikipedia)
        width = max_image_w,
        height = max_image_h,
        rotation_angle = rotation_angle,
        scale_factor = self.scale_factor,
        center_x_ratio = self._center_x_ratio,
        center_y_ratio = self._center_y_ratio,
    }

    self.image_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.img_container_h,
        },
        self._image_wg,
    }
end

function ImageViewer:update()
    -- Free our ImageWidget, which is the only thing we'll replace (e.g., leave the TextBoxWidgets alone).
    self:_clean_image_wg()

    -- Update window geometry
    local orig_dimen = self.main_frame.dimen
    if self.fullscreen then
        self.height = Screen:getHeight()
        self.width = Screen:getWidth()
    else
        self.height = Screen:getHeight() - Screen:scaleBySize(40)
        self.width = Screen:getWidth() - Screen:scaleBySize(40)
    end

    -- Update Buttons
    if self.buttons_visible then
        local scale_btn = self.button_table:getButtonById("scale")
        scale_btn:setText(self._scale_to_fit and _("Original size") or _("Scale"), scale_btn.width)
        local rotate_btn = self.button_table:getButtonById("rotate")
        rotate_btn:setText(self.rotated and _("No rotation") or _("Rotate"), rotate_btn.width)

        self.button_table_size = self.button_table:getSize().h
    else
        self.button_table_size = 0
    end

    -- height available to our image
    self.img_container_h = self.height - self.button_table_size

    -- Update the title bar
    if self.with_title_bar then
        self.ctoggler_tw:setText(self.caption_visible and "▽ " or "▷ ")

        -- Padding is dynamic...
        local title_tbw_padding_bottom = self.title_padding + Size.padding.small
        if self.caption and self.caption_visible then
            title_tbw_padding_bottom = 0
        end
        self.titlew.padding_bottom = title_tbw_padding_bottom
        self.title_bar.dimen.h = self.titlew:getSize().h

        if self.caption and self.caption_visible then
            self.full_title_bar = self.captioned_title_bar
        else
            self.full_title_bar = self.title_bar
        end

        self.img_container_h = self.img_container_h - self.full_title_bar:getSize().h - self.title_sep:getSize().h
    end

    -- Update the progress bar
    if self._images_list then
        local percent = 1
        if self._images_list_nb > 1 then
            percent = (self._images_list_cur - 1) / (self._images_list_nb - 1)
        end

        self.progress_bar:setPercentage(percent)

        self.img_container_h = self.img_container_h - self.progress_container:getSize().h
    end

    -- Update the image widget itself
    self:_new_image_wg()

    -- Update the final layout
    local frame_elements = VerticalGroup:new{ align = "left" }
    if self.with_title_bar then
        table.insert(frame_elements, self.full_title_bar)
        table.insert(frame_elements, self.title_sep)
    end
    table.insert(frame_elements, self.image_container)
    if self._images_list then
        table.insert(frame_elements, self.progress_container)
    end
    if self.buttons_visible then
        table.insert(frame_elements, self.button_container)
    end

    self.main_frame.radius = not self.fullscreen and 8 or nil
    self.main_frame[1] = frame_elements

    self.dithered = true
    UIManager:setDirty(self, function()
        local update_region = self.main_frame.dimen:combine(orig_dimen)
        return "ui", update_region, true
    end)
end

function ImageViewer:onShow()
    self.dithered = true
    UIManager:setDirty(self, function()
        return "full", self.main_frame.dimen, true
    end)
    return true
end

function ImageViewer:switchToImageNum(image_num)
    if self.image and self.image_disposable and self.image.free then
        logger.dbg("ImageViewer:switchToImageNum: free self.image", self.image)
        self.image:free()
        self.image = nil
    end
    self.image = self._images_list[image_num]
    if type(self.image) == "function" then
        self.image = self.image()
    end
    self._images_list_cur = image_num
    if not self.images_keep_pan_and_zoom then
        self._center_x_ratio = 0.5
        self._center_y_ratio = 0.5
        self.scale_factor = self._images_orig_scale_factor
    end
    self:update()
end

function ImageViewer:onTap(_, ges)
    if ges.pos:notIntersectWith(self.main_frame.dimen) then
        self:onClose()
        return true
    end
    if not Device:hasMultitouch() then
        -- Allow saving screenshot with tap in bottom left corner
        if not self.buttons_visible and ges.pos.x < Screen:getWidth()/10 and ges.pos.y > Screen:getHeight()*9/10 then
            return self:onSaveImageView()
        end
    end
    if self.with_title_bar and self.caption_tap_area and ges.pos:intersectWith(self.caption_tap_area.dimen) then
        self.caption_visible = not self.caption_visible
        self:update()
        return true
    end
    if self._images_list then
        -- If it's a list of image (e.g. animated gifs), tap left/right 1/3 of screen to navigate
        local show_prev_image, show_next_image
        if ges.pos.x < Screen:getWidth()/3 then
            show_prev_image = not BD.mirroredUILayout()
            show_next_image = BD.mirroredUILayout()
        elseif ges.pos.x > Screen:getWidth()*2/3 then
            show_prev_image = BD.mirroredUILayout()
            show_next_image = not BD.mirroredUILayout()
        end
        if show_prev_image then
            if self._images_list_cur > 1 then
                self:switchToImageNum(self._images_list_cur - 1)
            end
        elseif show_next_image then
            if self._images_list_cur < self._images_list_nb then
                self:switchToImageNum(self._images_list_cur + 1)
            end
        else -- toggle buttons when tap on middle 1/3 of screen width
            self.buttons_visible = not self.buttons_visible
            self:update()
        end
    else
        -- No image list: tap on any part of screen toggles buttons visibility
        self.buttons_visible = not self.buttons_visible
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
        elseif self.scale_factor == 0 then
            -- When scaled to fit (on initial launch, or after one has tapped
            -- "Scale"), as we are then sure that there is no use for panning,
            -- allow swipe south to close the widget.
            self:onClose()
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
            self.dithered = true
            UIManager:setDirty(nil, "full", nil, true)
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

function ImageViewer:onTapDiagonal()
    return self:onSaveImageView()
end

function ImageViewer:onSaveImageView()
    -- Similar behaviour as in Screenshoter:onScreenshot()
    -- We save the currently displayed blitbuffer (panned or zoomed)
    -- after getting fullscreen and removing UI elements if needed.
    local screenshots_dir = G_reader_settings:readSetting("screenshot_dir")
    if not screenshots_dir then
        screenshots_dir = DataStorage:getDataDir() .. "/screenshots/"
    end
    self.screenshot_fn_fmt = screenshots_dir .. "ImageViewer_%Y-%m-%d_%H%M%S.png"
    local screenshot_name = os.date(self.screenshot_fn_fmt)
    local restore_settings_func
    if self.with_title_bar or self.buttons_visible or not self.fullscreen then
        local with_title_bar = self.with_title_bar
        local buttons_visible = self.buttons_visible
        local fullscreen = self.fullscreen
        restore_settings_func = function()
            self.with_title_bar = with_title_bar
            self.buttons_visible = buttons_visible
            self.fullscreen = fullscreen
            self:update()
        end
        self.with_title_bar = false
        self.buttons_visible = false
        self.fullscreen = true
        self:update()
        UIManager:forceRePaint()
    end
    Screen:shot(screenshot_name)
    local widget = ConfirmBox:new{
        text = T( _("Saved screenshot to %1.\nWould you like to set it as screensaver?"), BD.filepath(screenshot_name)),
        ok_text = _("Yes"),
        ok_callback = function()
            G_reader_settings:saveSetting("screensaver_type", "image_file")
            G_reader_settings:saveSetting("screensaver_image", screenshot_name)
            if restore_settings_func then
                restore_settings_func()
            end
        end,
        cancel_text = _("No"),
        cancel_callback = function()
            if restore_settings_func then
                restore_settings_func()
            end
        end
    }
    UIManager:show(widget)
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
    -- Our ImageWidget (self._image_wg) is always a proper child widget, so it'll receive this event,
    -- and attempt to free its resources accordingly.
    -- But, if it didn't have to touch the original BB (self.image) passed to ImageViewer (e.g., no scaling needed),
    -- it will *re-use* self.image, and flag it as non-disposable, meaning it will not have been free'd earlier.
    -- Since we're the ones who ultimately truly know whether we should dispose of self.image or not, do that now ;).
    if self.image and self.image_disposable and self.image.free then
        logger.dbg("ImageViewer:onCloseWidget: free self.image", self.image)
        self.image:free()
        self.image = nil
    end
    -- also clean _images_list if it provides a method for that
    if self._images_list and self._images_list_disposable and self._images_list.free then
        logger.dbg("ImageViewer:onCloseWidget: free self._images_list", self._images_list)
        self._images_list:free()
    end

    -- Those, on the other hand, are always initialized, but may not actually be in our widget tree right now,
    -- depending on what we needed to show, so they might not get sent a CloseWidget event.
    -- They (and their FFI/C resources) would eventually get released by the GC, but let's be pedantic ;).
    if not self.with_title_bar then
        self.captioned_title_bar:free()
    end
    if not self.caption then
        self.ctoggler:free()
    end
    if not self._images_list then
        self.progress_container:free()
    end
    if not self.buttons_visible then
        self.button_container:free()
    end

    -- NOTE: Assume there's no image beneath us, so, no dithering request
    UIManager:setDirty(nil, function()
        return "flashui", self.main_frame.dimen
    end)
end

return ImageViewer
