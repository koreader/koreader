local Widget = require("ui/widget/widget")
local CacheItem = require("cacheitem")
local Image = require("ffi/mupdfimg")
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
    invert = nil,
    dim = nil,
    hide = nil,
    -- if width or height is given, image will rescale to the given size
    width = nil,
    height = nil,
    _bb = nil
}

function ImageWidget:_render()
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
                bb = Image:fromFile(self.file, self.width, self.height),
            }
            cache.size = cache.bb.pitch * cache.bb.h
            ImageCache:insert(hash, cache)
            self._bb = cache.bb
        end
    else
        error("Image file type not supported.")
    end
    local w, h = self._bb:getWidth(), self._bb:getHeight()
    if (self.width and self.width ~= w) or (self.height and self.height ~= h) then
        self._bb = self._bb:scale(self.width or w, self.height or h)
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
    bb:blitFrom(self._bb, x, y, 0, 0, size.w, size.h)
    if self.invert then
        bb:invertRect(x, y, size.w, size.h)
    end
    if self.dim then
        bb:dimRect(x, y, size.w, size.h)
    end
end

return ImageWidget
