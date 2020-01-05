local EventListener = require("ui/widget/eventlistener")
local Device = require("device")
local util = require("ffi/util")
-- lipc

local ReaderActivityIndicator = EventListener:new{}

function ReaderActivityIndicator:init()
    local dev_mod = Device.model
    if dev_mod == "KindlePaperWhite" or dev_mod == "KindlePaperWhite2" or dev_mod == "KindleVoyage" or dev_mod == "KindleBasic" or dev_mod == "KindlePaperWhite3" or dev_mod == "KindleOasis" or dev_mod == "KindleBasic2" or dev_mod == "KindleTouch" then
        if (pcall(require, "liblipclua")) then
            self.lipc_handle = lipc.init("com.github.koreader.activityindicator")
        end
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
        util.usleep(1000000)
    end
    return true
end

function ReaderActivityIndicator:coda()
    if self.lipc_handle then
        self.lipc_handle:close()
    end
end

return ReaderActivityIndicator
