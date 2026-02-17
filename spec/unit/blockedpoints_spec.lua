local commonrequire = require("commonrequire")
local BlockedPointsInjector = commonrequire.preload("ui/blockedpoints")
local JSON = require("json") -- Assuming JSON module is available

describe("BlockedPoints module", function()
    local BlockedPoints
    local mock_settings

    before_each(function()
        -- Mock G_reader_settings
        mock_settings = {}
        _G.G_reader_settings = {
            readSetting = function(self, key)
                return mock_settings[key]
            end,
            saveSetting = function(self, key, value)
                mock_settings[key] = value
            end,
            isTrue = function() return false end -- Default for any other checks
        }
        -- Each test should get a fresh instance of BlockedPoints
        -- to ensure loadBlockedPoints is called with the current mock_settings.
        BlockedPoints = BlockedPointsInjector({})
    end)

    after_each(function()
        _G.G_reader_settings = nil -- Clean up global mock
        mock_settings = nil
        BlockedPoints = nil
    end)

    it("should add a point and check if it's blocked", function()
        BlockedPoints:addBlockedPoint(100, 200)
        assert.is_true(BlockedPoints:isBlocked(100, 200))
        assert.is_false(BlockedPoints:isBlocked(10, 20))

        BlockedPoints:addBlockedPoint(10, 20)
        assert.is_true(BlockedPoints:isBlocked(10, 20))
    end)

    it("should not add duplicate points", function()
        BlockedPoints:addBlockedPoint(50, 50)
        BlockedPoints:addBlockedPoint(50, 50) -- Add again
        assert.is_true(BlockedPoints:isBlocked(50, 50))
        -- Check internal table size if possible, or remove and check it's gone
        BlockedPoints:removeBlockedPoint(50,50)
        assert.is_false(BlockedPoints:isBlocked(50,50))
        -- Try to remove again, should not error
        BlockedPoints:removeBlockedPoint(50,50)
    end)

    it("should remove a blocked point", function()
        BlockedPoints:addBlockedPoint(300, 400)
        assert.is_true(BlockedPoints:isBlocked(300, 400))
        BlockedPoints:removeBlockedPoint(300, 400)
        assert.is_false(BlockedPoints:isBlocked(300, 400))
    end)

    it("should persist points (save and load)", function()
        BlockedPoints:addBlockedPoint(10, 20)
        BlockedPoints:addBlockedPoint(30, 40)
        -- Save is called by addBlockedPoint, but we can call it explicitly if we want to be sure
        -- BlockedPoints:saveBlockedPoints() -- This is already done by addBlockedPoint

        -- Simulate fresh load by creating a new instance that will call loadBlockedPoints
        local NewBlockedPoints = BlockedPointsInjector({})
        assert.is_true(NewBlockedPoints:isBlocked(10, 20))
        assert.is_true(NewBlockedPoints:isBlocked(30, 40))
        assert.is_false(NewBlockedPoints:isBlocked(50, 60))
    end)

    describe("edge cases", function()
        it("isBlocked should handle non-numeric input gracefully", function()
            assert.is_false(BlockedPoints:isBlocked("abc", 10))
            assert.is_false(BlockedPoints:isBlocked(10, "def"))
            assert.is_false(BlockedPoints:isBlocked(nil, 10))
            assert.is_false(BlockedPoints:isBlocked(10, nil))
            assert.is_false(BlockedPoints:isBlocked({}, {}))
        end)

        it("addBlockedPoint should handle non-numeric input gracefully", function()
            BlockedPoints:addBlockedPoint("abc", 10)
            BlockedPoints:addBlockedPoint(10, "def")
            BlockedPoints:addBlockedPoint(nil, 10)
            BlockedPoints:addBlockedPoint(10, nil)
            BlockedPoints:addBlockedPoint({}, {})
            -- No easy way to check internal state without exposing it,
            -- but we can check that valid points are not affected and no error occurs.
            BlockedPoints:addBlockedPoint(1,1)
            assert.is_true(BlockedPoints:isBlocked(1,1))
            -- And that no malformed data was saved that would break loading
            local NewBlockedPoints = BlockedPointsInjector({})
            assert.is_true(NewBlockedPoints:isBlocked(1,1))
        end)

        it("removeBlockedPoint for a non-existent point should not error", function()
            assert.does_not_error(function()
                BlockedPoints:removeBlockedPoint(999, 999)
            end)
        end)

        it("should load with empty settings", function()
            mock_settings["blocked_points_list"] = nil
            local NewBlockedPoints = BlockedPointsInjector({})
            NewBlockedPoints:addBlockedPoint(1,2) -- should work
            assert.is_true(NewBlockedPoints:isBlocked(1,2))
        end)

        it("should load with empty JSON array", function()
            mock_settings["blocked_points_list"] = "[]"
            local NewBlockedPoints = BlockedPointsInjector({})
            NewBlockedPoints:addBlockedPoint(1,2) -- should work
            assert.is_true(NewBlockedPoints:isBlocked(1,2))
             assert.is_false(NewBlockedPoints:isBlocked(10,20)) -- point from other test
        end)

        it("should load with malformed JSON in settings", function()
            mock_settings["blocked_points_list"] = "{not_json"
            local NewBlockedPoints = BlockedPointsInjector({})
            NewBlockedPoints:addBlockedPoint(1,2) -- should work
            assert.is_true(NewBlockedPoints:isBlocked(1,2))
        end)

        it("should load with non-array JSON in settings (e.g. a JSON object/number)", function()
            mock_settings["blocked_points_list"] = "{\"foo\":\"bar\"}"
            local NewBlockedPoints = BlockedPointsInjector({})
            NewBlockedPoints:addBlockedPoint(1,2) -- should work
            assert.is_true(NewBlockedPoints:isBlocked(1,2))

            mock_settings["blocked_points_list"] = "123"
            local AnotherBP = BlockedPointsInjector({})
            AnotherBP:addBlockedPoint(3,4)
            assert.is_true(AnotherBP:isBlocked(3,4))
        end)

        it("should handle G_reader_settings not being available", function()
            _G.G_reader_settings = nil
            -- Need to re-require/re-inject to pick up nil G_reader_settings at module scope
            local NoSettingsBlockedPointsModule = commonrequire.preload("ui/blockedpoints")
            local NoSettingsBP = NoSettingsBlockedPointsModule({})

            assert.does_not_error(function() NoSettingsBP:loadBlockedPoints() end)
            assert.does_not_error(function() NoSettingsBP:saveBlockedPoints() end)
            assert.does_not_error(function() NoSettingsBP:addBlockedPoint(1,1) end)
            assert.is_false(NoSettingsBP:isBlocked(1,1)) -- Should not save/load, so not blocked

            -- Restore for other tests
            _G.G_reader_settings = {
                readSetting = function(self, key) return mock_settings[key] end,
                saveSetting = function(self, key, value) mock_settings[key] = value end,
                isTrue = function() return false end
            }
        end)
    end)
end)
