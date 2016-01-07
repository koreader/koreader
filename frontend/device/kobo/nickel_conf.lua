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
    local correct_section = false
    local kobo_conf = assert(io.open(kobo_conf_path, "r"))
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
    return new_intensity
end

function NickelConf.frontLightLevel.set(new_intensity)
	assert(new_intensity >= 0 and new_intensity <= 100,
		"Wrong brightness value given!")

    local lines = {}
    local correct_section = false
    local kobo_conf = assert(io.open(kobo_conf_path, "r"))
    for line in kobo_conf:lines() do
        if string.match(line, re_AnySection) then
            correct_section = false
            if string.match(line, re_PowerOptionsSection) then
                correct_section = true
            end
        end
        old_intensity = string.match(line, re_FrontLightLevel)
        if correct_section and old_intensity then
            lines[#lines + 1] = string.gsub(line, re_BrightnessValue, new_intensity, 1)
            remaining_file = kobo_conf:read("*a")
            break
        else
            lines[#lines + 1] = line
        end
    end
    kobo_conf:close()

    kobo_conf = assert(io.open(kobo_conf_path, "w"))
    for i, line in ipairs(lines) do
      kobo_conf:write(line, "\n")
    end
    kobo_conf:write(remaining_file)
    kobo_conf:close()
end

return NickelConf
