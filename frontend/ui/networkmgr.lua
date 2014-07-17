local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local DEBUG = require("dbg")
local _ = require("gettext")

local NetworkMgr = {}

local function kindleEnableWifi(toggle)
    local lipc = require("liblipclua")
    local lipc_handle = nil
    if lipc then
        lipc_handle = lipc.init("com.github.koreader.networkmgr")
    end
    if lipc_handle then
        lipc_handle:set_int_property("com.lab126.cmd", "wirelessEnable", toggle)
        lipc_handle:close()
    end
end

function NetworkMgr:turnOnWifi()
    if Device:isKindle() then
        kindleEnableWifi(1)
    elseif Device:isKobo() then
        -- TODO: turn on wifi on kobo?
    end
end

function NetworkMgr:turnOffWifi()
    if Device:isKindle() then
        kindleEnableWifi(0)
    elseif Device:isKobo() then
        -- TODO: turn off wifi on kobo?
    end
end

function NetworkMgr:promptWifiOn()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to Turn on Wifi?"),
        ok_callback = function()
            self:turnOnWifi()
        end,
    })
end

function NetworkMgr:promptWifiOff()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to Turn off Wifi?"),
        ok_callback = function()
            self:turnOffWifi()
        end,
    })
end

return NetworkMgr
