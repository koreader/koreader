--[[
    Access and modify values in 'Kobo eReader.conf' used by Nickel.
    Only PowerOptions:FrontLightLevel is currently supported .
]]

local NickelConf = {}
NickelConf.frontLightLevel = {}

local kobo_conf_path = '/mnt/onboard/.kobo/Kobo/Kobo eReader.conf'
local re_BrightnessValue = "[0-9]+"
local re_FrontLightLevel = "^FrontLightLevel%s*=%s*(" .. re_BrightnessValue .. ")%s*$"
local re_PowerOptionsSection = "^%[PowerOptions%]%s*"
local re_AnySection = "^%[.*%]%s*"

function NickelConf.frontLightLevel.get()

    local new_intensity
    local correct_section = false
    local kobo_conf = io.open(kobo_conf_path, "r")

    if kobo_conf then
        for line in kobo_conf:lines() do
            if string.match(line, re_AnySection) then
                correct_section = false
                if string.match(line, re_PowerOptionsSection) then
                    correct_section = true
                end
            end
            if correct_section then
                new_intensity = string.match(line, re_FrontLightLevel)
                if new_intensity then
                    new_intensity = tonumber(new_intensity)
                    break
                end
            end
        end
        kobo_conf:close()
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

function NickelConf.frontLightLevel.set(new_intensity)
	assert(new_intensity >= 0 and new_intensity <= 100,
		"Wrong brightness value given!")

    local kobo_conf
    local old_intensity
    local remaining_file = ""
    local lines = {}
    local current_position
    local correct_section = false
    local modified_brightness = false

    kobo_conf = io.open(kobo_conf_path, "r")
    if kobo_conf then
        for line in kobo_conf:lines() do
            if string.match(line, re_AnySection) then
                if correct_section then
                    -- found a new section after having found the correct one,
                    -- therefore the key was missing: let the code below add it
                    kobo_conf:seek("set", current_position)
                    break
                end
                if string.match(line, re_PowerOptionsSection) then
                    correct_section = true
                end
            end
            old_intensity = string.match(line, re_FrontLightLevel)
            if correct_section and old_intensity then
                lines[#lines + 1] = string.gsub(line, re_BrightnessValue, new_intensity, 1)
                modified_brightness = true
                break
            else
                lines[#lines + 1] = line
            end
            current_position = kobo_conf:seek()
        end
    end

    if not modified_brightness then
        if not correct_section then
            lines[#lines + 1] = '[PowerOptions]'
        end
        lines[#lines + 1] = 'FrontLightLevel=' .. new_intensity
    end

    if kobo_conf then
        remaining_file = kobo_conf:read("*a")
        kobo_conf:close()
    end

    kobo_conf_w = assert(io.open(kobo_conf_path, "w"))
    for i, line in ipairs(lines) do
      kobo_conf_w:write(line, "\n")
    end
    kobo_conf_w:write(remaining_file)
    kobo_conf_w:close()
    return true
end

return NickelConf
