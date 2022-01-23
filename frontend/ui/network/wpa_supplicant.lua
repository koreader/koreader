--[[--
WPA client helper for Kobo.
]]

local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local WpaClient = require("lj-wpaclient/wpaclient")
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

    local list
    list, err = wcli:scanThenGetResults()
    wcli:close()
    if list == nil then
        return nil, T("An error occurred while scanning: %1.", err)
    end

    local saved_networks = self:getAllSavedNetworks()
    local curr_network = self:getCurrentNetwork()

    for _, network in ipairs(list) do
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
    return string.match(out, "psk=([a-f0-9]+)")
end

--- Authenticates network.
function WpaSupplicant:authenticateNetwork(network)
    local wcli, reply, err

    wcli, err = WpaClient.new(self.wpa_supplicant.ctrl_interface)
    if not wcli then
        return false, T(CLIENT_INIT_ERR_MSG, err)
    end

    reply, err = wcli:addNetwork()
    if reply == nil then
        return false, err
    end
    local nw_id = reply

    reply, err = wcli:setNetwork(nw_id, "ssid", string.format("\"%s\"", network.ssid))
    if reply == nil or reply == "FAIL" then
        wcli:removeNetwork(nw_id)
        return false, T("An error occurred while selecting network: %1.", err)
    end
    -- if password is empty it’s an open AP
    if network.password and #network.password == 0 then -- Open AP
        reply, err = wcli:setNetwork(nw_id, "key_mgmt", "NONE")
        if reply == nil or reply == "FAIL" then
            wcli:removeNetwork(nw_id)
            return false, T("An error occurred while setting passwordless mode: %1.", err)
        end
    -- else it’s a WPA AP
    else
        if not network.psk then
            network.psk = calculatePsk(network.ssid, network.password)
            self:saveNetwork(network)
        end
        reply, err = wcli:setNetwork(nw_id, "psk", network.psk)
        if reply == nil or reply == "FAIL" then
            wcli:removeNetwork(nw_id)
            return false, T("An error occurred while setting password: %1.", err)
        end
    end
    wcli:enableNetworkByID(nw_id)

    wcli:attach()
    local cnt = 0
    local failure_cnt = 0
    local max_retry = 30
    local info = InfoMessage:new{text = _("Authenticating…")}
    local success = false
    local msg = _("Authenticated")
    UIManager:show(info)
    UIManager:forceRePaint()
    while cnt < max_retry do
        -- Start by checking if we're not actually connected already...
        -- NOTE: This is mainly to catch corner-cases where our preferred network list differs from the system's,
        --       and ours happened to be sorted earlier because of a better signal quality...
        local connected, state = wcli:getConnectedNetwork()
        if connected then
            network.wpa_supplicant_id = connected.id
            network.ssid = connected.ssid
            success = true
            break
        else
            if state then
                UIManager:close(info)
                -- Make the state prettier
                local first, rest = state:sub(1, 1), state:sub(2)
                info = InfoMessage:new{text = string.upper(first) .. string.lower(rest) .. "…"}
                UIManager:show(info)
                UIManager:forceRePaint()
            end
        end

        -- Otherwise, poke at the wpa_supplicant socket for a bit...
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
                success = true
                break
            elseif ev:isAuthFailed() then
                failure_cnt = failure_cnt + 1
                if failure_cnt > 3 then
                    success, msg = false, _("Failed to authenticate")
                    break
                end
            end
        else
            wcli:waitForEvent(1 * 1000)
            cnt = cnt + 1
        end
    end
    if success ~= true then
        wcli:removeNetwork(nw_id)
    end
    wcli:close()
    UIManager:close(info)
    UIManager:forceRePaint()
    if cnt >= max_retry then
        success, msg = false, _("Timed out")
    end
    return success, msg
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
