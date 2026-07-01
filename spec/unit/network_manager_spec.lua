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

describe("NetworkMgr:hasLeaseForCurrentNetwork", function()
    local NetworkMgr

    setup(function()
        require("commonrequire")
        local Device = require("device")
        function Device:initNetworkManager(mgr)
            -- Minimal stubs so manager.lua initialises without errors.
            function mgr:turnOnWifi() end
            function mgr:turnOffWifi() end
            function mgr:obtainIP() end
            function mgr:releaseIP() end
            function mgr:restoreWifiAsync() end
        end
        function Device:hasWifiRestore() return false end
    end)

    before_each(function()
        package.loaded["ui/network/manager"] = nil
        G_reader_settings:saveSetting("wifi_was_on", false)
        NetworkMgr = require("ui/network/manager")
    end)

    after_each(function()
        package.loaded["ui/network/manager"] = nil
    end)

    it("returns false when not connected", function()
        -- Override isConnected so we don't need a real interface.
        function NetworkMgr:isConnected() return false end
        assert.is_false(NetworkMgr:hasLeaseForCurrentNetwork())
    end)

    it("returns true when backend cannot report an SSID (non-wpa_supplicant platforms)", function()
        function NetworkMgr:isConnected() return true end
        -- getCurrentNetwork() is a no-op stub that returns nil on non-Kobo builds.
        function NetworkMgr:getCurrentNetwork() return nil end
        assert.is_true(NetworkMgr:hasLeaseForCurrentNetwork())
    end)

    it("returns true when connected and lease matches the current SSID (no churn)", function()
        function NetworkMgr:isConnected() return true end
        function NetworkMgr:getCurrentNetwork() return {ssid = "HomeNet"} end
        NetworkMgr.lease_ssid = "HomeNet"
        assert.is_true(NetworkMgr:hasLeaseForCurrentNetwork())
    end)

    it("returns false when lease_ssid differs from current SSID (stale lease)", function()
        function NetworkMgr:isConnected() return true end
        function NetworkMgr:getCurrentNetwork() return {ssid = "OfficeNet"} end
        NetworkMgr.lease_ssid = "HomeNet"   -- still holds the lease from the old network
        assert.is_false(NetworkMgr:hasLeaseForCurrentNetwork())
    end)

    it("returns false when lease_ssid is nil even though a SSID is reported", function()
        function NetworkMgr:isConnected() return true end
        function NetworkMgr:getCurrentNetwork() return {ssid = "SomeNet"} end
        NetworkMgr.lease_ssid = nil
        assert.is_false(NetworkMgr:hasLeaseForCurrentNetwork())
    end)

    teardown(function()
        local Device = require("device")
        function Device:initNetworkManager() end
        function Device:hasWifiRestore() return false end
        package.loaded["ui/network/manager"] = nil
    end)
end)
