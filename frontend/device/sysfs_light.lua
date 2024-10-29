-- Generic frontlight SysFS interface.
-- This also supports the natural light, which consists of additional
-- red and green light LEDs.

local dbg = require("dbg")
local ffiUtil = require("ffi/util")

local SysfsLight = {
    frontlight_white = nil,
    frontlight_red = nil,
    frontlight_green = nil,
    frontlight_mixer = nil,
    frontlight_ioctl = nil,
    nl_min = nil,
    nl_max = nil,
    nl_inverted = nil,
    current_brightness = 0,
    current_warmth = 0,
    white_gain = 25,
    red_gain = 24,
    green_gain = 24,
    white_offset = -25,
    red_offset = 0,
    green_offset = -65,
    exponent = 0.25,
}

function SysfsLight:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function SysfsLight:setBrightness(brightness)
    self:setNaturalBrightness(brightness, nil)
end

dbg:guard(SysfsLight, 'setBrightness',
          function(self, brightness)
              assert(brightness >= 0 and brightness <= 100,
                     "Wrong brightness value given!")
          end)

function SysfsLight:setWarmth(warmth)
    self:setNaturalBrightness(nil, warmth)
end

dbg:guard(SysfsLight, 'setWarmth',
          function(self, warmth)
              assert(warmth >= 0 and warmth <= 100,
                     "Wrong warmth value given!")
          end)

--- @note: warmth is already in the *native* scale!
function SysfsLight:setNaturalBrightness(brightness, warmth)
    local set_brightness = true
    local set_warmth = true
    if not brightness then
        set_brightness = false
        brightness = self.current_brightness
    end
    if not warmth then
        set_warmth = false
        warmth = self.current_warmth
    end

    -- Newer devices use a mixer instead of writing values per color.
    if self.frontlight_mixer then
        if set_brightness then
            -- Prefer the ioctl, as it's much lower latency.
            if self.frontlight_ioctl then
                self.frontlight_ioctl:setBrightness(brightness)
            else
                ffiUtil.writeToSysfs(brightness, self.frontlight_white)
            end
        end
        -- The mixer might be using inverted values... (cold is nl_max, warm is nl_min)
        if set_warmth then
            if self.nl_inverted then
                ffiUtil.writeToSysfs(self.nl_max - warmth, self.frontlight_mixer)
            else
                ffiUtil.writeToSysfs(warmth, self.frontlight_mixer)
            end
        end
    else
        local red = 0
        local green = 0
        local white = 0
        if brightness > 0 then
            -- On Nickel, the values for white/red/green are roughly linearly dependent
            -- on the 4th root of brightness and warmth.
            white = math.min(self.white_gain * (brightness * (100 - warmth))^self.exponent + self.white_offset, 255)
        end
        if warmth > 0 then
            local brightness_warmth_exp = (brightness * warmth)^self.exponent
            red = math.min(self.red_gain * brightness_warmth_exp + self.red_offset, 255)
            green = math.min(self.green_gain * brightness_warmth_exp + self.green_offset, 255)
        end

        white = math.max(white, 0)
        red = math.max(red, 0)
        green = math.max(green, 0)

        self:_set_light_value(self.frontlight_white, math.floor(white))
        self:_set_light_value(self.frontlight_green, math.floor(green))
        self:_set_light_value(self.frontlight_red, math.floor(red))
    end

    self.current_brightness = brightness
    self.current_warmth = warmth
end

dbg:guard(SysfsLight, 'setNaturalBrightness',
          function(self, brightness, warmth)
              assert(brightness == nil or (brightness >= 0 and brightness <= 100),
                     "Wrong brightness value given!")
              assert(warmth == nil or (warmth >= 0 and warmth <= 100),
                     "Wrong warmth value given!")
          end)

function SysfsLight:_set_light_value(sysfs_directory, value)
    if not sysfs_directory then return end
    -- bl_power is '31' when the light is turned on, '0' otherwise.
    if (value > 0) then
        ffiUtil.writeToSysfs(31, sysfs_directory .. "/bl_power")
    else
        ffiUtil.writeToSysfs(0, sysfs_directory .. "/bl_power")
    end
    ffiUtil.writeToSysfs(value, sysfs_directory .. "/brightness")
end

return SysfsLight
