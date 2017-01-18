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

    invert = nil,
    dim = nil,
    hide = nil,
    -- if width or height is given, image will rescale to the given size
    width = nil,
    height = nil,
    -- if autoscale is true image will be rescaled according to screen dpi
    autoscale = false,
    -- when alpha is set to true, alpha values from the image will be honored
    alpha = false,
    -- when autostretch is set to true, image will be stretched to best fit the
    -- widget size. i.e. either fit the width or fit the height according to the
    -- original image size.
    autostretch = false,
    -- when pre_rotate is not 0, native image is rotated by this angle
    -- before applying the other autostretch/autoscale settings
    pre_rotate = 0,
    -- former 'overflow' setting removed, as logic was wrong

    _bb = nil,
    _bb_disposable = true -- whether we should free() our _bb
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
    if self.image then
        self:_loadimage()
    elseif self.file then
        self:_loadfile()
    else
        error("cannot render image")
    end
    if self.pre_rotate ~= 0 then
        if not self._bb_disposable then
            -- we can't modify _bb, make a copy
            self._bb = self._bb:copy()
            self._bb_disposable = true -- new object will have to be freed
        end
        self._bb:rotate(self.pre_rotate) -- rotate in-place
    end
    local native_w, native_h = self._bb:getWidth(), self._bb:getHeight()
    local w, h = self.width, self.height
    if self.autoscale then
        local dpi_scale = Screen:getDPI() / 167
        -- rounding off to power of 2 to avoid alias with pow(2, floor(log(x)/log(2))
        local scale = math.pow(2, math.max(0, math.floor(math.log(dpi_scale)/0.69)))
        w, h = scale * native_w, scale * native_h
    elseif self.width and self.height then
        if self.autostretch then
            local ratio = native_w / self.width / native_h * self.height
            if ratio < 1 then
                h = self.height
                w = self.width * ratio
            else
                h = self.height / ratio
                w = self.width
            end
        end
    end
    if (w and w ~= native_w) or (h and h ~= native_h) then
        -- We're making a new blitbuffer, we need to explicitely free
        -- the old one to not leak memory
        local new_bb = self._bb:scale(w or native_w, h or native_h)
        if self._bb_disposable then
            self._bb:free()
        end
        self._bb = new_bb
        self._bb_disposable = true -- new object will have to be freed
    end
end

function ImageWidget:getSize()
    self:_render()
    return Geom:new{ w = self._bb:getWidth(), h = self._bb:getHeight() }
end

function ImageWidget:rotate(degree)
    self:_render()
    self._bb:rotate(degree)
end

function ImageWidget:paintTo(bb, x, y)
    if self.hide then return end
    -- self:_reader is called in getSize method
    local size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = size.w,
        h = size.h
    }
    if self.alpha == true then
        bb:alphablitFrom(self._bb, x, y, 0, 0, size.w, size.h)
    else
        bb:blitFrom(self._bb, x, y, 0, 0, size.w, size.h)
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
end

function ImageWidget:onCloseWidget()
    -- free when UIManager:close() was called
    self:free()
end

return ImageWidget
