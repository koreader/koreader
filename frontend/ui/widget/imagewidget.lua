--[[--
ImageWidget shows an image from a file or memory

Show image from file example:

        UIManager:show(ImageWidget:new{
            file = "resources/info-i.png",
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

local Widget = require("ui/widget/widget")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local CacheItem = require("cacheitem")
local Mupdf = require("ffi/mupdf")
local Geom = require("ui/geometry")
local Cache = require("cache")
local logger = require("logger")

local ImageCache = Cache:new{
    max_memsize = 2*1024*1024, -- 2M of image cache
    current_memsize = 0,
    cache = {},
    -- this will hold the LRU order of the cache
    cache_order = {}
}

local ImageCacheItem = CacheItem:new{}

function ImageCacheItem:onFree()
    if self.bb.free then
        logger.dbg("free image blitbuffer", self.bb)
        self.bb:free()
    end
end

local ImageWidget = Widget:new{
    -- Can be provided with a path to a file
    file = nil,
    -- or an already made BlitBuffer (ie: made by Mupdf.renderImage())
    image = nil,

    -- Whether BlitBuffer rendered from file should be cached
    file_do_cache = true,
    -- Whether provided BlitBuffer can be modified by us and SHOULD be free() by us,
    -- normally true unless our caller wants to reuse it's provided image
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

    -- When rotation_angle is not 0, native image is rotated by this angle
    -- before scaling.
    rotation_angle = 0,

    -- If scale_for_dpi is true image will be rescaled according to screen dpi
    -- (x2 if DPI > 332) - (formerly known as 'autoscale')
    scale_for_dpi = false,

    -- When scale_factor is not nil, native image is scaled by this factor
    -- (if scale_factor == 1, native image size is kept)
    -- Special case : scale_factor == 0 : image will be scaled to best fit provided
    -- width and height, keeping aspect ratio (scale_factor will be updated
    -- from 0 to the factor used at _render() time)
    -- (former 'autostrech' setting removed, use "scale_factor=0" instead)
    scale_factor = nil,

    -- For initial positionning, if (possibly scaled) image overflows width/height
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
    if itype == "png" or itype == "jpg" or itype == "jpeg"
            or itype == "tiff" then
        local hash = "image|"..self.file.."|"..(self.width or "").."|"..(self.height or "")
        local cache = ImageCache:check(hash)
        if cache then
            -- hit cache
            self._bb = cache.bb
            self._bb_disposable = false -- don't touch or free a cached _bb
        else
            if not self.file_do_cache then
                self._bb = Mupdf.renderImageFile(self.file, self.width, self.height)
                self._bb_disposable = true -- we made it, we can modify and free it
            else
                -- cache this image
                logger.dbg("cache", hash)
                cache = ImageCacheItem:new{
                    bb = Mupdf.renderImageFile(self.file, self.width, self.height),
                }
                cache.size = cache.bb.pitch * cache.bb.h * cache.bb:getBpp() / 8
                ImageCache:insert(hash, cache)
                self._bb = cache.bb
                self._bb_disposable = false -- don't touch or free a cached _bb
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
    logger.dbg("ImageWidget: _render'ing")
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
        if not self._bb_disposable then
            -- we can't modify _bb, make a copy
            self._bb = self._bb:copy()
            self._bb_disposable = true -- new object will have to be freed
        end
        self._bb:rotate(self.rotation_angle) -- rotate in-place
    end

    local bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()

    -- scale_for_dpi setting: update scale_factor (even if not set) with it
    if self.scale_for_dpi then
        local size_scale = math.min(Screen:getWidth(), Screen:getHeight())/600
        local dpi_scale = Screen:getDPI() / 167
        dpi_scale = math.pow(2, math.max(0, math.log((size_scale+dpi_scale)/2)/0.69))
        if self.scale_factor == nil then
            self.scale_factor = 1
        end
        self.scale_factor = self.scale_factor * dpi_scale
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

    -- replace blitbuffer with a resizd one if needed
    local new_bb = nil
    if self.scale_factor == nil then
        -- no scaling, but strech to width and height, only if provided
        if self.width and self.height then
            logger.dbg("ImageWidget: stretching")
            new_bb = self._bb:scale(self.width, self.height)
        end
    elseif self.scale_factor ~= 1 then
        -- scale by scale_factor (not needed if scale_factor == 1)
        logger.dbg("ImageWidget: scaling by", self.scale_factor)
        new_bb = self._bb:scale(bb_w * self.scale_factor, bb_h * self.scale_factor)
    end
    if new_bb then
        -- We made a new blitbuffer, we need to explicitely free
        -- the old one to not leak memory
        if self._bb_disposable then
            self._bb:free()
        end
        self._bb = new_bb
        self._bb_disposable = true -- new object will have to be freed
        bb_w, bb_h = self._bb:getWidth(), self._bb:getHeight()
    end

    -- deal with positionning
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
        UIManager:setDirty("all", function()
            return "partial", self.dimen
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
    if self.alpha == true then
        bb:alphablitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
    else
        bb:blitFrom(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h)
    end
    if self.invert then
        bb:invertRect(x, y, size.w, size.h)
    end
    if self.dim then
        bb:dimRect(x, y, size.w, size.h)
    end
end

-- This will normally be called by our WidgetContainer:free()
-- But it SHOULD explicitely be called if we are getting replaced
-- (ie: in some other widget's update()), to not leak memory with
-- BlitBuffer zombies
function ImageWidget:free()
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
