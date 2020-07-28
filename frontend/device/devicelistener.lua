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

local DeviceListener = InputContainer:new{
    steps_fl = { 0.1, 0.1, 0.2, 0.4, 0.7, 1.1, 1.6, 2.2, 2.9, 3.7, 4.6, 5.6, 6.7, 7.9, 9.2, 10.6, },
}

function DeviceListener:onToggleNightMode()
    local night_mode = G_reader_settings:isTrue("night_mode")
    Screen:toggleNightMode()
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

local function lightFrontlight()
    return Device:hasLightLevelFallback() and G_reader_settings:nilOrTrue("light_fallback")
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
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1,
    })
    return true
end

function DeviceListener:onShowWarmth(value)
    local powerd = Device:getPowerDevice()
    if powerd.fl_warmth ~= nil then
        UIManager:show(Notification:new{
            text = T(_("Warmth set to %1."), powerd.fl_warmth),
            timeout = 1.0,
        })
    end
    return true
end

-- frontlight controller
if Device:hasFrontlight() then

    -- direction +1 - increase frontlight
    -- direction -1 - decrease frontlight
    function DeviceListener:onChangeFlIntensity(ges, direction)
        local powerd = Device:getPowerDevice()
        local delta_int
        --received gesture
        if type(ges) == "table" then
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
            if powerd.fl_intensity == nil then return false end

            local steps_tbl = {}
            local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
            for i = 1, #self.steps_fl, 1 do
                steps_tbl[i] = math.ceil(self.steps_fl[i] * scale)
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
        -- when using frontlight system settings
        if lightFrontlight() then
            UIManager:show(Notification:new{
                text = _("Frontlight controlled by system settings."),
                timeout = 2.5,
            })
            return true
        end

        local powerd = Device:getPowerDevice()
        if powerd.fl_warmth == nil then return false end

        if powerd.auto_warmth then
            UIManager:show(Notification:new{
                text = _("Warmth is handled automatically."),
                timeout = 1.0,
            })
            return true
        end

        local delta_int
        --received gesture
        if type(ges) == "table" then
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
            local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
            for i = 1, #self.steps_fl, 1 do
                steps_tbl[i] = math.ceil(self.steps_fl[i] * scale)
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
        local warmth = powerd.fl_warmth + direction * delta_int
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
        -- when using frontlight system settings
        if lightFrontlight() then
            UIManager:show(Notification:new{
                text = _("Frontlight controlled by system settings."),
                timeout = 2.5,
            })
            return true
        end
        local powerd = Device:getPowerDevice()
        powerd:toggleFrontlight()
        local new_text
        if powerd.is_fl_on then
            new_text = _("Frontlight enabled.")
        else
            new_text = _("Frontlight disabled.")
        end
        UIManager:show(Notification:new{
            text = new_text,
            timeout = 1.0,
        })
        return true
    end

    function DeviceListener:onShowFlDialog()
        local FrontLightWidget = require("ui/widget/frontlightwidget")
        UIManager:show(FrontLightWidget:new{
            use_system_fl = Device:hasLightLevelFallback()
        })
    end

end

if Device:canToggleGSensor() then
    function DeviceListener:onToggleGSensor()
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor(not G_reader_settings:isTrue("input_ignore_gsensor"))
        local new_text
        if G_reader_settings:isTrue("input_ignore_gsensor") then
            new_text = _("Accelerometer rotation events off.")
        else
            new_text = _("Accelerometer rotation events on.")
        end
        UIManager:show(Notification:new{
            text = new_text,
            timeout = 1.0,
        })
        return true
    end
end

function DeviceListener:onToggleRotation()
    local arg = bit.band((Screen:getRotationMode() + 1), 3)
    self.ui:handleEvent(Event:new("SetRotationMode", arg))
    return true
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
    self.ui:handleEvent(Event:new("UpdateFooter"))
    UIManager:setDirty("all", "full")
end

return DeviceListener
