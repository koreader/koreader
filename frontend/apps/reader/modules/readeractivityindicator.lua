-- Start with a empty stub, because 99.9% of users won't actually need this.
local ReaderActivityIndicator = {}

function ReaderActivityIndicator:isStub() return true end
function ReaderActivityIndicator:onStartActivityIndicator() end
function ReaderActivityIndicator:onStopActivityIndicator() end

-- Now, if we're on Kindle, and we haven't actually murdered Pillow, see what we can do...
local Device = require("device")

if Device:isKindle() then
    if os.getenv("PILLOW_HARD_DISABLED") or os.getenv("PILLOW_SOFT_DISABLED") then
        -- Pillow is dead, bye!
        return ReaderActivityIndicator
    end

    if not Device:isTouchDevice() then
        -- No lipc, bye!
        return ReaderActivityIndicator
    end
else
    -- Not on Kindle, bye!
    return ReaderActivityIndicator
end


-- Okay, if we're here, it's basically because we're running on a Kindle on FW 5.x under KPV
local EventListener = require("ui/widget/eventlistener")

ReaderActivityIndicator = EventListener:extend{
    lipc_handle = nil,
}

function ReaderActivityIndicator:isStub() return false end

function ReaderActivityIndicator:init()
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc then
        self.lipc_handle = lipc.init("com.github.koreader.activityindicator")
    end
end

function ReaderActivityIndicator:onStartActivityIndicator()
    if self.lipc_handle then
        -- check if activity indicator is needed
        if self.document.configurable.text_wrap == 1 then
            -- start indicator depends on pillow being enabled
            self.lipc_handle:set_string_property(
                "com.lab126.pillow", "activityIndicator",
                '{"activityIndicator":{ \
                    "action":"start","timeout":10000, \
                    "clientId":"com.github.koreader.activityindicator", \
                    "priority":true}}')
            self.indicator_started = true
        end
    end
    return true
end

function ReaderActivityIndicator:onStopActivityIndicator()
    if self.lipc_handle and self.indicator_started then
        -- stop indicator depends on pillow being enabled
        self.lipc_handle:set_string_property(
            "com.lab126.pillow", "activityIndicator",
            '{"activityIndicator":{ \
                "action":"stop","timeout":10000, \
                "clientId":"com.github.koreader.activityindicator", \
                "priority":true}}')
        self.indicator_started = false
    end
    return true
end

function ReaderActivityIndicator:onCloseWidget()
    if self.lipc_handle then
        self.lipc_handle:close()
    end
    self.lipc_handle = nil
end

return ReaderActivityIndicator
