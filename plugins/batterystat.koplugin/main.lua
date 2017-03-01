
local WidgetContainer = require("ui/widget/container/widgetcontainer")

function State:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:validate()
    return o
end

function State:validate()
    if self.percentage == nil or self.timestamp == nil then
        self.percentage = 0
        self.timestamp = os.time()
    end
end

function Usage:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:validate()
    return o
end

function Usage:validate()
    if self.percentage == nil or self.time == nil then
        self.percentage = 0
        self.time = 0
    end
end

function Usage:append(state1, state2)
    self.percentage = self.percentage + (state2.percentage - state1.percentage)
    self.time = self.time + (state2.timestamp - state1.timestamp)
end

local BatteryStat = WidgetContainer:new{
    name = "batterstat",
    last_charging = Usage:new(),
    last_decharging = Usage:new(),
    last_charging_start = State:new(),
    last_charging_end = State:new(),
    last_resume_start = State:new(),
    last_sleep_start = State:new(),
}

function BatteryState:init()
    local records = G_reader_settings:readSetting("batterystat") or {}
    self.last_charging = records.last_charging
    self.last_decharing = records.last_decharging
    self.last_charging_start = records.last_charging_start
    self.last_charging_end = records.last_charging_end
    self.last_resume_start = records.last_resume_start
    self.last_sleep_start = records.last_sleep_start
end

return BatteryStat
