--[[--
Image rendering module.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Math = require("optmath")
local ffi = require("ffi")
local logger = require("logger")

-- Will be loaded when needed
local Mupdf = nil
local Pic = nil
local NnSVG = nil

local RenderImage = {}

--- Renders image file as a BlitBuffer with the best renderer
--
-- @string filename image file path
-- @bool[opt=false] want_frames whether to return a list of animated GIF frames
-- @int width requested width
-- @int height requested height
-- @treturn BlitBuffer or list of frames (each a function returning a Blitbuffer)
function RenderImage:renderImageFile(filename, want_frames, width, height)
    local file = io.open(filename, "rb")
    if not file then
        logger.info("could not open image file:", filename)
        return
    end
    local data = file:read("*a")
    file:close()
    return RenderImage:renderImageData(data, #data, want_frames, width, height)
end


--- Renders image data as a BlitBuffer with the best renderer
--
-- @tparam data string or userdata (pointer) with image bytes
-- @int size size of data
-- @bool[opt=false] want_frames whether to return a list of animated GIF frames
-- @int width requested width
-- @int height requested height
-- @treturn BlitBuffer or list of frames (each a function returning a Blitbuffer)
function RenderImage:renderImageData(data, size, want_frames, width, height)
    if not data or not size or size == 0 then
        return
    end
    -- Guess if it is a GIF
    local buffer = ffi.cast("unsigned char*", data)
    local header = ffi.string(buffer, math.min(4, size))
    if header == "GIF8" then
        logger.dbg("GIF file provided, renderImageData: using GifLib")
        local image = self:renderGifImageDataWithGifLib(data, size, want_frames, width, height)
        if image then
            return image
        end
        -- fallback to rendering with MuPDF
    end
    logger.dbg("renderImageData: using MuPDF")
    return self:renderImageDataWithMupdf(data, size, width, height)
end

--- Renders image data as a BlitBuffer with MuPDF
--
-- @tparam data string or userdata (pointer) with image bytes
-- @int size size of data
-- @int width requested width
-- @int height requested height
-- @treturn BlitBuffer
function RenderImage:renderImageDataWithMupdf(data, size, width, height)
    if not Mupdf then Mupdf = require("ffi/mupdf") end
    local ok, image = pcall(Mupdf.renderImage, data, size, width, height)
    logger.dbg("Mupdf.renderImage", ok, image)
    if not ok then
        logger.info("failed rendering image (mupdf):", image)
        return
    end
    return image
end

--- Renders image data as a BlitBuffer with GifLib
--
-- @tparam data string or userdata (pointer) with image bytes
-- @int size size of data
-- @bool[opt=false] want_frames whether to also return a list with animated GIF frames
-- @int width requested width
-- @int height requested height
-- @treturn BlitBuffer or list of frames (each a function returning a Blitbuffer)
function RenderImage:renderGifImageDataWithGifLib(data, size, want_frames, width, height)
    if not data or not size or size == 0 then
        return
    end
    if not Pic then Pic = require("ffi/pic") end
    local ok, gif = pcall(Pic.openGIFDocumentFromData, data, size)
    logger.dbg("Pic.openGIFDocumentFromData", ok)
    if not ok then
        logger.info("failed rendering image (giflib):", gif)
        return
    end
    local nb_frames = gif:getPages()
    logger.dbg("GifDocument, nb frames:", nb_frames)
    if want_frames and nb_frames > 1 then
        -- Returns a regular table, with functions (returning the BlitBuffer)
        -- as values. Users will have to check via type() and call them.
        -- (The __len metamethod is a Lua 5.2 feature, otherwise we
        -- could have used setmetatable to avoid creating all the functions)
        local frames = {}
        -- As we don't cache the bb we build on the fly, let caller know it
        -- will have to free them
        frames.image_disposable = true
        for i=1, nb_frames do
            table.insert(frames, function()
                local page = gif:openPage(i)
                -- we do not page.close(), so image_bb is not freed
                if page and page.image_bb then
                    return self:scaleBlitBuffer(page.image_bb, width, height)
                end
            end)
        end
        -- We can't close our GifDocument as long as we may fetch some
        -- frame: we need to delay it till 'frames' is no longer used.
        frames.gif_close_needed = true
        -- Since frames is a plain table, __gc won't work on Lua 5.1/LuaJIT,
        -- not without a little help from the newproxy hack...
        frames.gif = gif
        local frames_mt = {}
        function frames_mt:__gc()
            logger.dbg("frames.gc() called, closing GifDocument", self.gif)
            if self.gif_close_needed then
                self.gif:close()
                self.gif_close_needed = nil
            end
        end
        -- Much like our other stuff, when we're puzzled about __gc, we do it manually!
        -- So, also set this method, so that ImageViewer can explicitely call it onClose.
        function frames:free()
            logger.dbg("frames.free() called, closing GifDocument", self.gif)
            if self.gif_close_needed then
                self.gif:close()
                self.gif_close_needed = nil
            end
        end
        local setmetatable = require("ffi/__gc")
        setmetatable(frames, frames_mt)
        return frames
    else
        local page = gif:openPage(1)
        -- we do not page.close(), so image_bb is not freed
        if page and page.image_bb then
            gif:close()
            return self:scaleBlitBuffer(page.image_bb, width, height)
        end
        gif:close()
    end
    logger.info("failed rendering image (giflib)")
end

--- Rescales a BlitBuffer to the requested size if needed
--
-- @tparam bb BlitBuffer
-- @int width
-- @int height
-- @bool[opt=true] free_orig_bb free() original bb if scaled
-- @treturn BlitBuffer
function RenderImage:scaleBlitBuffer(bb, width, height, free_orig_bb)
    if not width or not height then
        logger.dbg("RenderImage:scaleBlitBuffer: no need")
        return bb
    end
    -- Ensure we give integer width and height to MuPDF, to
    -- avoid a black 1-pixel line at right and bottom of image
    width, height = math.floor(width), math.floor(height)
    if bb:getWidth() == width and bb:getHeight() == height then
        logger.dbg("RenderImage:scaleBlitBuffer: no need")
        return bb
    end
    logger.dbg("RenderImage:scaleBlitBuffer: scaling")
    local scaled_bb
    if G_reader_settings:isTrue("legacy_image_scaling") then
        -- Uses "simple nearest neighbour scaling"
        scaled_bb = bb:scale(width, height)
    else
        -- Better quality scaling with MuPDF
        if not Mupdf then Mupdf = require("ffi/mupdf") end
        scaled_bb = Mupdf.scaleBlitBuffer(bb, width, height)
    end
    if not free_orig_bb == false then
        bb:free()
    end
    return scaled_bb
end

--- Renders SVG image file as a BlitBuffer with the best renderer
--
-- @string filename image file path
-- @int width requested width
-- @int height requested height
-- @number zoom requested zoom
-- @treturn BlitBuffer
function RenderImage:renderSVGImageFile(filename, width, height, zoom)
    if self.RENDER_SVG_WITH_NANOSVG then
        return self:renderSVGImageFileWithNanoSVG(filename, width, height, zoom)
    else
        return self:renderSVGImageFileWithMupdf(filename, width, height, zoom)
    end
end

-- For now (with our old MuPDF 1.13), NanoSVG is the best renderer
-- Note that both renderers currently enforce keeping the image's
-- original aspect ratio.
RenderImage.RENDER_SVG_WITH_NANOSVG = true

function RenderImage:renderSVGImageFileWithNanoSVG(filename, width, height, zoom)
    if not NnSVG then
        NnSVG = require("libs/libkoreader-nnsvg")
    end
    local svg_image = NnSVG.new(filename)
    local native_w, native_h = svg_image:getSize()
    if not zoom then
        if width and height then
            -- Original aspect ratio will be kept, we might have
            -- to center the SVG inside the target width/height
            zoom = math.min(width/native_w, height/native_h)
        elseif width then
            zoom = width/native_w
        elseif height then
            zoom = height/native_h
        else
            zoom = 1
        end
    end
    -- (Be sure we use integers; using floats can cause glitches)
    local inner_w = math.ceil(zoom * native_w)
    local inner_h = math.ceil(zoom * native_h)
    local offset_x = 0
    local offset_y = 0
    if not width then
        width = inner_w
    elseif inner_w < width then
        offset_x = Math.round((width - inner_w) / 2)
    end
    if not height then
        height = inner_h
    elseif inner_h < height then
        offset_y = Math.round((height - inner_h) / 2)
    end
    logger.dbg("renderSVG", filename, zoom, native_w, native_h, ">", width, height, offset_x, offset_y)
    local bb = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    svg_image:drawTo(bb, zoom, offset_x, offset_y)
    svg_image:free()
    return bb, true -- is_straight_alpha=true
end

function RenderImage:renderSVGImageFileWithMupdf(filename, width, height, zoom)
    local ok, document = pcall(Mupdf.openDocument, filename)
    if not ok then
        return
    end
    -- document:layoutDocument(width, height, 20) -- does not change anything
    if document:getPages() <= 0 then
        return
    end
    local page = document:openPage(1)
    local DrawContext = require("ffi/drawcontext")
    local dc = DrawContext.new()
    local native_w, native_h = page:getSize(dc)
    if not zoom then
        if width and height then
            zoom = math.min(width/native_w, height/native_h)
        elseif width then
            zoom = width/native_w
        elseif height then
            zoom = height/native_h
        else
            zoom = 1
        end
    end
    if not width or not height then
        width = zoom * native_w
        height = zoom * native_h
    end
    width = math.ceil(width)
    height = math.ceil(height)
    logger.dbg("renderSVG", filename, zoom, native_w, native_h, ">", width, height)
    dc:setZoom(zoom)
    -- local bb = page:draw_new(dc, width, height, 0, 0)
    -- MuPDF or our FFI may fail on some icons (appbar.page.fit),
    -- avoid a crash and return a blank and black image
    local rendered, bb = pcall(page.draw_new, page, dc, width, height, 0, 0)
    if not rendered then
        logger.warn("MuPDF renderSVG error:", bb)
        bb = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    end
    page:close()
    document:close()
    return bb -- pre-multiplied alpha: no is_straight_alpha=true
end

return RenderImage
