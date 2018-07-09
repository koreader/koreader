--[[--
Image rendering module.
]]

local ffi = require("ffi")
local Device = require("device")
local logger = require("logger")

-- Will be loaded when needed
local Mupdf = nil
local Pic = nil

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
    -- NOTE: Kobo's fb is BGR, not RGB. Handle the conversion in MuPDF if needed.
    if Mupdf.bgr == nil then
        Mupdf.bgr = false
        if Device:hasBGRFrameBuffer() then
            Mupdf.bgr = true
        end
    end
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
        -- (our luajit does not support __len via metatable, otherwise we
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
        -- frame: we need to delay it till 'frames' is no more used.
        frames.gif_close_needed = true
        -- Should happen with that, but __gc seems never called...
        frames = setmetatable(frames, {
            __gc = function()
                logger.dbg("frames.gc() called, closing GifDocument")
                if frames.gif_close_needed then
                    gif:close()
                    frames.gif_close_needed = nil
                end
            end
        })
        -- so, also set this method, so that ImageViewer can explicitely
        -- call it onClose.
        frames.free = function()
            logger.dbg("frames.free() called, closing GifDocument")
            if frames.gif_close_needed then
                gif:close()
                frames.gif_close_needed = nil
            end
        end
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

return RenderImage
