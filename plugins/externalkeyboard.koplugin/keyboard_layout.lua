-- US QWERTY physical-keyboard resolver.

local Utf8Proc = require("ffi/utf8proc")

local M = {}

M.SHIFT = 1
M.ALTGR = 2

local DEAD_KEYS = {
    dead_grave = { "\204\128", "`" },
    dead_acute = { "\204\129", "\194\180" },
    dead_circumflex = { "\204\130", "^" },
    dead_tilde = { "\204\131", "~" },
    dead_macron = { "\204\132", "\194\175" },
    dead_breve = { "\204\134", "\203\152" },
    dead_abovedot = { "\204\135", "\203\153" },
    dead_diaeresis = { "\204\136", "\194\168" },
    dead_abovering = { "\204\138", "\194\176" },
    dead_doubleacute = { "\204\139", "\203\157" },
    dead_caron = { "\204\140", "\203\135" },
    dead_cedilla = { "\204\167", "\194\184" },
    dead_ogonek = { "\204\168", "\203\155" },
    dead_iota = { "\205\133" },
    dead_voiced_sound = { "\227\130\153" },
    dead_semivoiced_sound = { "\227\130\154" },
    dead_belowdot = { "\204\163" },
    dead_hook = { "\204\137" },
    dead_horn = { "\204\155" },
    dead_stroke = { "\204\181" },
    dead_abovecomma = { "\204\147" },
    dead_abovereversedcomma = { "\204\148" },
    dead_doublegrave = { "\204\143" },
    dead_belowring = { "\204\165" },
    dead_belowmacron = { "\204\177" },
    dead_belowcircumflex = { "\204\173" },
    dead_belowtilde = { "\204\176" },
    dead_belowbreve = { "\204\174" },
    dead_belowdiaeresis = { "\204\164" },
    dead_invertedbreve = { "\204\145" },
    dead_belowcomma = { "\204\166" },
    dead_currency = { "\226\131\157" },
    dead_lowline = { "\204\178" },
    dead_aboveverticalline = { "\204\141" },
    dead_belowverticalline = { "\204\169" },
    dead_longsolidusoverlay = { "\204\184" },
}

local pending_dead_key

M.layouts = setmetatable({}, {
    __index = function(layouts, layout_name)
        if type(layout_name) ~= "string" or not layout_name:match("^[%w_-]+$") then return nil end
        local loader = loadfile("plugins/externalkeyboard.koplugin/keyboard_layouts/" .. layout_name .. ".lua")
        if not loader then return nil end
        local layout = loader()
        rawset(layouts, layout_name, layout)
        return layout
    end,
})

function M.resolve(layout_name, key_name, modifiers)
    if type(key_name) ~= "string" then return nil end
    if pending_dead_key and pending_dead_key.layout_name ~= layout_name then
        pending_dead_key = nil
    end
    modifiers = modifiers or {}
    local level = 0
    for name, active in pairs(modifiers) do
        if active then
            if name == "Shift" then
                level = level + M.SHIFT
            elseif name == "AltGr" then
                level = level + M.ALTGR
            else
                pending_dead_key = nil
                return nil
            end
        end
    end

    local layout = M.layouts[layout_name]
    if not layout then
        pending_dead_key = nil
        return nil
    end
    local entry = layout[key_name]
    local value = entry and entry[level + 1]

    if not value and key_name:match("^[A-Z]$") then
        value = level == M.SHIFT and key_name or (level == 0 and key_name:lower() or nil)
    end

    if type(value) == "table" then
        pending_dead_key = {
            layout_name = layout_name,
            value = DEAD_KEYS[value.dead],
        }
        return nil
    end
    if not value then
        pending_dead_key = nil
        return nil
    end
    if pending_dead_key then
        local dead_key = pending_dead_key
        pending_dead_key = nil
        if value == " " and dead_key.value[2] then return dead_key.value[2] end
        return Utf8Proc.normalize_NFC(value .. dead_key.value[1])
    end
    return value
end

return M
