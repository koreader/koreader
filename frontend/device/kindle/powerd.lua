local BasePowerD = require("device/generic/powerd")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,

    lipc_handle = nil,
}

function KindlePowerD:init()
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end

    -- On devices where lipc step 0 is *not* off, we add a synthetic fl level where 0 *is* off,
    -- which allows us to keep being able to use said step 0 as the first "on" step.
    if not self.device:canTurnFrontlightOff() then
        self.fl_max = self.fl_max + 1
    end
end

-- If we start with the light off (fl_intensity is fl_min), ensure a toggle will set it to the lowest "on" step,
-- and that we update fl_intensity (by using setIntensity and not setIntensityHW).
function KindlePowerD:turnOnFrontlightHW()
    self:setIntensity(self.fl_intensity == self.fl_min and self.fl_min + 1 or self.fl_intensity)
end
-- Which means we need to get rid of the insane fl_intensity == fl_min shortcut in turnOnFrontlight, too...
-- That dates back to #2941, and I have no idea what it's supposed to help with.
function BasePowerD:turnOnFrontlight()
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOn() then return false end
    self:turnOnFrontlightHW()
    self.is_fl_on = true
    self:stateChanged()
    return true
end

function KindlePowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    -- Kindle stock software does not use intensity file directly, so go through lipc to keep us in sync.
    if self.lipc_handle ~= nil then
        -- Handle the step 0 switcheroo on ! canTurnFrontlightOff devices...
        if self.device:canTurnFrontlightOff() then
            return self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
        else
            local lipc_fl_intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
            -- NOTE: If lipc returns 0, compare against what the kernel says,
            --       to avoid breaking on/off detection on devices where lipc 0 doesn't actually turn it off (<= PW3),
            --       c.f., #5986
            if lipc_fl_intensity == self.fl_min then
                local sysfs_fl_intensity = self:_readFLIntensity()
                if sysfs_fl_intensity ~= self.fl_min then
                    -- Return something potentially slightly off (as we can't be sure of the sysfs -> lipc mapping),
                    -- but, more importantly, something that's not fl_min (0), so we properly detect the light as on,
                    -- and update fl_intensity accordingly.
                    -- That's only tripped if it was set to fl_min from the stock UI,
                    -- as we ourselves *do* really turn it off when we do that.
                    return self.fl_min + 1
                else
                    return self.fl_min
                end
            else
                -- We've added a synthetic step...
                return lipc_fl_intensity + 1
            end
        end
    else
        -- NOTE: This fallback is of dubious use, as it will NOT match our expected [fl_min..fl_max] range,
        --       each model has a specific curve.
        return self:_readFLIntensity()
    end
end

function KindlePowerD:setIntensityHW(intensity)
    -- Handle the synthetic step switcheroo on ! canTurnFrontlightOff devices...
    local turn_it_off = false
    if not self.device:canTurnFrontlightOff() then
        if intensity > 0 then
            intensity = intensity - 1
        else
            -- And if we *really* requested 0, turn it off manually.
            turn_it_off = true
        end
    end
    -- NOTE: This means we *require* a working lipc handle to set the FL:
    --       it knows what the UI values should map to for the specific hardware much better than us.
    if self.lipc_handle ~= nil then
        -- NOTE: We want to bypass setIntensity's shenanigans and simply restore the light as-is
        self.lipc_handle:set_int_property(
            "com.lab126.powerd", "flIntensity", intensity)
    end
    if turn_it_off then
        -- NOTE: when intensity is 0, we want to *really* kill the light, so do it manually
        -- (asking lipc to set it to 0 would in fact set it to > 0 on ! canTurnFrontlightOff Kindles).
        -- We do *both* to make the fl restore on resume less jarring on devices where lipc 0 != off.
        os.execute("printf '%s' ".. intensity .." > " .. self.fl_intensity_file)
    end
end

function KindlePowerD:getCapacityHW()
    if self.lipc_handle ~= nil then
        return self.lipc_handle:get_int_property("com.lab126.powerd", "battLevel")
    elseif self.batt_capacity_file then
        return self:read_int_file(self.batt_capacity_file)
    else
        local std_out = io.popen("gasgauge-info -c 2>/dev/null", "r")
        if std_out then
            local result = std_out:read("*number")
            std_out:close()
            return result or 0
        else
            return 0
        end
    end
end

function KindlePowerD:isChargingHW()
    local is_charging
    if self.lipc_handle ~= nil then
        is_charging = self.lipc_handle:get_int_property("com.lab126.powerd", "isCharging")
    else
        is_charging = self:read_int_file(self.is_charging_file)
    end
    return is_charging == 1
end

function KindlePowerD:_readFLIntensity()
    return self:read_int_file(self.fl_intensity_file)
end

function KindlePowerD:afterResume()
    if not self.device:hasFrontlight() then
        return
    end
    local UIManager = require("ui/uimanager")
    if self:isFrontlightOn() then
        -- The Kindle framework should turn the front light back on automatically.
        -- The following statement ensures consistency of intensity, but should basically always be redundant,
        -- since we set intensity via lipc and not sysfs ;).
        -- NOTE: This is race-y, and we want to *lose* the race, hence the use of the scheduler (c.f., #4392)
        UIManager:tickAfterNext(function() self:turnOnFrontlightHW() end)
    else
        -- But in the off case, we *do* use sysfs, so this one actually matters.
        UIManager:tickAfterNext(function() self:turnOffFrontlightHW() end)
    end
end

function KindlePowerD:toggleSuspend()
    if self.lipc_handle then
        self.lipc_handle:set_int_property("com.lab126.powerd", "powerButton", 1)
    else
        os.execute("powerd_test -p")
    end
end

--- @fixme: This won't ever fire, as KindlePowerD is already a metatable on a plain table.
function KindlePowerD:__gc()
    if self.lipc_handle then
        self.lipc_handle:close()
        self.lipc_handle = nil
    end
end

return KindlePowerD
