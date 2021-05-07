--[[--
ImageWidget shows an image from a file or memory

Show image from file example:

        UIManager:show(ImageWidget:new{
            file = "resources/koreader.png",
            -- Make sure alpha is set to true if png has transparent background
            -- alpha = true,
        })


Show image from memory example:

        UIManager:show(ImageWidget:new{
            -- bitmap_buffer should be a block of memory that holds the raw
            -- uncompressed bitmap.
            image = bitmap_buffer,
        })

]]

local Blitbuffer = require("ffi/blitbuffer")
local Cache = require("cache")
local Geom = require("ui/geometry")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local logger = require("logger")

-- DPI_SCALE can't change without a restart, so let's compute it now
local function get_dpi_scale()
    local size_scale = math.min(Screen:getWidth(), Screen:getHeight())/600
    local dpi_scale = Screen:getDPI() / 167
    return math.pow(2, math.max(0, math.log((size_scale+dpi_scale)/2)/0.69))
end
local DPI_SCALE = get_dpi_scale()

local ImageCache = Cache:new{
    -- 8 MiB of image cache, with 128 slots
    -- Overwhelmingly used for our icons, which are tiny in size, and not very numerous (< 100),
    -- but also by ImageViewer (on files, which we never do), and ScreenSaver (again, on image files, but not covers),
    -- hence the leeway.
    size = 8 * 1024 * 1024,
    avg_itemsize = 64 * 1024,
    -- Rely on our FFI finalizer to free the BBs on GC
    enable_eviction_cb = false,
}

local ImageWidget = Widget:new{
    -- Can be provided with a path to a file
    file = nil,
    -- or an already made BlitBuffer (ie: made by RenderImage)
    image = nil,

    -- Whether BlitBuffer rendered from file should be cached
    file_do_cache = true,
    -- Whether provided BlitBuffer can be modified by us and SHOULD be free() by us,
    -- normally true unless our caller wants to reuse its provided image
    image_disposable = true,

    -- Width and height of container, to limit rendering to this area
    -- (if provided, and scale_factor is nil, image will be resized to
    -- these width and height without regards to original aspect ratio)
    width = nil,
    height = nil,

    hide = nil, -- to not be painted

    -- Settings that apply at paintTo() time
    invert = nil,
    dim = nil,
    alpha = false, -- honors alpha values from the image
    is_icon = false, -- set to true by sub-class IconWidget

    -- When rotation_angle is not 0, native image is rotated by this angle
    -- before scaling.
    rotation_angle = 0,

    -- If scale_for_dpi is true image will be rescaled according to screen dpi
    scale_for_dpi = false,

    -- When scale_factor is not nil, native image is scaled by this factor
    -- (if scale_factor == 1, native image size is kept)
    -- Special case : scale_factor == 0 : image will be scaled to best fit provided
    -- width and height, keeping aspect ratio (scale_factor will be updated
    -- from 0 to the factor used at _render() time)
    scale_factor = nil,

    -- Whether to use former blitbuffer:scale() (default to using MuPDF)
    use_legacy_image_scaling = G_reader_settings:isTrue("legacy_image_scaling"),

    -- For initial positioning, if (possibly scaled) image overflows width/height
    center_x_ratio = 0.5, -- default is centered on image's center
    center_y_ratio = 0.5,

    -- For pan & zoom management:
    -- offsets to use in blitFrom()
    _offset_x = 0,
    _offset_y = 0,
    -- limits to center_x_ratio variation around 0.5 (0.5 +/- these values)
    -- to keep image centered (0 means center_x_ratio will be forced to 0.5)
    _max_off_center_x_ratio = 0,
    _max_off_center_y_ratio = 0,

    -- So we can reset self.scale_factor to its initial value in free(), in
    -- case this same object is free'd but re-used and and re-render'ed
    _initial_scale_factor = nil,

    _bb = nil,
    _bb_disposable = true, -- whether we should free() our _bb
    _bb_w = nil,
    _bb_h = nil,
}

function ImageWidget:_loadimage()
    self._bb = self.image
    -- don't touch or free if caller doesn't want that
    self._bb_disposable = self.image_disposable
end

function ImageWidget:_loadfile()
    local itype = string.lower(string.match(self.file, ".+%.([^.]+)") or "")
    if itype == "svg" or itype == "png" or itype == "jpg" or itype == "jpeg"
            or itype == "gif" or itype == "tiff" or itype == "tif" then
        -- In our use cases for files (icons), we either provide width and height,
        -- or just scale_for_dpi, and scale_factor should stay nil.
        -- Other combinations will result in double scaling, and unexpected results.
        -- We should anyway only give self.width and self.height to renderImageFile(),
        -- and use them in cache hash, when self.scale_factor is nil, when we are sure
        -- we don't need to keep aspect ratio.
        local width, height
        if self.scale_factor == nil then
            width = self.width
            height = self.height
        end
        local hash = "image|"..self.file.."|"..(width or "").."|"..(height or "")
        -- Do the scaling for DPI here, so it can be cached and not re-done
        -- each time in _render() (but not if scale_factor, to avoid double scaling)
        local scale_for_dpi_here = false
        if self.scale_for_dpi and DPI_SCALE ~= 1 and not self.scale_factor then
            scale_for_dpi_here = true -- we'll do it before caching
            hash = hash .. "|d"
            self.already_scaled_for_dpi = true -- so we don't do it again in _render()
        end
        local cached = ImageCache:check(hash)
        if cached then
            -- hit cache
            self._bb = cached.bb
            self._bb_disposable = false -- don't touch or free a cached _bb
            self._is_straight_alpha = cached.is_straight_alpha
        else
            if itype == "svg" then
                local zoom
                if scale_for_dpi_here then
                    zoom = DPI_SCALE
                elseif self.scale_factor == 0 then
                    -- renderSVGImageFile() keeps aspect ratio by default
                    width = self.width
                    height = self.height
                end
                -- If NanoSVG is used by renderSVGImageFile, we'll get self._is_straight_alpha=true,
                -- and paintTo() must use alphablitFrom() instead of pmulalphablitFrom() (which is
                -- fine for everything MuPDF renders out)
                self._bb, self._is_straight_alpha = RenderImage:renderSVGImageFile(self.file, width, height, zoom)
            else
                self._bb = RenderImage:renderImageFile(self.file, false, width, height)
                if scale_for_dpi_here then
                    local bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()
                    self._bb = RenderImage:scaleBlitBuffer(self._bb, math.floor(bb_w * DPI_SCALE), math.floor(bb_h * DPI_SCALE))
                end
            end

            -- Now, if that was *also* one of our icons, we haven't explicitly requested to keep the alpha channel intact,
            -- and it actually has an alpha channel, compose it against a background-colored BB now, and cache *that*.
            -- This helps us avoid repeating alpha-blending steps down the line,
            -- and also ensures icon highlights/unhighlights behave sensibly.
            if self.is_icon and not self.alpha then
                local bbtype = self._bb:getType()
                if bbtype == Blitbuffer.TYPE_BB8A or bbtype == Blitbuffer.TYPE_BBRGB32 then
                    local icon_bb = Blitbuffer.new(self._bb.w, self._bb.h, Screen.bb:getType())
                    --- @note: Should match the background color. Which is currently hard-coded as white ;).
                    ---        See the note below in paintTo for how to make the dim flag behave in case
                    ---        this no longer actually is white ;).
                    icon_bb:fill(Blitbuffer.COLOR_WHITE)

                    -- And now simply compose the icon on top of that, with dithering if necessary
                    -- Remembering that NanoSVG feeds us straight alpha, unlike MµPDF
                    if self._is_straight_alpha then
                        if Screen.sw_dithering then
                            icon_bb:ditheralphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        else
                            icon_bb:alphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        end
                    else
                        if Screen.sw_dithering then
                            icon_bb:ditherpmulalphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        else
                            icon_bb:pmulalphablitFrom(self._bb, 0, 0, 0, 0, icon_bb.w, icon_bb.h)
                        end
                    end

                    -- Free the original icon w/ an alpha-channel, keep the flattened one
                    self._bb:free()
                    self._bb = icon_bb

                    -- There's no longer an alpha channel ;)
                    self._is_straight_alpha = nil
                end
            end

            if not self.file_do_cache then
                self._bb_disposable = true -- we made it, we can modify and free it
            else
                self._bb_disposable = false -- don't touch or free a cached _bb
                -- cache this image
                logger.dbg("cache", hash)
                cached = {
                    bb = self._bb,
                    is_straight_alpha = self._is_straight_alpha,
                }
                ImageCache:insert(hash, cached, tonumber(cached.bb.stride) * cached.bb.h)
            end
        end
    else
        error("Image file type not supported.")
    end
end

function ImageWidget:_render()
    if self._bb then -- already rendered
        return
    end
    logger.dbg("ImageWidget: _render'ing", self.file and self.file or "data", self.width, self.height)
    if self.image then
        self:_loadimage()
    elseif self.file then
        self:_loadfile()
    else
        error("cannot render image")
    end

    -- Store initial scale factor
    self._initial_scale_factor = self.scale_factor

    -- First, rotation
    if self.rotation_angle ~= 0 then
        -- Allow for easy switch to former scaling via blitbuffer methods
        if self.use_legacy_image_scaling then
            if not self._bb_disposable then
                -- we can't modify _bb, make a copy
                self._bb = self._bb:copy()
                self._bb_disposable = true -- new object will have to be freed
            end
            self._bb:rotate(self.rotation_angle) -- rotate in-place
        else
            -- If we use MuPDF for scaling, we can't use bb:rotate() anymore,
            -- as it only flags rotation in the blitbuffer and rotation is dealt
            -- with at painting time. MuPDF does not like such a blitbuffer, and
            -- we get corrupted images when using it for scaling such blitbuffers.
            -- We need to make a real new blitbuffer with rotated content:
            local rot_bb = self._bb:rotatedCopy(self.rotation_angle)
            -- We made a new blitbuffer, we need to explicitely free
            -- the old one to not leak memory
            if self._bb_disposable then
                self._bb:free()
            end
            self._bb = rot_bb
            self._bb_disposable = true -- new object will have to be freed
        end
    end

    local bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()

    -- scale_for_dpi setting: update scale_factor (even if not set) with it
    if self.scale_for_dpi and not self.already_scaled_for_dpi then
        if self.scale_factor == nil then
            self.scale_factor = 1
        end
        self.scale_factor = self.scale_factor * DPI_SCALE
    end

    -- scale to best fit container : compute scale_factor for that
    if self.scale_factor == 0 then
        if self.width and self.height then
            self.scale_factor = math.min(self.width / bb_w, self.height / bb_h)
            logger.dbg("ImageWidget: scale to fit, setting scale_factor to", self.scale_factor)
        else
            -- no width and height provided (inconsistencies from caller),
            self.scale_factor = 1 -- native image size
        end
    end

    -- replace blitbuffer with a resized one if needed
    if self.scale_factor == nil then
        -- no scaling, but strech to width and height, only if provided and needed
        if self.width and self.height and (self.width ~= bb_w or self.height ~= bb_h) then
            logger.dbg("ImageWidget: stretching")
            self._bb = RenderImage:scaleBlitBuffer(self._bb, self.width, self.height, self._bb_disposable)
            self._bb_disposable = true -- new bb will have to be freed
        end
    elseif self.scale_factor ~= 1 then
        -- scale by scale_factor (not needed if scale_factor == 1)
        logger.dbg("ImageWidget: scaling by", self.scale_factor)
        self._bb = RenderImage:scaleBlitBuffer(self._bb, bb_w * self.scale_factor, bb_h * self.scale_factor, self._bb_disposable)
        self._bb_disposable = true -- new bb will have to be freed
    end
    bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()

    -- deal with positioning
    if self.width and self.height then
        -- if image is bigger than paint area, allow center_ratio variation
        -- around 0.5 so we can pan till image border
        if bb_w > self.width then
            self._max_off_center_x_ratio = 0.5 - self.width/2 / bb_w
        end
        if bb_h > self.height then
            self._max_off_center_y_ratio = 0.5 - self.height/2 / bb_h
        end
        -- correct provided center ratio if out limits
        if self.center_x_ratio < 0.5 - self._max_off_center_x_ratio then
            self.center_x_ratio = 0.5 - self._max_off_center_x_ratio
        elseif self.center_x_ratio > 0.5 + self._max_off_center_x_ratio then
            self.center_x_ratio = 0.5 + self._max_off_center_x_ratio
        end
        if self.center_y_ratio < 0.5 - self._max_off_center_y_ratio then
            self.center_y_ratio = 0.5 - self._max_off_center_y_ratio
        elseif self.center_y_ratio > 0.5 + self._max_off_center_y_ratio then
            self.center_y_ratio = 0.5 + self._max_off_center_y_ratio
        end
        -- set offsets to reflect center ratio, whether oversized or not
        self._offset_x = self.center_x_ratio * bb_w - self.width/2
        self._offset_y = self.center_y_ratio * bb_h - self.height/2
        logger.dbg("ImageWidget: initial offsets", self._offset_x, self._offset_y)
    end

    -- store final bb's width and height
    self._bb_w = bb_w
    self._bb_h = bb_h
end

function ImageWidget:getSize()
    self:_render()
    -- getSize will be used by the widget stack for centering/padding
    if not self.width or not self.height then
        -- no width/height provided, return bb size to let widget stack do the centering
        return Geom:new{ w = self._bb:getWidth(), h = self._bb:getHeight() }
    end
    -- if width or height provided, return them as is, even if image is smaller
    -- and would be centered: we'll do the centering ourselves with offsets
    return Geom:new{ w = self.width, h = self.height }
end

function ImageWidget:getScaleFactor()
    -- return computed scale_factor, useful if 0 (scale to fit) was used
    return self.scale_factor
end

function ImageWidget:getPanByCenterRatio(x, y)
    -- returns center ratio (without limits check) we would get with this panBy
    local center_x_ratio = (x + self._offset_x + self.width/2) / self._bb_w
    local center_y_ratio = (y + self._offset_y + self.height/2) / self._bb_h
    return center_x_ratio, center_y_ratio
end

function ImageWidget:panBy(x, y)
    -- update center ratio from new offset
    self.center_x_ratio = (x + self._offset_x + self.width/2) / self._bb_w
    self.center_y_ratio = (y + self._offset_y + self.height/2) / self._bb_h
    -- correct new center ratio if out limits
    if self.center_x_ratio < 0.5 - self._max_off_center_x_ratio then
        self.center_x_ratio = 0.5 - self._max_off_center_x_ratio
    elseif self.center_x_ratio > 0.5 + self._max_off_center_x_ratio then
        self.center_x_ratio = 0.5 + self._max_off_center_x_ratio
    end
    if self.center_y_ratio < 0.5 - self._max_off_center_y_ratio then
        self.center_y_ratio = 0.5 - self._max_off_center_y_ratio
    elseif self.center_y_ratio > 0.5 + self._max_off_center_y_ratio then
        self.center_y_ratio = 0.5 + self._max_off_center_y_ratio
    end
    -- new offsets that reflect this new center ratio
    local new_offset_x = self.center_x_ratio * self._bb_w - self.width/2
    local new_offset_y = self.center_y_ratio * self._bb_h - self.height/2
    -- only trigger screen refresh it we actually pan
    if new_offset_x ~= self._offset_x or new_offset_y ~= self._offset_y then
        self._offset_x = new_offset_x
        self._offset_y = new_offset_y
        self.dithered = true
        UIManager:setDirty("all", function()
            return "ui", self.dimen, true
        end)
    end
    -- return new center ratio, so caller can use them later to create a new
    -- ImageWidget with a different scale_factor, while keeping center point
    return self.center_x_ratio, self.center_y_ratio
end

function ImageWidget:paintTo(bb, x, y)
    if self.hide then return end
    -- self:_render is called in getSize method
    local size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = size.w,
        h = size.h
    }
    logger.dbg("blitFrom", x, y, self._offset_x, self._offset_y, size.w, size.h)
    local do_alpha = false
    if self.alpha == true then
        -- Only actually try to alpha-blend if the image really has an alpha channel...
        local bbtype = self._bb:getType()
        if bbtype == Blitbuffer.TYPE_BB8A or bbtype == Blitbuffer.TYPE_BBRGB32 then
            do_alpha = true
        end
    end
    if do_alpha then
        --- @note: MuPDF feeds us premultiplied alpha (and we don't care w/ GifLib, as alpha is all or nothing),
        ---        while NanoSVG feeds us straight alpha.
        ---        SVG icons are currently flattened at caching time, so we'll only go through the straight alpha
        ---        codepath for non-icons SVGs.
        if self._is_straight_alpha then
            --- @note: Our icons are already dithered properly, either at encoding time, or at caching time.
            if Screen.sw_dithering and not self.is_icon then
                bb:ditheralphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            else
                bb:alphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            end
        else
            if Screen.sw_dithering and not self.is_icon then
                bb:ditherpmulalphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            else
                bb:pmulalphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
            end
        end
    else
        if Screen.sw_dithering and not self.is_icon then
            bb:ditherblitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
        else
            bb:blitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
        end
    end
    if self.invert then
        bb:invertRect(x, y, size.w, size.h)
    end
    --- @note: This is mainly geared at black icons/text on a *white* background,
    ---        otherwise the background color itself will shift.
    ---        i.e., this actually *lightens* the rectangle, but since it's aimed at black,
    ---        it makes it gray, dimmer; hence the name.
    ---        TL;DR: If we one day want that to work for icons on a non-white background,
    ---        a better solution would probably be to take the icon pixmap as an alpha-mask,
    ---        (which simply involves blending it onto a white background, then inverting the result),
    ---        and colorBlit it a dim gray onto the target bb.
    ---        This would require the *original* transparent icon, not the flattened one in the cache.
    ---        c.f., https://github.com/koreader/koreader/pull/6937#issuecomment-748372429 for a PoC
    if self.dim then
        bb:dimRect(x, y, size.w, size.h)
    end
    -- In night mode, invert all rendered images, so the original is
    -- displayed when the whole screen is inverted by night mode.
    -- Except for our *black & white* icons: we do *NOT* want to invert them again:
    -- they should match the UI's text/backgound.
    --- @note: As for *color* icons, we really *ought* to invert them here,
    ---        but we currently don't, as we don't really trickle down
    ---        a way to discriminate them from the B&W ones.
    ---        Currently, this is *only* the KOReader icon in Help, AFAIK.
    if Screen.night_mode and not self.is_icon then
        bb:invertRect(x, y, size.w, size.h)
    end
end

-- This will normally be called by our WidgetContainer:free()
-- But it SHOULD explicitely be called if we are getting replaced
-- (ie: in some other widget's update()), to not leak memory with
-- BlitBuffer zombies
function ImageWidget:free()
    --print("ImageWidget:free on", self, "for BB?", self._bb, self._bb_disposable)
    if self._bb and self._bb_disposable and self._bb.free then
        self._bb:free()
        self._bb = nil
    end
    -- reset self.scale_factor to its initial value, in case
    -- self._render() is called again (happens with iconbutton,
    -- avoids x2 x2 x2 if high dpi and icon scaled x8 after 3 calls)
    self.scale_factor = self._initial_scale_factor
end

function ImageWidget:onCloseWidget()
    -- free when UIManager:close() was called
    self:free()
end

return ImageWidget
