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
-- Nickel will set FrontLightLevel to 0 - 100
local re_FrontLightLevel = "^" .. front_light_level_str .. "%s*=%s*([0-9]+)%s*$"
-- Nickel will set FrontLightState to true (light on) or false (light off)
local re_FrontLightState = "^" .. front_light_state_str .. "%s*=%s*(.+)%s*$"
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

function NickelConf.frontLightState.get()
    local new_state = NickelConf._read_kobo_conf(re_FrontLightState)
    if new_state then
        new_state = (new_state == "true") or false
    end
    -- for devices that do not have toggle button, the entry will be missing
    -- and we return nil in this case.
    return new_state
end

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

function NickelConf.frontLightLevel.set(new_intensity)
    assert(new_intensity >= 0 and new_intensity <= 100,
           "Wrong brightness value given!")
    return NickelConf._write_kobo_conf(re_FrontLightLevel,
                                       front_light_level_str,
                                       new_intensity)
end

function NickelConf.frontLightState.set(new_state)
    assert(type(new_state) == "boolean",
           "Wrong front light state value type (expect boolean)!")
    return NickelConf._write_kobo_conf(re_FrontLightState,
                                       front_light_state_str,
                                       new_state,
                                       -- do not create this entry is missing
                                       true)
end

return NickelConf
