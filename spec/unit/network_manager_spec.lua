describe("network_manager module", function()
    local Device
    local turn_on_wifi_called
    local turn_off_wifi_called
    local obtain_ip_called
    local release_ip_called

    local function clearState()
        G_reader_settings:saveSetting("auto_restore_wifi", true)
        turn_on_wifi_called = 0
        turn_off_wifi_called = 0
        obtain_ip_called = 0
        release_ip_called = 0
    end

    setup(function()
        require("commonrequire")
        Device = require("device")
        function Device:initNetworkManager(NetworkMgr)
            function NetworkMgr:turnOnWifi(callback)
                turn_on_wifi_called = turn_on_wifi_called + 1
                if callback then
                    callback()
                end
            end
            function NetworkMgr:turnOffWifi(callback)
                turn_off_wifi_called = turn_off_wifi_called + 1
                if callback then
                    callback()
                end
            end
            function NetworkMgr:obtainIP(callback)
                obtain_ip_called = obtain_ip_called + 1
                if callback then
                    callback()
                end
            end
            function NetworkMgr:releaseIP(callback)
                release_ip_called = release_ip_called + 1
                if callback then
                    callback()
                end
            end
            function NetworkMgr:restoreWifiAsync()
                self:turnOnWifi()
                self:obtainIP()
            end
        end
        function Device:hasWifiRestore()
            return true
        end
    end)

    it("should restore wifi in init if wifi was on", function()
        package.loaded["ui/network/manager"] = nil
        clearState()
        G_reader_settings:saveSetting("wifi_was_on", true)
        local network_manager = require("ui/network/manager") --luacheck: ignore
        assert.is.same(turn_on_wifi_called, 1)
        assert.is.same(turn_off_wifi_called, 0)
        assert.is.same(obtain_ip_called, 1)
        assert.is.same(release_ip_called, 0)
    end)

    it("should not restore wifi in init if wifi was off", function()
        package.loaded["ui/network/manager"] = nil
        clearState()
        G_reader_settings:saveSetting("wifi_was_on", false)
        local network_manager = require("ui/network/manager") --luacheck: ignore
        assert.is.same(turn_on_wifi_called, 0)
        assert.is.same(turn_off_wifi_called, 0)
        assert.is.same(obtain_ip_called, 0)
        assert.is.same(release_ip_called, 0)
    end)

    teardown(function()
        function Device:initNetworkManager() end
        function Device:hasWifiRestore() return false end
        package.loaded["ui/network/manager"] = nil
    end)
end)

describe("NetworkMgr:reconnectOrShowNetworkMenu background-association wait", function()
    local NetworkMgr
    local Device
    local UIManager
    local get_current_network_calls

    setup(function()
        require("commonrequire")
        Device = require("device")
        function Device:initNetworkManager(mgr)
            function mgr:turnOnWifi() end
            function mgr:turnOffWifi() end
            function mgr:obtainIP() end
            function mgr:releaseIP() end
            function mgr:restoreWifiAsync() end
        end
        function Device:hasWifiRestore() return false end
        -- Simulate a wpa_supplicant-capable device (like Kobo)
        function Device:hasWifiManager() return true end
    end)

    before_each(function()
        package.loaded["ui/network/manager"] = nil
        G_reader_settings:saveSetting("wifi_was_on", false)
        NetworkMgr = require("ui/network/manager")
        get_current_network_calls = 0
        UIManager = require("ui/uimanager")
        -- Silence UI calls in headless test env
        UIManager.show = function() end
        UIManager.close = function() end
        UIManager.forceRePaint = function() end
        -- Default stubs for network methods
        function NetworkMgr:authenticateNetwork(_network) return false, "auth failed" end
        function NetworkMgr:getCurrentNetwork()
            get_current_network_calls = get_current_network_calls + 1
            return {ssid = "FoundNet"}
        end
    end)

    after_each(function()
        package.loaded["ui/network/manager"] = nil
    end)

    it("skips background-association wait when no saved network is in scan results", function()
        -- Scan sees unknown APs; none match any saved network (no .password tag)
        function NetworkMgr:getNetworkList()
            return {
                {ssid = "Starbucks",     signal_quality = 80},
                {ssid = "McDonalds_WiFi", signal_quality = 60},
            }, nil
        end
        -- User has saved networks, but they are out of range
        -- (the old code keyed on this and wrongly entered a 15s blocking wait)
        function NetworkMgr:getConfiguredNetworks()
            return {{ssid = "HomeNet"}, {ssid = "OfficeNet"}}
        end

        local success = NetworkMgr:reconnectOrShowNetworkMenu(nil, false)

        assert.is_false(success)
        -- The background-association wait must have been skipped entirely:
        -- getCurrentNetwork should never be called when no known AP is in range.
        assert.is_same(0, get_current_network_calls)
    end)

    it("enters background-association wait when a saved AP is visible in scan results", function()
        -- Scan sees one AP that the user has saved (.password tag present)
        function NetworkMgr:getNetworkList()
            return {
                {ssid = "HomeNet", signal_quality = 70, password = "secret"},
            }, nil
        end
        -- authenticateNetwork fails; wpa_supplicant handles it in background
        function NetworkMgr:getConfiguredNetworks()
            return {{ssid = "HomeNet"}}
        end

        -- getCurrentNetwork immediately reports a connection on first poll
        local success = NetworkMgr:reconnectOrShowNetworkMenu(nil, false)

        assert.is_true(success)
        -- The wait loop must have run and polled getCurrentNetwork at least once
        assert.is_truthy(get_current_network_calls >= 1)
    end)

    teardown(function()
        Device = require("device")
        function Device:initNetworkManager() end
        function Device:hasWifiRestore() return false end
        function Device:hasWifiManager() return false end
        package.loaded["ui/network/manager"] = nil
    end)
end)
