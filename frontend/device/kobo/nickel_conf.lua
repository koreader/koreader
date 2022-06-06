--[[--
Access and modify values in `Kobo eReader.conf` used by Nickel.
Only PowerOptions:FrontLightLevel is currently supported.
]]

local dbg = require("dbg")

local NickelConf = {}
NickelConf.frontLightLevel = {}
NickelConf.frontLightState = {}
NickelConf.colorSetting = {}

local kobo_conf_path = '/mnt/onboard/.kobo/Kobo/Kobo eReader.conf'
local front_light_level_str = "FrontLightLevel"
local front_light_state_str = "FrontLightState"
local color_setting_str = "ColorSetting"
-- Nickel will set FrontLightLevel to 0 - 100
local re_FrontLightLevel = "^" .. front_light_level_str .. "%s*=%s*([0-9]+)%s*$"
-- Nickel will set FrontLightState to true (light on) or false (light off)
local re_FrontLightState = "^" .. front_light_state_str .. "%s*=%s*(.+)%s*$"
-- Nickel will set ColorSetting to 1500 - 6400
local re_ColorSetting = "^" .. color_setting_str .. "%s*=%s*([0-9]+)%s*$"
local re_PowerOptionsSection = "^%[PowerOptions%]%s*"
local re_AnySection = "^%[.*%]%s*"


function NickelConf._set_kobo_conf_path(new_path)
    kobo_conf_path = new_path
end

function NickelConf._read_kobo_conf(re_Match)
    local value
    local correct_section = false
    local kobo_conf = io.open(kobo_conf_path, "r")

    if kobo_conf then
        for line in kobo_conf:lines() do
            if string.match(line, re_PowerOptionsSection) then
                correct_section = true
            elseif string.match(line, re_AnySection) then
                correct_section = false
            elseif correct_section then
                value = string.match(line, re_Match)
                if value then
                    break
                end
            end
        end
        kobo_conf:close()
    end

    return value
end

--[[--
Get frontlight level.

@treturn int Frontlight level.
--]]
function NickelConf.frontLightLevel.get()
    local new_intensity = NickelConf._read_kobo_conf(re_FrontLightLevel)
    if new_intensity then
        -- we need 0 to signal frontlight off for device that does not support
        -- FrontLightState config, so don't normalize the value here yet.
        return tonumber(new_intensity)
    else
        local fallback_fl_level = 1
        assert(NickelConf.frontLightLevel.set(fallback_fl_level))
        return fallback_fl_level
    end
end

--[[--
Get frontlight state.

This entry will be missing for devices that do not have a hardware toggle button.
We return nil in this case.

@treturn int Frontlight state (or nil).
--]]
function NickelConf.frontLightState.get()
    local new_state = NickelConf._read_kobo_conf(re_FrontLightState)

    if new_state then
        new_state = (new_state == "true") or false
    end

    return new_state
end

--[[--
Get color setting.

@treturn int Color setting.
--]]
function NickelConf.colorSetting.get()
    local new_colorsetting = NickelConf._read_kobo_conf(re_ColorSetting)
    if new_colorsetting then
        return tonumber(new_colorsetting)
    end
end

--[[--
Write Kobo configuration.

@string re_Match Lua pattern.
@string key Kobo conf key.
@param value
@bool dontcreate Don't create if key doesn't exist.
--]]
function NickelConf._write_kobo_conf(re_Match, key, value, dont_create)
    local kobo_conf = io.open(kobo_conf_path, "r")
    local lines = {}
    local found = false
    local remaining
    local correct_section = false
    local new_value_line = key .. "=" .. tostring(value)
    if kobo_conf then
        local pos
        for line in kobo_conf:lines() do
            if string.match(line, re_AnySection) then
                if correct_section then
                    -- found a new section after having found the correct one,
                    -- therefore the key was missing: let the code below add it
                    kobo_conf:seek("set", pos)
                    break
                elseif string.match(line, re_PowerOptionsSection) then
                    correct_section = true
                end
            end
            local old_value = string.match(line, re_Match)
            if correct_section and old_value then
                lines[#lines + 1] = new_value_line
                found = true
                break
            else
                lines[#lines + 1] = line
            end
            pos = kobo_conf:seek()
        end

        remaining = kobo_conf:read("*a")
        kobo_conf:close()
    end

    if not found then
        if dont_create then return true end

        if not correct_section then
            lines[#lines + 1] = "[PowerOptions]"
        end
        lines[#lines + 1] = new_value_line
    end

    local kobo_conf_w = assert(io.open(kobo_conf_path, "w"))
    for i, line in ipairs(lines) do
      kobo_conf_w:write(line, "\n")
    end
    if remaining then
        kobo_conf_w:write(remaining)
    end
    kobo_conf_w:close()

    return true
end

--[[--
Set frontlight level.

@int new_intensity
--]]
function NickelConf.frontLightLevel.set(new_intensity)
    if type(new_intensity) ~= "number" or (new_intensity < 0 or new_intensity > 100) then return end
    return NickelConf._write_kobo_conf(re_FrontLightLevel,
                                       front_light_level_str,
                                       new_intensity)
end
dbg:guard(NickelConf.frontLightLevel, "set",
    function(new_intensity)
        assert(type(new_intensity) == "number",
               "Wrong brightness value type (expected number)!")
        assert(new_intensity >= 0 and new_intensity <= 100,
               "Wrong brightness value given!")
    end)

--[[--
Set frontlight state.

@bool new_state
--]]
function NickelConf.frontLightState.set(new_state)
    if new_state == nil or type(new_state) ~= "boolean" then return end
    return NickelConf._write_kobo_conf(re_FrontLightState,
                                       front_light_state_str,
                                       new_state,
                                       -- Do not create if this entry is missing.
                                       true)
end
dbg:guard(NickelConf.frontLightState, "set",
    function(new_state)
        assert(type(new_state) == "boolean",
            "Wrong front light state value type (expected boolean)!")
    end)

--[[--
Set color setting.

@int new_color >= 1500 and <= 6400
--]]
function NickelConf.colorSetting.set(new_color)
    return NickelConf._write_kobo_conf(re_ColorSetting,
                                       color_setting_str,
                                       new_color)
end
dbg:guard(NickelConf.colorSetting, "set",
    function(new_color)
        assert(type(new_color) == "number",
            "Wrong color value type (expected number)!")
        assert(new_color >= 1500 and new_color <= 6400,
            "Wrong colorSetting value given!")
    end)

return NickelConf
