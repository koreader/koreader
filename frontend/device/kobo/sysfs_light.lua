-- Interface to the SysFS interface of the Kobo Aura One Frontlight.
-- This also supports the natural light, which consists of additional
-- red and green light LEDs.

local logger = require("logger")
local dbg = require("dbg")

local KoboSysfsLight = {
    frontlight_white = "/sys/class/backlight/lm3630a_led1b",
    frontlight_red = "/sys/class/backlight/lm3630a_led1a",
    frontlight_green = "/sys/class/backlight/lm3630a_ledb",
    current_brightness = 0,
    current_warmth = 0,
    white_gain = 25,
    red_gain = 24,
    green_gain = 24,
    white_offset = -25,
    red_offset = 0,
    green_offset = -65,
}

function KoboSysfsLight:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function KoboSysfsLight:setBrightness(brightness)
    self:setNaturalBrightness(brightness, self.current_warmth)
end

dbg:guard(KoboSysfsLight, 'setBrightness',
          function(self, brightness)
              assert(brightness >= 0 and brightness <= 100,
                     "Wrong brightness value given!")
          end)

function KoboSysfsLight:setWarmth(warmth)
    self:setNaturalBrightness(self.current_brightness, warmth)
end

dbg:guard(KoboSysfsLight, 'setWarmth',
          function(self, warmth)
              assert(warmth >= 0 and warmth <= 100,
                     "Wrong warmth value given!")
          end)

function KoboSysfsLight:setNaturalBrightness(brightness, warmth)
    -- On Nickel, the values for white/red/green are roughly linearly dependent
    -- on the 4th root of brightness and warmth.
    local white = math.min(self.white_gain * math.pow(brightness, 0.25) *
                       math.pow(100 - warmth, 0.25) + self.white_offset, 255)
    local red = math.min(self.red_gain * math.pow(brightness, 0.25) *
                     math.pow(warmth, 0.25) + self.red_offset, 255)
    local green = math.min(self.green_gain * math.pow(brightness, 0.25) *
                       math.pow(warmth, 0.25) + self.green_offset, 255)

    white = math.max(white, 0)
    red = math.max(red, 0)
    green = math.max(green, 0)

    self:_set_light_value(self.frontlight_white, math.floor(white))
    self:_set_light_value(self.frontlight_green, math.floor(green))
    self:_set_light_value(self.frontlight_red, math.floor(red))

    self.current_brightness = brightness
    self.current_warmth = warmth
end

dbg:guard(KoboSysfsLight, 'setNaturalBrightness',
          function(self, brightness, warmth)
              assert(brightness >= 0 and brightness <= 100,
                     "Wrong brightness value given!")
              assert(warmth >= 0 and warmth <= 100,
                     "Wrong warmth value given!")
          end)

function KoboSysfsLight:_set_light_value(sysfs_directory, value)
    -- bl_power is '31' when the light is turned on, '0' otherwise.
    if (value > 0) then
        self:_write_value(sysfs_directory .. "/bl_power", 31)
    else
        self:_write_value(sysfs_directory .. "/bl_power", 0)
    end
    self:_write_value(sysfs_directory .. "/brightness", value)
end

function KoboSysfsLight:_write_value(file, value)
    local f = io.open(file, "w")
    if not f then
        logger.err("Could not open file: ", file)
        return false
    end
    local ret, err_msg, err_code = f:write(value)
    io.close(f)
    if not ret then
        logger.err("Write error: ", err_msg, err_code)
        return false
    end
    return true
end

return KoboSysfsLight
