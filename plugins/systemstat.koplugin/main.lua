
local Device = require("device")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local SystemStat = {
    start_sec = os.time(),
    suspend_sec = nil,
    resume_sec = nil,
    wakeup_count = 0,
    sleep_count = 0,
    charge_count = 0,
    discharge_count = 0,
}

function SystemStat:init()
    if Device:isKobo() or Device:isPocketBook() then
        self.storage_filter = "mmcblk"
    elseif Device:isKindle() then
        self.storage_filter = "' /mnt/us$'"
    elseif Device:isSDL() then
        self.storage_filter = "/dev/sd"
    end
end

function SystemStat:appendCounters()
    table.insert(self.kv_pairs, {_("KOReader Started at"), os.date("%c", self.start_sec)})
    if self.suspend_sec then
       table.insert(self.kv_pairs, {_("  Last suspend time"), os.date("%c", self.suspend_sec)})
    end
    if self.resume_sec then
        table.insert(self.kv_pairs, {_("  Last resume time"), os.date("%c", self.resume_sec)})
    end
    table.insert(self.kv_pairs, {_("  Up hours"), string.format("%.2f", os.difftime(os.time(), self.start_sec) / 60 / 60)})
    table.insert(self.kv_pairs, {_("Counters"), ""})
    table.insert(self.kv_pairs, {_("  wake-ups"), self.wakeup_count})
    table.insert(self.kv_pairs, {_("  sleeps"), self.sleep_count})
    table.insert(self.kv_pairs, {_("  charge cycles"), self.charge_count})
    table.insert(self.kv_pairs, {_("  discharge cycles"), self.discharge_count})
end

local function systemInfo()
    local stat = io.open("/proc/stat", "r")
    if stat == nil then return {} end
    for line in util.gsplit(stat:read("*all"), "\n", false) do
        local t = util.splitToArray(line, " ")
        if #t >= 5 and string.lower(t[1]) == "cpu" then
            local result = {}
            local n1, n2, n3, n4
            n1 = tonumber(t[2])
            n2 = tonumber(t[3])
            n3 = tonumber(t[4])
            n4 = tonumber(t[5])
            if n1 ~= nil and n2 ~= nil and n3 ~= nil and n4 ~= nil then
              result.user = n1
              result.nice = n2
              result.system = n3
              result.idle = n4
              result.total = n1 + n2 + n3 + n4
              return result
            end
        end
    end
    return {}
end

function SystemStat:appendSystemInfo()
    local stat = systemInfo()
    if next(stat) == nil then return end
    table.insert(self.kv_pairs, {_("System information"), ""})
    table.insert(self.kv_pairs, {_("  Total ticks (million)"), string.format("%.2f", stat.total / 1000000)})
    table.insert(self.kv_pairs, {_("  Idle ticks (million)"), string.format("%.2f", stat.idle / 1000000)})
    table.insert(self.kv_pairs, {_("  Processor usage %"), string.format("%.2f", (1 - stat.idle / stat.total) * 100)})
end

function SystemStat:appendProcessInfo()
    local stat = io.open("/proc/self/stat", "r")
    if stat == nil then return end

    local t = util.splitToArray(stat:read("*all"), " ")
    stat:close()

    local n1, n2

    if #t == 0 then return end
    table.insert(self.kv_pairs, {_("Process"), ""})

    table.insert(self.kv_pairs, {_("  ID"), t[1]})

    if #t < 14 then return end
    n1 = tonumber(t[14])
    n2 = tonumber(t[15])
    if n1 ~= nil then
        if n2 ~= nil then
            n1 = n1 + n2
        end
        local stat = systemInfo()
        if stat.total ~= nil then
            table.insert(self.kv_pairs, {_("  Processor usage %"), string.format("%.2f", n1 / stat.total * 100)})
        end
    end

    if #t < 20 then return end
    n1 = tonumber(t[20])
    if n1 ~= nil then
        table.insert(self.kv_pairs, {_("  Threads"), tostring(n1)})
    end

    if #t < 23 then return end
    n1 = tonumber(t[23])
    if n1 ~= nil then
        table.insert(self.kv_pairs, {_("  Virtual memory (MB)"), string.format("%.2f", n1 / 1024 / 1024)})
    end

    if #t < 24 then return end
    n1 = tonumber(t[24])
    if n1 ~= nil then
        table.insert(self.kv_pairs, {_("  RAM usage (MB)"), string.format("%.2f", n1 / 256)})
    end
end

function SystemStat:appendStorageInfo()
    if self.storage_filter == nil then return end

    table.insert(self.kv_pairs, {_("Storage information"), ""})
    local std_out = io.popen(
        "df -h | sed -r 's/ +/ /g' | grep " .. self.storage_filter ..
        " | sed 's/ /\\t/g' | cut -f 2,4,5,6"
    )
    if not std_out then
        table.insert(self.kv_pairs, {_("  Failed"), _("Nothing retrieved")})
        return
    end

    for line in util.gsplit(std_out:read("*all"), "\n", false) do
        local t = util.splitToArray(line, "\t")
        if #t ~= 4 then
            table.insert(self.kv_pairs, {_("  Unexpected"), line})
        else
            table.insert(self.kv_pairs, {_("  Mount point: ") .. t[4], ""})
            table.insert(self.kv_pairs, {_("    Available"), t[2]})
            table.insert(self.kv_pairs, {_("    Total"), t[1]})
            table.insert(self.kv_pairs, {_("    Used percentage"), t[3]})
        end
    end
    std_out:close()
end

function SystemStat:onSuspend()
    self.suspend_sec = os.time()
    self.sleep_count = self.sleep_count + 1
end

function SystemStat:onResume()
    self.resume_sec = os.time()
    self.wakeup_count = self.wakeup_count + 1
end

function SystemStat:onCharging()
    self.charge_count = self.charge_count + 1
end

function SystemStat:onNotCharging()
    self.discharge_count = self.discharge_count + 1
end

function SystemStat:showStatistics()
    self.kv_pairs = {}
    self:appendCounters()
    self:appendProcessInfo()
    self:appendStorageInfo()
    self:appendSystemInfo()
    UIManager:show(KeyValuePage:new{
        title = _("System statistics"),
        kv_pairs = self.kv_pairs,
    })
end

SystemStat:init()

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
