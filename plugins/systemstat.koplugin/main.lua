
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local SystemStat = {
    start_sec = os.time(),
    wakeup_count = 0,
    sleep_count = 0,
    charge_count = 0,
    discharge_count = 0,
}

function SystemStat:onSuspend()
    self.sleep_count = self.sleep_count + 1
end

function SystemStat:onResume()
    self.wakeup_count = self.wakeup_count + 1
end

function SystemStat:onCharging()
    self.charge_count = self.charge_count + 1
end

function SystemStat:onNotCharging()
    self.discharge_count = self.discharge_count + 1
end

function SystemStat:showStatistics()
    local kv_pairs = {
        {_("KOReader Started at"), os.date("%c", self.start_sec)},
        {_("Up hours"), string.format("%.2f", os.difftime(os.time(), self.start_sec) / 60 / 60)},
        {_("Number of wake-ups"), self.wakeup_count},
        {_("Number of sleeps"), self.sleep_count},
        {_("Number of charge cycles"), self.charge_count},
        {_("Number of discharge cycles"), self.discharge_count},
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
            SystemStat:showStatistics()
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
