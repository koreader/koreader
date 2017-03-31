
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local SystemStat = {
    start_sec = os.time(),
    wakeup_count = 0,
    sleep_count = 0,
    charging_count = 0,
    decharging_count = 0,
}

function SystemStat:onSuspend()
    self.sleep_count = self.sleep_count + 1
end

function SystemStat:onResume()
    self.wakeup_count = self.wakeup_count + 1
end

function SystemStat:onCharging()
    self.charging_count = self.charging_count + 1
end

function SystemStat:onNotCharging()
    self.decharging_count = self.decharging_count + 1
end

function SystemStat:onCallback()
    local kv_pairs = {
        {_("Startup at"), os.date("%c", self.start_sec)},
        {_("Running hours"),
         string.format("%.2f", os.difftime(os.time(), self.start_sec) / 60 / 60)},
        {_("Wakeup times"), self.wakeup_count},
        {_("Sleep times"), self.sleep_count},
        {_("Charging times"), self.charging_count},
        {_("Decharging times"), self.decharging_count},
    }
    UIManager:show(KeyValuePage:new{
        title = _("System statistics"),
        kv_pairs = kv_pairs,
    })
end

local SystemStatWidget = WidgetContainer:new{
    name = "systemstat",
}

function SystemStatWidget:init()
    self.ui.menu:registerToMainMenu(self)
end

function SystemStatWidget:addToMainMenu(menu_items)
    menu_items.system_statistics = {
        text = _("System statistics"),
        callback = function()
            SystemStat:onCallback()
        end,
    }
end

function SystemStatWidget:onSuspend()
    SystemStat:onSuspend()
end

function SystemStatWidget:onResume()
    SystemStat:onResume()
end

function SystemStatWidget:onCharging()
    SystemStat:onCharging()
end

function SystemStatWidget:onNotCharging()
    SystemStat:onNotCharging()
end

return SystemStatWidget
