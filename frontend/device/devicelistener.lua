local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local bit = require("bit")
local _ = require("gettext")
local T = require("ffi/util").template

local DeviceListener = InputContainer:new{}

local function _setSetting(name)
    G_reader_settings:makeTrue(name)
end

local function _unsetSetting(name)
    G_reader_settings:delSetting(name)
end

local function _toggleSetting(name)
    G_reader_settings:flipNilOrFalse(name)
end

function DeviceListener:onToggleNightMode()
    local night_mode = G_reader_settings:isTrue("night_mode")
    Screen:toggleNightMode()
    -- Make sure CRe will bypass the call cache
    if self.ui and self.ui.document and self.ui.document.provider == "crengine" then
        self.ui.document:resetCallCache()
    end
    UIManager:setDirty("all", "full")
    UIManager:ToggleNightMode(not night_mode)
    G_reader_settings:saveSetting("night_mode", not night_mode)
end

function DeviceListener:onSetNightMode(night_mode_on)
    local night_mode = G_reader_settings:isTrue("night_mode")
    if night_mode_on ~= night_mode then
        self:onToggleNightMode()
    end
end

function DeviceListener:onShowIntensity()
    if not Device:hasFrontlight() then return true end
    local powerd = Device:getPowerDevice()
    local new_text
    if powerd:isFrontlightOff() then
        new_text = _("Frontlight disabled.")
    else
        new_text = T(_("Frontlight intensity set to %1."), powerd:frontlightIntensity())
    end
    Notification:notify(new_text)
    return true
end

function DeviceListener:onShowWarmth(value)
    local powerd = Device:getPowerDevice()
    if powerd.fl_warmth ~= nil then
        -- powerd.fl_warmth holds the warmth-value in the internal koreader scale [0,100]
        -- powerd.fl_warmth_max is the maximum value the hardware accepts
        Notification:notify(T(_("Warmth set to %1."), math.floor(powerd.fl_warmth/100*powerd.fl_warmth_max)))
    end
    return true
end

-- frontlight controller
if Device:hasFrontlight() then

    local function calculateGestureDelta(ges, direction, min, max)
        local delta_int
        if type(ges) == "table" then
            -- here we are using just two scales
            -- big scale is for high dynamic ranges (e.g. brightness from 1..100)
            --           original scale maybe tuned by hand
            -- small scale is for lower dynamic ranges (e.g. warmth from 1..10)
            --           scale entries are calculated by math.round(1*sqrt(2)^n)
            local steps_fl_big_scale = { 0.1, 0.1, 0.2, 0.4, 0.7, 1.1, 1.6, 2.2, 2.9, 3.7, 4.6, 5.6, 6.7, 7.9, 9.2, 10.6, }
            local steps_fl_small_scale = { 1.0, 1.0, 2.0, 3.0, 4.0, 6.0, 8.1, 11.3 }
            local steps_fl = steps_fl_big_scale
            if (max - min) < 50  then
                steps_fl = steps_fl_small_scale
            end
            local gestureScale
            local scale_multiplier
            if ges.ges == "two_finger_swipe" then
                -- for backward compatibility
                scale_multiplier = FRONTLIGHT_SENSITIVITY_DECREASE * 0.8
            elseif ges.ges == "swipe" then
                scale_multiplier = 0.8
            else
                scale_multiplier = 1
            end

            if ges.direction == "south" or ges.direction == "north" then
                gestureScale = Screen:getHeight() * scale_multiplier
            elseif ges.direction == "west" or ges.direction == "east" then
                gestureScale = Screen:getWidth() * scale_multiplier
            else
                local width = Screen:getWidth()
                local height = Screen:getHeight()
                -- diagonal
                gestureScale = math.sqrt(width * width + height * height) * scale_multiplier
            end

            local steps_tbl = {}
            local scale = (max - min) / steps_fl[#steps_fl] / 2 -- full swipe gives half scale
            for i = 1, #steps_fl, 1 do
                steps_tbl[i] = math.ceil(steps_fl[i] * scale)
            end

            if ges.distance == nil then
                ges.distance = 1
            end

            local step = math.ceil(#steps_tbl * ges.distance / gestureScale)
            delta_int = steps_tbl[step] or steps_tbl[#steps_tbl]
        else
            -- received amount to change
            delta_int = ges
        end
        if direction ~= -1 and direction ~= 1 then
            -- set default value (increase frontlight)
            direction = 1
        end
        return direction, delta_int
    end

    -- direction +1 - increase frontlight
    -- direction -1 - decrease frontlight
    function DeviceListener:onChangeFlIntensity(ges, direction)
        local powerd = Device:getPowerDevice()
        local delta_int
        --received gesture

        direction, delta_int = calculateGestureDelta(ges, direction, powerd.fl_min, powerd.fl_max)

        local new_intensity = powerd.fl_intensity + direction * delta_int
        if new_intensity == nil then return true end
        -- when new_intensity <=0, toggle light off
        self:onSetFlIntensity(new_intensity)
        self:onShowIntensity()
        return true
    end

    function DeviceListener:onSetFlIntensity(new_intensity)
        local powerd = Device:getPowerDevice()
        if new_intensity <= 0 then
            powerd:turnOffFrontlight()
        else
            powerd:setIntensity(new_intensity)
        end
        return true
    end

    function DeviceListener:onIncreaseFlIntensity(ges)
        self:onChangeFlIntensity(ges, 1)
        return true
    end

    function DeviceListener:onDecreaseFlIntensity(ges)
        self:onChangeFlIntensity(ges, -1)
        return true
    end

    -- direction +1 - increase frontlight warmth
    -- direction -1 - decrease frontlight warmth
    function DeviceListener:onChangeFlWarmth(ges, direction)
        local powerd = Device:getPowerDevice()
        if powerd.fl_warmth == nil then return false end

        if powerd.auto_warmth then
            Notification:notify(_("Warmth is handled automatically."))
            return true
        end

        local delta_int
        --received gesture

        direction, delta_int = calculateGestureDelta(ges, direction, powerd.fl_warmth_min, powerd.fl_warmth_max)

        local warmth = math.floor(powerd.fl_warmth + direction * delta_int * 100 / powerd.fl_warmth_max)
        self:onSetFlWarmth(warmth)
        self:onShowWarmth()
        return true
    end

    function DeviceListener:onSetFlWarmth(warmth)
        local powerd = Device:getPowerDevice()
        if warmth > 100 then
            warmth = 100
        elseif warmth < 0 then
            warmth = 0
        end
        powerd:setWarmth(warmth)
        return true
    end

    function DeviceListener:onIncreaseFlWarmth(ges)
        self:onChangeFlWarmth(ges, 1)
    end

    function DeviceListener:onDecreaseFlWarmth(ges)
        self:onChangeFlWarmth(ges, -1)
    end

    function DeviceListener:onToggleFrontlight()
        local powerd = Device:getPowerDevice()
        powerd:toggleFrontlight()
        local new_text
        if powerd.is_fl_on then
            new_text = _("Frontlight enabled.")
        else
            new_text = _("Frontlight disabled.")
        end
        Notification:notify(new_text)
        return true
    end

    function DeviceListener:onShowFlDialog()
        Device:showLightDialog()
    end

end

if Device:canToggleGSensor() then
    function DeviceListener:onToggleGSensor()
        _toggleSetting("input_ignore_gsensor")
        Device:toggleGSensor(not G_reader_settings:isTrue("input_ignore_gsensor"))
        local new_text
        if G_reader_settings:isTrue("input_ignore_gsensor") then
            new_text = _("Accelerometer rotation events off.")
        else
            new_text = _("Accelerometer rotation events on.")
        end
        UIManager:show(Notification:new{
            text = new_text,
        })
        return true
    end
end

function DeviceListener:onIterateRotation()
    -- Simply rotate by 90° CW
    local arg = bit.band(Screen:getRotationMode() + 1, 3)
    self.ui:handleEvent(Event:new("SetRotationMode", arg))
    return true
end

function DeviceListener:onInvertRotation()
    -- Invert is always rota + 2, w/ wraparound
    local arg = bit.band(Screen:getRotationMode() + 2, 3)
    self.ui:handleEvent(Event:new("SetRotationMode", arg))
    return true
end

function DeviceListener:onSwapRotation()
    local rota = Screen:getRotationMode()
    -- Portrait is always even, Landscape is always odd. For each of 'em, Landscape = Portrait + 1.
    -- As such...
    local arg
    if bit.band(rota, 1) == 0 then
        -- If Portrait, Landscape is +1
        arg = bit.band(rota + 1, 3)
    else
        -- If Landscape, Portrait is -1
        arg = bit.band(rota - 1, 3)
    end
    self.ui:handleEvent(Event:new("SetRotationMode", arg))
    return true
end

function DeviceListener:onSetRefreshRates(day, night)
    UIManager:setRefreshRate(day, night)
end

function DeviceListener:onSetBothRefreshRates(rate)
    UIManager:setRefreshRate(rate, rate)
end

function DeviceListener:onSetDayRefreshRate(day)
    UIManager:setRefreshRate(day, nil)
end

function DeviceListener:onSetNightRefreshRate(night)
    UIManager:setRefreshRate(nil, night)
end

function DeviceListener:onSetFlashOnChapterBoundaries(toggle)
    if toggle == true then
        _setSetting("refresh_on_chapter_boundaries")
    else
        _unsetSetting("refresh_on_chapter_boundaries")
    end
end

function DeviceListener:onToggleFlashOnChapterBoundaries()
    _toggleSetting("refresh_on_chapter_boundaries")
end

function DeviceListener:onSetNoFlashOnSecondChapterPage(toggle)
    if toggle == true then
        _setSetting("no_refresh_on_second_chapter_page")
    else
        _unsetSetting("no_refresh_on_second_chapter_page")
    end
end

function DeviceListener:onToggleNoFlashOnSecondChapterPage()
    _toggleSetting("no_refresh_on_second_chapter_page")
end

if Device:canReboot() then
    function DeviceListener:onReboot()
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to reboot the device?"),
            ok_text = _("Reboot"),
            ok_callback = function()
                UIManager:nextTick(UIManager.reboot_action)
            end,
        })
    end
end

if Device:canPowerOff() then
    function DeviceListener:onPowerOff()
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to power off the device?"),
            ok_text = _("Power off"),
            ok_callback = function()
                UIManager:nextTick(UIManager.poweroff_action)
            end,
        })
    end
end

function DeviceListener:onSuspendEvent()
    UIManager:suspend()
end

function DeviceListener:onExit(callback)
    self.ui.menu:exitOrRestart(callback)
end

function DeviceListener:onRestart()
    self.ui.menu:exitOrRestart(function() UIManager:restartKOReader() end)
end

function DeviceListener:onFullRefresh()
    if self.ui and self.ui.view then
        self.ui:handleEvent(Event:new("UpdateFooter", self.ui.view.footer_visible))
    end
    UIManager:setDirty(nil, "full")
end

return DeviceListener
