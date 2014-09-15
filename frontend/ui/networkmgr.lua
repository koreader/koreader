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

local function koboEnableWifi(toggle)
    if toggle == 1 then
        local path = "/etc/wpa_supplicant/wpa_supplicant.conf"
        os.execute("insmod /drivers/ntx508/wifi/sdio_wifi_pwr.ko 2>/dev/null")
        os.execute("insmod /drivers/ntx508/wifi/dhd.ko")
        os.execute("sleep 1")
        os.execute("ifconfig eth0 up")
        os.execute("wlarm_le -i eth0 up")
        os.execute("wpa_supplicant -s -i eth0 -c "..path.." -C /var/run/wpa_supplicant -B")
        os.execute("udhcpc -S -i eth0 -s /etc/udhcpc.d/default.script -t15 -T10 -A3 -b -q >/dev/null 2>&1")
    else
        os.execute("killall udhcpc wpa_supplicant 2>/dev/null")
        os.execute("wlarm_le -i eth0 down")
        os.execute("ifconfig eth0 down")
        os.execute("rmmod -r dhd")
        os.execute("rmmod -r sdio_wifi_pwr")
    end
end

function NetworkMgr:turnOnWifi()
    if Device:isKindle() then
        kindleEnableWifi(1)
    elseif Device:isKobo() then
        koboEnableWifi(1)
    end
end

function NetworkMgr:turnOffWifi()
    if Device:isKindle() then
        kindleEnableWifi(0)
    elseif Device:isKobo() then
        koboEnableWifi(0)
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

function NetworkMgr:getWifiStatus()
    local default_string = io.popen("ip r | grep default")
    local result = default_string:read()
    if result ~= nil then
        local gateway = string.match(result,"%d+.%d+.%d+.%d+")
        if os.execute("ping -q -c1 "..gateway) == 0 then
            return true
      end -- ping to gateway
    end -- test for empty string
    return false
end

return NetworkMgr
