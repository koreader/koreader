--[[
    Access and modify values in 'Kobo eReader.conf' used by Nickel.
    Only PowerOptions:FrontLightLevel is currently supported .
]]

local NickelConf = {}
NickelConf.frontLightLevel = {}
NickelConf.frontLightState = {}

local kobo_conf_path = '/mnt/onboard/.kobo/Kobo/Kobo eReader.conf'
local front_light_level_str = "FrontLightLevel"
local front_light_state_str = "FrontLightState"
local re_BrightnessValue = "[0-9]+"
local re_StateValue = "true|false"
local re_FrontLightLevel =
    "^" .. front_light_level_str .. "%s*=%s*(" .. re_BrightnessValue .. ")%s*$"
local re_FrontLightState =
    "^" .. front_light_state_str .. "%s*=%s*(" .. re_StateValue .. ")%s*$"
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
            end
            if correct_section then
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

function NickelConf.frontLightLevel.get()
    local new_intensity = NickelConf._read_kobo_conf(re_FrontLightLevel)
    if new_intensity then
        new_intensity = tonumber(new_intensity)
    end

    if not new_intensity then
        local Device = require("device")
        local powerd = Device:getPowerDevice()
        local fallback_FrontLightLevel = powerd.flIntensity or 1

        assert(NickelConf.frontLightLevel.set(fallback_FrontLightLevel))
        return fallback_FrontLightLevel
    end

    return new_intensity
end

function NickelConf.frontLightState.get()
    local new_state = NickelConf._read_kobo_conf(re_FrontLightState)
    if new_state then
        new_state = (new_state == "true" ? true : false)
    end

    if not new_state then
        assert(NickelConf.frontLightState.set(false))
        return false
    end

    return new_state
end

function NickelConf._write_kobo_conf(re_Match, key, value)
    local kobo_conf = io.open(kobo_conf_path, "r")
    if kobo_conf then
        local lines = {}
        local correct_section = false
        local found = false
        for line in kobo_conf:lines() do
            if found then
                --[[
                    The value has been updated, just forward following lines.
                --]]
                lines[#lines + 1] = line
            else
                if string.match(line, re_PowerOptionsSection) then
                    correct_section = true
                elseif string.match(line, re_AnySection) then
                    correct_section = false
                end
                local old_value = string.match(line, re_Match)
                if correct_section and old_value then
                    lines[#lines + 1] = string.gsub(line, re_Match, value, 1)
                    found = true
                else
                    lines[#lines + 1] = line
                end
            end
        end

        if not found then
            if not correct_section then
                lines[#lines + 1] = "[PowerOptions]"
            end
            lines[#lines + 1] = key .. "=" .. value
        end

        local kobo_conf_w = assert(io.open(kobo_conf_path, "w"))
        for i, line in ipairs(lines) do
          kobo_conf_w:write(line, "\n")
        end
        kobo_conf_w:close()

        return true
    else
        return false
    end
end

function NickelConf.frontLightLevel.set(new_intensity)
    assert(new_intensity >= 0 and new_intensity <= 100,
           "Wrong brightness value given!")
    return NickelConf._write_kobo_conf(
               re_FrontLightLevel, front_light_level_str, new_intensity)
end

function NickelConf.frontLightState.set(new_state)
    assert(type(new_state) == "bollean")
    return NickelConf._write_kobo_conf(
               re_FrontLightState, front_light_state_str, new_state)
end

return NickelConf
