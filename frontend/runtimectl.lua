local Mupdf = require("ffi/mupdf")

local Runtimectl = {
    should_restrict_JIT = false,
    is_color_rendering_enabled = false,
    is_bgr = false,
}

--[[
Initialize runtimectl with settings from device.

The following key is required for a device object:

* hasBGRFrameBuffer: function() -> boolean
* screen: object with following methods:
    * getWidth() -> int
    * getHeight() -> int
    * getDPI() -> int
    * getSize() -> Rect
    * scaleBySize(int) -> int
]]--
function Runtimectl:init(device)
    self.screen = device.screen
    self.isAndroid = device.isAndroid
    self.isKindle = device.isKindle

    if self.isAndroid() then
        self:restrictJIT()
    end

    -- NOTE: Kobo's fb is BGR, not RGB. Handle the conversion in MuPDF if needed.
    if device:hasBGRFrameBuffer() then
        self.is_bgr = true
        Mupdf.bgr = true
    end
end

--[[
Disable jit on some modules on android to make koreader on Android more stable.

The strategy here is that we only use precious mcode memory (jitting)
on deep loops like the several blitting methods in blitbuffer.lua and
the pixel-copying methods in mupdf.lua. So that a small amount of mcode
memory (64KB) allocated when koreader is launched in the android.lua
is enough for the program and it won't need to jit other parts of lua
code and thus won't allocate mcode memory any more which by our
observation will be harder and harder as we run koreader.
]]--
function Runtimectl:restrictJIT()
    self.should_restrict_JIT = true
end

function Runtimectl:setColorRenderingEnabled(val)
    self.is_color_rendering_enabled = val
end

function Runtimectl:getExternalFontDir()
    if self.isAndroid() then
        return ANDROID_FONT_DIR
    else
        return os.getenv("EXT_FONT_DIR")
    end
end

function Runtimectl:getRenderWidth()
    return self.screen:getWidth()
end

function Runtimectl:getRenderHeight()
    return self.screen:getHeight()
end

function Runtimectl:getRenderDPI()
    return self.screen:getDPI()
end

function Runtimectl:getRenderSize()
    return self.screen:getSize()
end

function Runtimectl:scaleByRenderSize(px)
    return self.screen:scaleBySize(px)
end

return Runtimectl
