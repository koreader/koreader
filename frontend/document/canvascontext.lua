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
    should_restrict_JIT = false,
    is_color_rendering_enabled = false,
    is_bgr = false,
}

--[[
Initialize CanvasContext with settings from device.

The following key is required for a device object:

* should_restrict_JIT: bool
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
    self.screen = device.screen
    self.isAndroid = device.isAndroid
    self.isDesktop = device.isDesktop
    self.isEmulator = device.isEmulator
    self.isKindle = device.isKindle
    self.isPocketBook = device.isPocketBook
    self.should_restrict_JIT = device.should_restrict_JIT
    self:setColorRenderingEnabled(device.screen.isColorEnabled())

    -- NOTE: Kobo's fb is BGR, not RGB. Handle the conversion in MuPDF if needed.
    if device:hasBGRFrameBuffer() then
        self.is_bgr = true
        Mupdf.bgr = true
    end
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

return CanvasContext
