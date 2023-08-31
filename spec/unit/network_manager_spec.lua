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

    describe("decodeSSID()", function()
        local NetworkMgr = require("ui/network/manager")

        it("should correctly unescape emoji", function()
            assert.is_equal("📚", NetworkMgr.decodeSSID("\\xf0\\x9f\\x93\\x9a"))
        end)

        it("should correctly unescape multiple characters", function()
            assert.is_equal("神舟五号", NetworkMgr.decodeSSID("\\xe7\\xa5\\x9e\\xe8\\x88\\x9f\\xe4\\xba\\x94\\xe5\\x8f\\xb7"))
        end)

        it("should ignore escaped backslashes", function()
            assert.is_equal("\\x61", NetworkMgr.decodeSSID("\\\\x61"))
        end)

        it("should not remove encoded backslashes", function()
            assert.is_equal("\\\\", NetworkMgr.decodeSSID("\\x5c\\"))
        end)

        it("should deal with invalid UTF-8 (relatively) gracefully", function()
            assert.is_equal("��", NetworkMgr.decodeSSID("\\xe2\\x82"))
        end)
    end)

    teardown(function()
        function Device:initNetworkManager() end
        function Device:hasWifiRestore() return false end
        package.loaded["ui/network/manager"] = nil
    end)
end)
