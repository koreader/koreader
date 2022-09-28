--[[
CanvasContext is introduced to abstract out screen hardware code from document
render module. This abstraction makes it possible to use core document module
in headless mode.

You can think of canvas as a virtual screen. It provides render related
settings like canvas dimension and DPI. User of document module need to
initialize CanvasContext with settings from the actual hardware screen before
calling renderPage/drawPage.

Note: CanvasContext is a singleton and it is not thread safe.
]]--

local Mupdf = require("ffi/mupdf")

local CanvasContext = {
    is_color_rendering_enabled = false,
    is_bgr = false,
}

--[[
Initialize CanvasContext with settings from device.

The following key is required for a device object:

* hasBGRFrameBuffer: function() -> boolean
* screen: object with following methods:
    * getWidth() -> int
    * getHeight() -> int
    * getDPI() -> int
    * getSize() -> Rect
    * scaleBySize(int) -> int
    * isColorEnabled() -> boolean
]]--
function CanvasContext:init(device)
    self.device = device
    self.screen = device.screen
    -- NOTE: These work because they don't actually require accessing the Device object itself,
    --       as opposed to more dynamic methods like the Screen ones we handle properly later...
    --       By which I mean when one naively calls CanvasContext:isKindle(), it calls
    --       device.isKindle(CanvasContext), whereas when one calls Device:isKindle(), it calls
    --       Device.isKindle(Device).
    --       In the latter case, self is sane, but *NOT* in the former.
    --       TL;DR: The methods assigned below must *never* access self.
    --              (Or programmers would have to be careful to call them through CanvasContext as functions,
    --              and not methods, which is clunky, error-prone, and unexpected).
    self.isAndroid = device.isAndroid
    self.isDesktop = device.isDesktop
    self.isEmulator = device.isEmulator
    self.isKindle = device.isKindle
    self.isPocketBook = device.isPocketBook
    self.hasSystemFonts = device.hasSystemFonts
    self:setColorRenderingEnabled(device.screen:isColorEnabled())

    -- NOTE: At 32bpp, Kobo's fb is BGR, not RGB. Handle the conversion in MuPDF if needed.
    if device:hasBGRFrameBuffer() then
        self.is_bgr = true
        Mupdf.bgr = true
    end

    -- This one may be called by a subprocess, and would crash on Android when
    -- calling android.isEink() which is only allowed from the main thread.
    local hasEinkScreen = device:hasEinkScreen()
    self.hasEinkScreen = function() return hasEinkScreen end

    self.canHWDither = device.canHWDither
    self.fb_bpp = device.screen.fb_bpp
end


function CanvasContext:setColorRenderingEnabled(val)
    self.is_color_rendering_enabled = val
end

function CanvasContext:getWidth()
    return self.screen:getWidth()
end

function CanvasContext:getHeight()
    return self.screen:getHeight()
end

function CanvasContext:getDPI()
    return self.screen:getDPI()
end

function CanvasContext:getSize()
    return self.screen:getSize()
end

function CanvasContext:scaleBySize(px)
    return self.screen:scaleBySize(px)
end

function CanvasContext:enableCPUCores(amount)
    return self.device:enableCPUCores(amount)
end

return CanvasContext
