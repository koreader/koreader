local isAndroid, android = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")
local Screen = require("ui/device/screen")
local util = require("ffi/util")
local DEBUG = require("dbg")
local ffi = require("ffi")

local Device = {
    screen_saver_mode = false,
    charging_mode = false,
    survive_screen_saver = false,
    is_special_offers = nil,
    touch_dev = nil,
    model = nil,
    firmware_rev = nil,
    powerd = nil,
    has_no_keyboard = nil,
    is_touch_device = nil,
    has_front_light = nil,
    screen = Screen
}

Screen.device = Device

function Set (list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end

function Device:getModel()
    if self.model then return self.model end
    if util.isEmulated() then
        self.model = "Emulator"
        return self.model
    end
    self.model = ""
    local kindle_sn = io.open("/proc/usid", "r")
    if kindle_sn then
        local kindle_devcode = string.sub(kindle_sn:read(),3,4)
        kindle_sn:close()
        -- NOTE: Update me when new devices come out :)
        local k2_set = Set { "02", "03" }
        local dx_set = Set { "04", "05" }
        local dxg_set = Set { "09" }
        local k3_set = Set { "08", "06", "0A" }
        local k4_set = Set { "0E", "23" }
        local touch_set = Set { "0F", "11", "10", "12" }
        local pw_set = Set { "24", "1B", "1D", "1F", "1C", "20" }
        local pw2_set = Set { "D4", "5A", "D5", "D6", "D7", "D8", "F2", "17", "60", "F4", "F9", "62", "61", "5F" }

        if k2_set[kindle_devcode] then
            self.model = "Kindle2"
        elseif dx_set[kindle_devcode] then
            self.model = "Kindle2"
        elseif dxg_set[kindle_devcode] then
            self.model = "Kindle2"
        elseif k3_set[kindle_devcode] then
            self.model = "Kindle3"
        elseif k4_set[kindle_devcode] then
            self.model = "Kindle4"
        elseif touch_set[kindle_devcode] then
            self.model = "KindleTouch"
        elseif pw_set[kindle_devcode] then
            self.model = "KindlePaperWhite"
        elseif pw2_set[kindle_devcode] then
            self.model = "KindlePaperWhite2"
        end
    else
        local kg_test_fd = lfs.attributes("/bin/kobo_config.sh")
        if kg_test_fd then
            local std_out = io.popen("/bin/kobo_config.sh 2>/dev/null", "r")
            local codename = std_out:read()
            self.model = "Kobo_" .. codename
            local version_file = io.open("/mnt/onboard/.kobo/version", "r")
            self.firmware_rev = string.sub(version_file:read(),24,28)
            version_file:close()
        end
    end
    return self.model
end

function Device:getFirmVer()
    if not self.model then self:getModel() end
    return self.firmware_rev
end

function Device:isKindle4()
    return (self:getModel() == "Kindle4")
end

function Device:isKindle3()
    return (self:getModel() == "Kindle3")
end

function Device:isKindle2()
    return (self:getModel() == "Kindle2")
end

function Device:isKindle()
    local is_kindle = false
    local kindle_sn = io.open("/proc/usid", "r")
    if kindle_sn then
        is_kindle = true
        kindle_sn:close()
    end
    return is_kindle
end

function Device:isKobo()
    return string.find(self:getModel() or "", "Kobo_") == 1
end

Device.isAndroid = util.isAndroid

-- device has qwerty keyboard
function Device:hasKeyboard()
    if self.has_keyboard ~= nil then return self.has_keyboard end
    if not isAndroid then
        local model = self:getModel()
        self.has_keyboard = (model == "Kindle2") or (model == "Kindle3")
                            or util.isEmulated()
    else
        self.has_keyboard = ffi.C.AConfiguration_getKeyboard(android.app.config)
                            == ffi.C.ACONFIGURATION_KEYBOARD_QWERTY
    end
    return self.has_keyboard
end

function Device:hasNoKeyboard()
    return not self:hasKeyboard()
end

-- device has hardware keys for pagedown/pageup
function Device:hasKeys()
    if self.has_keys ~= nil then return self.has_keys end
    local model = self:getModel()
    self.has_keys = (model ~= "KindlePaperWhite") and (model ~= "KindlePaperWhite2")
                    and (model ~= "KindleTouch") and not self:isKobo()
    return self.has_keys
end

function Device:isTouchDevice()
    if self.is_touch_device ~= nil then return self.is_touch_device end
    if not isAndroid then
        local model = self:getModel()
        self.is_touch_device = (model == "KindlePaperWhite") or (model == "KindlePaperWhite2")
                            or (model == "KindleTouch") or self:isKobo() or util.isEmulated()
    else
        self.is_touch_device = ffi.C.AConfiguration_getTouchscreen(android.app.config)
                            ~= ffi.C.ACONFIGURATION_TOUCHSCREEN_NOTOUCH
    end
    return self.is_touch_device
end

function Device:hasFrontlight()
    if self.has_front_light ~= nil then return self.has_front_light end
    local model = self:getModel()
    self.has_front_light = (model == "KindlePaperWhite") or (model == "KindlePaperWhite2")
                        or (model == "Kobo_dragon") or (model == "Kobo_kraken") or (model == "Kobo_phoenix")
                        or util.isEmulated()
    return self.has_front_light
end

function Device:setTouchInputDev(dev)
    self.touch_dev = dev
end

function Device:getTouchInputDev()
    return self.touch_dev
end

function Device:intoScreenSaver()
    --os.execute("echo 'screensaver in' >> /mnt/us/event_test.txt")
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        --UIManager:show(InfoMessage:new{
            --text = "Going into screensaver... ",
            --timeout = 2,
        --})
        --util.sleep(1)
        --os.execute("killall -cont cvm")
        self.screen_saver_mode = true
    end
end

function Device:outofScreenSaver()
    --os.execute("echo 'screensaver out' >> /mnt/us/event_test.txt")
    if self.screen_saver_mode == true and self.charging_mode == false then
        -- wait for native system update screen before we recover saved
        -- Blitbuffer.
        util.usleep(1500000)
        --os.execute("killall -stop cvm")
        self.screen:restoreFromSavedBB()
        self.screen:refresh(0)
        self.survive_screen_saver = true
    end
    self.screen_saver_mode = false
end

function Device:onPowerEvent(ev)
    local Screensaver = require("ui/screensaver")
    local UIManager = require("ui/uimanager")
    if (ev == "Power" or ev == "Suspend") and not self.screen_saver_mode then
        DEBUG("Suspending...")
        -- always suspend in portrait mode
        self.orig_rotation_mode = Screen:getRotationMode()
        Screen:setRotationMode(0)
        Screensaver:show()
        self:prepareSuspend()
        UIManager:scheduleIn(2, function() self:Suspend() end)
    elseif (ev == "Power" or ev == "Resume") and self.screen_saver_mode then
        DEBUG("Resuming...")
        -- restore to previous rotation mode
        Screen:setRotationMode(self.orig_rotation_mode)
        self:Resume()
        Screensaver:close()
    end
end

function Device:prepareSuspend()
    local powerd = self:getPowerDevice()
    if powerd.fl ~= nil then
        -- in no case should the frontlight be turned on in suspend mode
        powerd.fl:sleep()
    end
    self.screen:refresh(0)
    self.screen_saver_mode = true
end

function Device:Suspend()
    if self:isKobo() then
        if KOBO_LIGHT_OFF_ON_SUSPEND then self:getPowerDevice():setIntensity(0) end
        os.execute("./suspend.sh")
    end
end

function Device:Resume()
    if self:isKobo() then
        os.execute("echo 0 > /sys/power/state-extended")
        local powerd = self:getPowerDevice()
        if powerd then
            if KOBO_LIGHT_ON_START and tonumber(KOBO_LIGHT_ON_START) > -1 then
                powerd:setIntensity(math.max(math.min(KOBO_LIGHT_ON_START,100),0))
            elseif powerd.fl ~= nil then
                powerd.fl:restore()
            end
        end
    end
    self.screen:refresh(1)
    self.screen_saver_mode = false
end

function Device:usbPlugIn()
    --os.execute("echo 'usb in' >> /mnt/us/event_test.txt")
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        --UIManager:show(InfoMessage:new{
            --text = "Going into USB mode... ",
            --timeout = 2,
        --})
        --util.sleep(1)
        --os.execute("killall -cont cvm")
    end
    self.charging_mode = true
end

function Device:usbPlugOut()
    --os.execute("echo 'usb out' >> /mnt/us/event_test.txt")
    if self.charging_mode == true and self.screen_saver_mode == false then
        --util.usleep(1500000)
        --os.execute("killall -stop cvm")
        self.screen:restoreFromSavedBB()
        self.screen:refresh(0)
    end

    --@TODO signal filemanager for file changes  13.06 2012 (houqp)
    self.charging_mode = false
end

function Device:getPowerDevice()
    if self.powerd ~= nil then
        return self.powerd
    else
        local model = self:getModel()
        if model == "KindleTouch" or model == "KindlePaperWhite" or model == "KindlePaperWhite2" then
            local KindlePowerD = require("ui/device/kindlepowerd")
            self.powerd = KindlePowerD:new{model = model}
        elseif self:isKobo() then
            local KoboPowerD = require("ui/device/kobopowerd")
            self.powerd = KoboPowerD:new()
        elseif self.isAndroid then
            local AndroidPowerd = require("ui/device/androidpowerd")
            self.powerd = AndroidPowerd:new()
        else -- emulated FrontLight
            local BasePowerD = require("ui/device/basepowerd")
            self.powerd = BasePowerD:new()
        end
    end
    return self.powerd
end

function Device:isSpecialOffers()
    if self.is_special_offers ~= nil then return self.is_special_offers end
    -- K5 only
    if self:isTouchDevice() and self:isKindle() then
        -- Look at the current blanket modules to see if the SO screensavers are enabled...
        local lipc = require("liblipclua")
        local lipc_handle = nil
        if lipc then
            lipc_handle = lipc.init("com.github.koreader.device")
        end
        if lipc_handle then
            local loaded_blanket_modules = lipc_handle:get_string_property("com.lab126.blanket", "load")
            if string.find(loaded_blanket_modules, "ad_screensaver") then
                self.is_special_offers = true
            end
            lipc_handle:close()
        else
        end
    end
    return self.is_special_offers
end

-- FIXME: this is a dirty hack, normally we don't need to get power device this early,
-- but Kobo devices somehow may need to init the frontlight module at startup?
-- because `kobolight = require("ffi/kobolight")` used to be in the `koreader-base` script
-- and run as the first line of koreader script no matter which device you are running on, 
-- which is utterly ugly. So I refactored it into the `init` method of `kobopowerd` and
-- `kobolight` will be init here. It's pretty safe to comment this line for non-kobo devices
-- so if kobo users find this line is useless, please don't hesitate to get rid of it.
local dummy_powerd = Device:getPowerDevice()

return Device
