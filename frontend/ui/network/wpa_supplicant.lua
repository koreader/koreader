--[[--
WPA client helper for Kobo.
]]

local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local WpaClient = require('lj-wpaclient/wpaclient')
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = FFIUtil.template

local CLIENT_INIT_ERR_MSG = _("Failed to initialize network control client: %1.")

local WpaSupplicant = {}

--- Gets network list.
function WpaSupplicant:getNetworkList()
    local wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if wcli == nil then
        return nil, T(CLIENT_INIT_ERR_MSG, err)
    end

    local list = wcli:scanThenGetResults()
    wcli:close()

    local saved_networks = self:getAllSavedNetworks()
    local curr_network = self:getCurrentNetwork()

    for _,network in ipairs(list) do
        network.signal_quality = network:getSignalQuality()
        local saved_nw = saved_networks:readSetting(network.ssid)
        if saved_nw then
            --- @todo verify saved_nw.flags == network.flags? This will break if user changed the
            -- network setting from [WPA-PSK-TKIP+CCMP][WPS][ESS] to [WPA-PSK-TKIP+CCMP][ESS]
            network.password = saved_nw.password
            network.psk = saved_nw.psk
        end
        --- @todo also verify bssid if it is not set to any
        if curr_network and curr_network.ssid == network.ssid then
            network.connected = true
            network.wpa_supplicant_id = curr_network.id
        end
    end
    return list
end

local function calculatePsk(ssid, pwd)
    --- @todo calculate PSK with native function instead of shelling out
    -- hostap's reference implementation is available at:
    --   * /wpa_supplicant/wpa_passphrase.c
    --   * /src/crypto/sha1-pbkdf2.c
    -- see: <http://docs.ros.org/diamondback/api/wpa_supplicant/html/sha1-pbkdf2_8c_source.html>
    local fp = io.popen(("wpa_passphrase %q %q"):format(ssid, pwd))
    local out = fp:read("*a")
    fp:close()
    return string.match(out, 'psk=([a-f0-9]+)')
end

--- Authenticates network.
function WpaSupplicant:authenticateNetwork(network)
    local err, wcli, nw_id
    --- @todo support passwordless network
    wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if not wcli then
        return false, T(CLIENT_INIT_ERR_MSG, err)
    end

    nw_id, err = wcli:addNetwork()
    if err then return false, err end

    local re = wcli:setNetwork(nw_id, "ssid", string.format("\"%s\"", network.ssid))
    if re == 'FAIL' then
        wcli:removeNetwork(nw_id)
        return false, _("An error occurred while selecting network.")
    end
    if not network.psk then
        network.psk = calculatePsk(network.ssid, network.password)
        self:saveNetwork(network)
    end
    re = wcli:setNetwork(nw_id, "psk", network.psk)
    if re == 'FAIL' then
        wcli:removeNetwork(nw_id)
        return false, _("An error occurred while setting password.")
    end
    wcli:enableNetworkByID(nw_id)

    wcli:attach()
    local cnt = 0
    local failure_cnt = 0
    local max_retry = 30
    local info = InfoMessage:new{text = _("Authenticating…")}
    local msg
    UIManager:show(info)
    UIManager:forceRePaint()
    while cnt < max_retry do
        local ev = wcli:readEvent()
        if ev ~= nil then
            if not ev:isScanEvent() then
                UIManager:close(info)
                info = InfoMessage:new{text = ev.msg}
                UIManager:show(info)
                UIManager:forceRePaint()
            end
            if ev:isAuthSuccessful() then
                network.wpa_supplicant_id = nw_id
                re = true
                break
            elseif ev:isAuthFailed() then
                failure_cnt = failure_cnt + 1
                if failure_cnt > 3 then
                    re, msg = false, _('Failed to authenticate')
                    break
                end
            end
        else
            FFIUtil.sleep(1)
            cnt = cnt + 1
        end
    end
    if re ~= true then wcli:removeNetwork(nw_id) end
    wcli:close()
    UIManager:close(info)
    UIManager:forceRePaint()
    if cnt >= max_retry then
        re, msg = false, _('Timed out')
    end
    return re, msg
end

function WpaSupplicant:disconnectNetwork(network)
    if not network.wpa_supplicant_id then return end
    local wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if wcli == nil then
        return nil, T(CLIENT_INIT_ERR_MSG, err)
    end
    wcli:removeNetwork(network.wpa_supplicant_id)
    wcli:close()
end

function WpaSupplicant:getCurrentNetwork()
    local wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if wcli == nil then
        return nil, T(CLIENT_INIT_ERR_MSG, err)
    end
    local nw = wcli:getCurrentNetwork()
    wcli:close()
    return nw
end

function WpaSupplicant.init(network_mgr, options)
    network_mgr.wpa_supplicant = {ctrl_interface = options.ctrl_interface}
    network_mgr.getNetworkList = WpaSupplicant.getNetworkList
    network_mgr.getCurrentNetwork = WpaSupplicant.getCurrentNetwork
    network_mgr.authenticateNetwork = WpaSupplicant.authenticateNetwork
    network_mgr.disconnectNetwork = WpaSupplicant.disconnectNetwork
end

return WpaSupplicant
