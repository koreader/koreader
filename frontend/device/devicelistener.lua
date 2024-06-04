local Device = require("device")
local Event = require("ui/event")
local EventListener = require("ui/widget/eventlistener")
local Notification = require("ui/widget/notification")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local bit = require("bit")
local _ = require("gettext")
local T = require("ffi/util").template

local DeviceListener = EventListener:extend{}

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

function DeviceListener:onShowWarmth()
    if not Device:hasNaturalLight() then return true end
    -- Display it in the native scale, like FrontLightWidget
    local powerd = Device:getPowerDevice()
    Notification:notify(T(_("Warmth set to %1."), powerd:toNativeWarmth(powerd:frontlightWarmth())))
    return true
end

-- frontlight controller
if Device:hasFrontlight() then
    local function calculateGestureDelta(ges, direction, min, max)
        local delta_int
        if type(ges) == "table" then
            local gesture_multiplier
            if ges.ges == "two_finger_swipe" or ges.ges == "swipe" then
                gesture_multiplier = 0.8
            else
                gesture_multiplier = 1
            end

            local gestureScale
            if ges.direction == "south" or ges.direction == "north" then
                gestureScale = Screen:getHeight() * gesture_multiplier
            elseif ges.direction == "west" or ges.direction == "east" then
                gestureScale = Screen:getWidth() * gesture_multiplier
            else
                local width = Screen:getWidth()
                local height = Screen:getHeight()
                -- diagonal
                gestureScale = math.sqrt(width^2 + height^2) * gesture_multiplier
            end

            -- In case we're passed a gesture that doesn't imply movement (e.g., tap or hold)
            if ges.distance == nil then
                ges.distance = 1
            end

            -- delta_int is calculated by a function f(x) = coeff * x^2
            -- *) f(x) has the boundary condition: f(1) = max/2;
            -- *) x is roughly the swipe distance as a fraction of the screen geometry,
            --    clamped between 0 and 1
            local x = math.min(1, ges.distance / gestureScale)
            delta_int = math.ceil(1/2 * max * x^2)
        else
            -- The ges arg passed by our caller wasn't a gesture, but an absolute integer increment
            delta_int = ges
        end
        if direction ~= -1 and direction ~= 1 then
            -- If the caller didn't specify, opt to *increase* by default
            direction = 1
        end
        return direction * delta_int
    end

    -- direction +1 - increase frontlight
    -- direction -1 - decrease frontlight
    function DeviceListener:onChangeFlIntensity(ges, direction)
        local powerd = Device:getPowerDevice()
        local delta = calculateGestureDelta(ges, direction, powerd.fl_min, powerd.fl_max)

        local new_intensity = powerd:frontlightIntensity() + delta
        -- when new_intensity <= 0, toggle light off
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
        if not Device:hasNaturalLight() then return true end

        local powerd = Device:getPowerDevice()
        local delta = calculateGestureDelta(ges, direction, powerd.fl_warmth_min, powerd.fl_warmth_max)

        -- Given that the native warmth ranges are usually pretty restrictive (e.g., [0, 10] or [0, 24]),
        -- do the computations in the native scale, to ensure we always actually *change* something,
        -- in case both the old and new value would round to the same native step,
        -- despite being different in the API scale, which is stupidly fixed at [0, 100]...
        local warmth = powerd:fromNativeWarmth(powerd:toNativeWarmth(powerd:frontlightWarmth()) + delta)

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
        local new_text
        if powerd:isFrontlightOn() then
            new_text = _("Frontlight disabled.")
        else
            new_text = _("Frontlight enabled.")
        end
        -- We defer displaying the Notification to PowerD, as the toggle may be a ramp, and we both want to make sure the refresh fencing won't affect it, and that we only display the Notification at the end...
        local notif_source = Notification.notify_source
        local notif_cb = function()
            Notification:notify(new_text, notif_source)
        end
        if not powerd:toggleFrontlight(notif_cb) then
            Notification:notify(_("Frontlight unchanged."), notif_source)
        end
    end

    function DeviceListener:onShowFlDialog()
        Device:showLightDialog()
    end

end

if Device:hasGSensor() then
    function DeviceListener:onToggleGSensor()
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor(not G_reader_settings:isTrue("input_ignore_gsensor"))
        local new_text
        if G_reader_settings:isTrue("input_ignore_gsensor") then
            new_text = _("Accelerometer rotation events off.")
        else
            new_text = _("Accelerometer rotation events on.")
        end
        Notification:notify(new_text)
        return true
    end

    function DeviceListener:onLockGSensor()
        G_reader_settings:flipNilOrFalse("input_lock_gsensor")
        Device:lockGSensor(G_reader_settings:isTrue("input_lock_gsensor"))
        local new_text
        if G_reader_settings:isTrue("input_lock_gsensor") then
            new_text = _("Orientation locked.")
        else
            new_text = _("Orientation unlocked.")
        end
        Notification:notify(new_text)
        return true
    end
end

if not Device:isAlwaysFullscreen() then
    function DeviceListener:onToggleFullscreen()
        Device:toggleFullscreen()
    end
end

function DeviceListener:onIterateRotation(ccw)
    -- Simply rotate by 90° CW or CCW
    local step = ccw and -1 or 1
    local arg = bit.band(Screen:getRotationMode() + step, 3)
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
        G_reader_settings:makeTrue("refresh_on_chapter_boundaries")
    else
        G_reader_settings:delSetting("refresh_on_chapter_boundaries")
    end
end

function DeviceListener:onToggleFlashOnChapterBoundaries()
    G_reader_settings:flipNilOrFalse("refresh_on_chapter_boundaries")
end

function DeviceListener:onSetNoFlashOnSecondChapterPage(toggle)
    if toggle == true then
        G_reader_settings:makeTrue("no_refresh_on_second_chapter_page")
    else
        G_reader_settings:delSetting("no_refresh_on_second_chapter_page")
    end
end

function DeviceListener:onToggleNoFlashOnSecondChapterPage()
    G_reader_settings:flipNilOrFalse("no_refresh_on_second_chapter_page")
end

function DeviceListener:onSetFlashOnPagesWithImages(toggle)
    if toggle == true then
        G_reader_settings:delSetting("refresh_on_pages_with_images")
    else
        G_reader_settings:makeFalse("refresh_on_pages_with_images")
    end
end

function DeviceListener:onToggleFlashOnPagesWithImages()
    G_reader_settings:flipNilOrTrue("refresh_on_pages_with_images")
end

function DeviceListener:onSwapPageTurnButtons()
    G_reader_settings:flipNilOrFalse("input_invert_page_turn_keys")
    Device:invertButtons()
end

function DeviceListener:onToggleKeyRepeat(toggle)
    if toggle == true then
        G_reader_settings:makeFalse("input_no_key_repeat")
    elseif toggle == false then
        G_reader_settings:makeTrue("input_no_key_repeat")
    else
        G_reader_settings:flipNilOrFalse("input_no_key_repeat")
    end
    Device:toggleKeyRepeat(G_reader_settings:nilOrFalse("input_no_key_repeat"))
end

function DeviceListener:onRequestUSBMS()
    local MassStorage = require("ui/elements/mass_storage")
    -- It already takes care of the canToggleMassStorage cap check for us
    -- NOTE: Never request confirmation, it's sorted right next to exit, restart & friends in Dispatcher,
    --       and they don't either...
    MassStorage:start(false)
end

function DeviceListener:onRestart()
    self.ui.menu:exitOrRestart(function() UIManager:restartKOReader() end)
end

function DeviceListener:onRequestSuspend()
    UIManager:suspend()
end

function DeviceListener:onRequestReboot()
    UIManager:askForReboot()
end

function DeviceListener:onRequestPowerOff()
    UIManager:askForPowerOff()
end

function DeviceListener:onExit(callback)
    self.ui.menu:exitOrRestart(callback)
end

function DeviceListener:onFullRefresh()
    if self.ui and self.ui.view then
        self.ui:handleEvent(Event:new("UpdateFooter", self.ui.view.footer_visible))
    end
    UIManager:setDirty(nil, "full")
end

-- On resume, make sure we restore Gestures handling in InputContainer, to avoid confusion for scatter-brained users ;).
-- It's also helpful when the IgnoreTouchInput event is emitted by Dispatcher through other means than Gestures.
function DeviceListener:onResume()
    UIManager:setIgnoreTouchInput(false)
end

return DeviceListener
