--[[--
lib/config.lua — fastnote.koplugin user configuration loader.

Reads a Lua-table config file and merges it with built-in defaults.
Pure Lua; no KOReader runtime dependencies — fully busted-testable.

The config file (typically koreader/settings/fastnote.conf) must be a
plain Lua file that returns a table, e.g.:

    return {
        finger_draw = false,
    }

Any key absent from the file is filled from Config.DEFAULTS.
Syntax errors or non-table returns fall back to DEFAULTS silently.

@module fastnote.config
--]]--

local Config = {}

--- Default values for all supported config keys.
-- These apply when a key is absent from the user's config file.
Config.DEFAULTS = {
    --- Allow drawing with finger touches in addition to the pen.
    -- false = pen-only (default). true = pen + finger both draw.
    finger_draw = false,

    --- Rotation mode to apply when the canvas opens.
    -- "auto" (default) — inherit whatever orientation is current on open.
    -- 0 = portrait upright, 1 = landscape CW, 2 = portrait inverted,
    -- 3 = landscape CCW (buttons at bottom on Kobo Libra — recommended landscape).
    rotation_mode = "auto",

    --- Enable raw + decoded pen event logging to fastnote/input.log.
    -- false (default) = off.  Also toggleable live via the hamburger menu.
    debug_input_log = false,

    --- Seconds of pen inactivity after which the deferred colour "tighten"
    -- pass fires -- a single targeted GLRC16 refresh over the accumulated
    -- stroke bounding box (drawingcanvas.lua: _scheduleTighten).  Only takes
    -- effect on colour hardware (Kaleido 3).
    -- Default: 2.5 -- matches the device-tuned COLOR_TIGHTEN_DELAY constant.
    -- This value was tuned on real hardware: shorter delays fire the tighten
    -- pass mid-multi-stroke writing and briefly lock out the pen. See
    -- .github/instructions/eink-refresh.instructions.md before lowering it,
    -- and re-run the multi-stroke writing test in the waveform-experimentation
    -- skill if you do.
    tighten_delay = 2.5,

    --- Whether to perform the deferred colour tighten pass at all.
    -- true (default) = strokes tighten into full colour ~tighten_delay
    -- seconds after the pen lifts (colour hardware only).
    -- false = draw-time A2 only (no deferred colour pass).
    tighten_enabled = true,

    --- EXPERIMENTAL. Throttled direct-refresh live colour drawing
    -- (pencil.koplugin technique; see
    -- .agents/planning/pencil-koplugin-research.md candidate 1). Only takes
    -- effect when colour hardware AND the raw evdev pen path are both in
    -- use -- the gesture/emulator path and monochrome hardware are never
    -- affected by this flag.
    -- false (default) = unchanged per-segment "a2" refresh behaviour.
    -- true  = live segments blit directly into the framebuffer and refresh
    --         via a throttled direct Screen:refreshUI call instead, showing
    --         (muted) live colour. Not yet validated on the on-device test
    --         matrix -- see .github/skills/waveform-experimentation/SKILL.md
    --         before relying on this outside of testing.
    live_color_refresh = false,

    --- Which raw button code the hardware eraser tip sends on this unit.
    -- The Kobo Stylus 2 eraser tip reports as BTN_STYLUS (level signal)
    -- while the side button reports as BTN_STYLUS2 -- but some units/pens
    -- ship with the two swapped. See lib/eraser_button.lua and
    -- .agents/plans/color-drawing-fix-and-menu-access.md Fix F.
    -- "stylus"  (default) -- eraser tip sends BTN_STYLUS (standard wiring).
    -- "stylus2" -- eraser tip sends BTN_STYLUS2 (swapped unit). Symptom
    --             that tells you to try this: the eraser end draws instead
    --             of erasing.
    eraser_button = "stylus",
}

--- Load a config file and return the merged result.
-- @param  path  absolute path to the config file, or nil to use defaults only.
-- @return table  config with every key guaranteed to be present (from file or DEFAULTS).
function Config.load(path)
    local cfg = {}

    if path ~= nil then
        local chunk, _err = loadfile(path)
        if chunk then
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then
                cfg = result
            end
        end
    end

    -- Merge defaults for any key absent from the file.
    -- We copy into a fresh table so mutations by the caller cannot affect DEFAULTS.
    --
    -- NOTE: this must NOT be written as `out[k] = (cfg[k] ~= nil) and cfg[k] or v`.
    -- That ternary-style and/or has a hole (see lua.instructions.md): when
    -- cfg[k] is explicitly `false`, `cfg[k] ~= nil` is true, but the second
    -- `and` operand (`cfg[k]`) is itself false, so the whole expression
    -- falls through to `v` -- silently discarding the user's explicit
    -- `false` and replacing it with the default. Use an explicit if instead.
    local out = {}
    for k, v in pairs(Config.DEFAULTS) do
        if cfg[k] ~= nil then
            out[k] = cfg[k]
        else
            out[k] = v
        end
    end

    return out
end

return Config
