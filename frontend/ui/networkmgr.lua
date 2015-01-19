local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Device = require("device")
local DEBUG = require("dbg")
local T = require("ffi/util").template
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
        text = _("Do you want to turn on Wifi?"),
        ok_callback = function()
            self:turnOnWifi()
        end,
    })
end

function NetworkMgr:promptWifiOff()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn off Wifi?"),
        ok_callback = function()
            self:turnOffWifi()
        end,
    })
end

function NetworkMgr:getWifiStatus()
    local socket = require("socket")
    return socket.dns.toip("www.google.com") ~= nil
end

function NetworkMgr:setHTTPProxy(proxy)
    local http = require("socket.http")
    http.PROXY = proxy
    if proxy then
        G_reader_settings:saveSetting("http_proxy", proxy)
        G_reader_settings:saveSetting("http_proxy_enabled", true)
    else
        G_reader_settings:saveSetting("http_proxy_enabled", false)
    end
end

function NetworkMgr:getWifiMenuTable()
    return {
        text = _("Wifi connection"),
        enabled_func = function() return Device:isKindle() or Device:isKobo() end,
        checked_func = function() return NetworkMgr:getWifiStatus() end,
        callback = function()
            if NetworkMgr:getWifiStatus() then
                NetworkMgr:promptWifiOff()
            else
                NetworkMgr:promptWifiOn()
            end
        end
    }
end

function NetworkMgr:getProxyMenuTable()
    local proxy_enabled = function()
        return G_reader_settings:readSetting("http_proxy_enabled")
    end
    local proxy = function()
        return G_reader_settings:readSetting("http_proxy")
    end
    return {
        text_func = function()
            return T(_("HTTP proxy %1"), (proxy_enabled() and proxy() or ""))
        end,
        checked_func = function() return proxy_enabled() end,
        callback = function()
            if not proxy_enabled() and proxy() then
                NetworkMgr:setHTTPProxy(proxy())
            elseif proxy_enabled() then
                NetworkMgr:setHTTPProxy(nil)
            end
            if not proxy() then
                UIManager:show(InfoMessage:new{
                    text = _("Tip:\nLong press on this menu entry to configure HTTP proxy."),
                })
            end
        end,
        hold_input = {
            title = _("Enter proxy address"),
            type = "text",
            hint = proxy() or "",
            callback = function(input)
                if input ~= "" then
                    NetworkMgr:setHTTPProxy(input)
                end
            end,
        }
    }
end

-- set network proxy if global variable NETWORK_PROXY is defined
if NETWORK_PROXY then
    NetworkMgr:setHTTPProxy(NETWORK_PROXY)
end

return NetworkMgr
