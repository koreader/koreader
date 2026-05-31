--[[--
lib/color.lua — ink color model for fastnote.koplugin.

Defines the 6-color palette with light/dark Kaleido 3 variants and
color resolution helpers used by DrawingCanvas and StrokeBuffer.

Stroke data is always stored using the light-mode hex as the canonical
color value. Dark mode is a display-only transform — stroke data is
never mutated.

Pure Lua; no KOReader dependencies; fully busted-testable.

@module fastnote.lib.color
--]]--

local Color = {}

--- 6-color ink palette with light and dark Kaleido 3 variants.
-- .light — canonical stored hex (used on disk + in light mode)
-- .dark  — display hex in dark mode
-- .name  — human-readable label (shown in quick menu)
Color.PALETTE = {
    { name = "Black",  light = "#000000", dark = "#ffffff" },
    { name = "Red",    light = "#cc2222", dark = "#ff5555" },
    { name = "Blue",   light = "#2244cc", dark = "#5577ff" },
    { name = "Green",  light = "#22aa44", dark = "#55cc77" },
    { name = "Orange", light = "#cc7700", dark = "#ffaa33" },
    { name = "Purple", light = "#8822bb", dark = "#bb77ee" },
}

-- Reverse lookup: light hex → palette entry (O(1) resolve).
-- Built once at module load; never mutated.
local _by_light = {}
for _, entry in ipairs(Color.PALETTE) do
    _by_light[entry.light] = entry
end

--- Return the display hex for a stored light-hex value.
-- Strokes are stored with the light-mode variant as the canonical color.
-- Dark mode is a display-only transform; stored data is never mutated.
-- Unknown hex (not in palette) is returned unchanged — safe fallback for
-- externally-authored SVGs that use arbitrary colors.
--
-- @string stored_hex  canonical light-mode hex (e.g. "#cc2222")
-- @bool   dark_mode   true if the canvas is in dark mode
-- @return string  the hex color to paint with
function Color.resolve(stored_hex, dark_mode)
    local entry = _by_light[stored_hex]
    if not entry then return stored_hex end
    return dark_mode and entry.dark or entry.light
end

--- True if the hex is black (#000000) or white (#ffffff).
-- Used by the deferred colour develop gate: achromatic strokes have no
-- colour information to reveal, so developing a region that only contains
-- black/white ink is a no-op on Kaleido hardware.
--
-- @string hex  color hex string
-- @return bool
function Color.is_achromatic(hex)
    return hex == "#000000" or hex == "#ffffff"
end

return Color
