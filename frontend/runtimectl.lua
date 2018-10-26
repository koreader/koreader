local Runtimectl = {
    should_restrict_JIT = false,
    is_color_rendering_enabled = false,
}

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

return Runtimectl
