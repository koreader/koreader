local Widget = require("ui/widget/widget")
local Screen = require("device").screen
local CacheItem = require("cacheitem")
local Mupdf = require("ffi/mupdf")
local Geom = require("ui/geometry")
local Cache = require("cache")
local DEBUG = require("dbg")

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
        DEBUG("free image blitbuffer", self.bb)
        self.bb:free()
    end
end

--[[
ImageWidget shows an image from a file
--]]
local ImageWidget = Widget:new{
    file = nil,
    image = nil,
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
    _bb = nil
}

function ImageWidget:_loadimage()
    self._bb = self.image
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
        else
            -- cache this image
            DEBUG("cache", hash)
            local cache = ImageCacheItem:new{
                bb = Mupdf.renderImageFile(self.file, self.width, self.height),
            }
            cache.size = cache.bb.pitch * cache.bb.h * cache.bb:getBpp() / 8
            ImageCache:insert(hash, cache)
            self._bb = cache.bb
        end
    else
        error("Image file type not supported.")
    end
end

function ImageWidget:_render()
    if self.image then
        self:_loadimage()
    elseif self.file then
        self:_loadfile()
    else
        error("cannot render image")
    end
    local native_w, native_h = self._bb:getWidth(), self._bb:getHeight()
    local scaled_w, scaled_h = self.width, self.height
    if self.autoscale then
        local dpi_scale = Screen:getDPI() / 167
        -- rounding off to power of 2 to avoid alias with pow(2, floor(log(x)/log(2))
        local scale = math.pow(2, math.max(0, math.floor(math.log(dpi_scale)/0.69)))
        scaled_w, scaled_h = scale * native_w, scale * native_h
    end
    if (scaled_w and scaled_w ~= native_w) or (scaled_h and scaled_h ~= native_h) then
        self._bb = self._bb:scale(scaled_w or native_w, scaled_h or native_h)
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

function ImageWidget:free()
    if self.image then
        self.image:free()
        self.image = nil
    end
end

return ImageWidget
