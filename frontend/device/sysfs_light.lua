-- Generic frontlight SysFS interface.
-- This also supports the natural light, which consists of additional
-- red and green light LEDs.

local logger = require("logger")
local dbg = require("dbg")

local SysfsLight = {
    frontlight_white = nil,
    frontlight_red = nil,
    frontlight_green = nil,
    frontlight_mixer = nil,
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
    bl_power_on = 31,
    bl_power_off = 0,
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

function SysfsLight:_brightness_to_raw(brightness, warmth, exponent, gain, offest)
    -- On Nickel, the values for white/red/green are roughly linearly dependent
    -- on the 4th root of brightness and warmth.
    return gain * math.pow(brightness * warmth, exponent) + offset
end

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

    -- Newer devices use a mixer instead of writting values per color.
    if self.frontlight_mixer then
        -- Honor the device's scale, which may not be [0...100] (f.g., it's [0...10] on the Forma) ;).
        warmth = math.floor(warmth / self.nl_max)
        if set_brightness then
            self:_write_value(self.frontlight_white, brightness)
        end
        -- And it may be inverted... (cold is nl_max, warm is nl_min)
        if set_warmth then
            if self.nl_inverted then
                self:_write_value(self.frontlight_mixer, self.nl_max - warmth)
            else
                self:_write_value(self.frontlight_mixer, warmth)
            end
        end
    else
        local red = 0
        local green = 0
        local white = 0
        if brightness > 0 then
            white = self:_brightness_to_raw(brightness, 100 - warmth,
                                            self.exponent, self.white_gain, self.white_offset)
        end
        if warmth > 0 then
            red = self:_brightness_to_raw(brightness, warmth,
                                          self.exponent, self.red_gain, self.red_offset)
            green = self:_brightness_to_raw(brightness, warmth,
                                            self.exponent, self.green_gain, self.green_offset)
        end

        white = math.min(math.max(white, 0), 255)
        red = math.min(math.max(red, 0), 255)
        green = math.min(math.max(green, 0), 255)

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

function SysfsLight:_get_bl_power(sysfs_directory)
    local bl_power = self:_read_value(sysfs_directory .. "/bl_power")
    if self.bl_power_on ~= nil and bl_power == self.bl_power_on then
        return true
    elseif self.bl_power_off ~= nil and bl_power == self.bl_power_off then
        return false
    else
        return nil
    end
end

function SysfsLight:_set_bl_power(sysfs_directory, is_on)
    if not sysfs_directory then return end
    local bl_power_directory = sysfs_directory .. "/bl_power"
    if is_on and self.bl_power_on ~= nil then
        return self:_write_value(bl_power_directory, self.bl_power_on)
    elseif not is_on and self.bl_power_off ~= nil then
        return self:_write_value(bl_power_directory, self.bl_power_off)
    else
        return false
    end
end

function SysfsLight:_get_light_value(sysfs_directory)
    if not sysfs_directory then return end
    local brightness = self:_read_value(sysfs_directory .. "/brightness")
    local is_on = self:_get_bl_power(sysfs_directory)
    return brightness, is_on
end

function SysfsLight:_set_light_value(sysfs_directory, value)
    if not sysfs_directory then return end
    self:_set_bl_power(sysfs_directory, value > 0)
    self:_write_value(sysfs_directory .. "/brightness", value)
end

function SysfsLight:_read_value(filename, value)
    local f = io.open(filename, "r")
    if not f then
        logger.err("Could not open file: ", filename)
        return
    end
    local ret = f:read("n")
    io.close(f)
    if ret == nil then
        logger.err("Read error.")
    end
    return ret
end

function SysfsLight:_write_value(file, value)
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

return SysfsLight
