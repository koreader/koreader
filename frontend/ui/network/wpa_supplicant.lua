local UIManager = require("ui/uimanager")
local WpaClient = require('lj-wpaclient/wpaclient')
local InfoMessage = require("ui/widget/infomessage")
local sleep = require("ffi/util").sleep
local T = require("ffi/util").template
local _ = require("gettext")

local CLIENT_INIT_ERR_MSG = _("Failed to initialize network control client: %1.")

local WpaSupplicant = {}

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
            -- TODO: verify saved_nw.flags == network.flags? This will break if user changed the
            -- network setting from [WPA-PSK-TKIP+CCMP][WPS][ESS] to [WPA-PSK-TKIP+CCMP][ESS]
            network.password = saved_nw.password
        end
        -- TODO: also verify bssid if it is not set to any
        if curr_network and curr_network.ssid == network.ssid then
            network.connected = true
            network.wpa_supplicant_id = curr_network.id
        end
    end
    return list
end

function WpaSupplicant:authenticateNetwork(network)
    -- TODO: support passwordless network
    local err, wcli, nw_id
    wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if not wcli then
        return false, T(CLIENT_INIT_ERR_MSG, err)
    end

    nw_id, err = wcli:addNetwork()
    if err then return false, err end

    wcli:setNetwork(nw_id, "ssid", network.ssid)
    wcli:setNetwork(nw_id, "psk", network.password)
    wcli:enableNetworkByID(nw_id)

    wcli:attach()
    local cnt = 0
    local failure_cnt = 0
    local max_retry = 30
    local info = InfoMessage:new{text = _("Authenticating…")}
    local re, msg
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
            sleep(1)
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
