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
    if Device:isCervantes() or Device:isPocketBook() then
        self.storage_filter = "mmcblk"
    elseif Device:isKobo() then
        self.storage_filter = " /mnt/"
    elseif Device:isKindle() then
        self.storage_filter = "' /mnt/us$'"
    elseif Device:isSDL() then
        self.storage_filter = "/dev/sd"
    end
end

function SystemStat:put(p)
    table.insert(self.kv_pairs, p)
end

function SystemStat:appendCounters()
    self:put({_("KOReader started at"), os.date("%c", self.start_sec)})
    if self.suspend_sec then
       self:put({_("  Last suspend time"), os.date("%c", self.suspend_sec)})
    end
    if self.resume_sec then
        self:put({_("  Last resume time"), os.date("%c", self.resume_sec)})
    end
    self:put({_("  Up hours"),
             string.format("%.2f", os.difftime(os.time(), self.start_sec) / 60 / 60)})
    self:put({_("Counters"), ""})
    self:put({_("  wake-ups"), self.wakeup_count})
    -- @translators The number of "sleeps", that is the number of times the device has entered standby. This could also be translated as a rendition of a phrase like "entered sleep".
    self:put({_("  sleeps"), self.sleep_count})
    self:put({_("  charge cycles"), self.charge_count})
    self:put({_("  discharge cycles"), self.discharge_count})
end

local function systemInfo()
    local result = {}
    do
        local stat = io.open("/proc/stat", "r")
        if stat ~= nil then
            for line in util.gsplit(stat:read("*all"), "\n", false) do
                local t = util.splitToArray(line, " ")
                if #t >= 5 and string.lower(t[1]) == "cpu" then
                    local n1, n2, n3, n4
                    n1 = tonumber(t[2])
                    n2 = tonumber(t[3])
                    n3 = tonumber(t[4])
                    n4 = tonumber(t[5])
                    if n1 ~= nil and n2 ~= nil and n3 ~= nil and n4 ~= nil then
                      result.cpu = {
                        user = n1,
                        nice = n2,
                        system = n3,
                        idle = n4,
                        total = n1 + n2 + n3 + n4
                      }
                      break
                    end
                end
            end
            stat:close()
        end
    end

    do
        local meminfo = io.open("/proc/meminfo", "r")
        if meminfo ~= nil then
            result.memory = {}
            for line in util.gsplit(meminfo:read("*all"), "\n", false) do
                local t = util.splitToArray(line, " ")
                if #t >= 2 then
                    if string.lower(t[1]) == "memtotal:" then
                        local n = tonumber(t[2])
                        if n ~= nil then
                            result.memory.total = n
                        end
                    elseif string.lower(t[1]) == "memfree:" then
                        local n = tonumber(t[2])
                        if n ~= nil then
                            result.memory.free = n
                        end
                    elseif string.lower(t[1]) == "memavailable:" then
                        local n = tonumber(t[2])
                        if n ~= nil then
                            result.memory.available = n
                        end
                    end
                end
            end
            meminfo:close()
        end
    end
    return result
end

function SystemStat:appendSystemInfo()
    local stat = systemInfo()
    if stat.cpu ~= nil then
        self:put({_("System information"), ""})
        -- @translators Ticks is a highly technical term. See https://superuser.com/a/101202 The correct translation is likely to simply be "ticks".
        self:put({_("  Total ticks (million)"),
                 string.format("%.2f", stat.cpu.total / 1000000)})
        -- @translators Ticks is a highly technical term. See https://superuser.com/a/101202 The correct translation is likely to simply be "ticks".
        self:put({_("  Idle ticks (million)"),
                 string.format("%.2f", stat.cpu.idle / 1000000)})
        self:put({_("  Processor usage %"),
                 string.format("%.2f", (1 - stat.cpu.idle / stat.cpu.total) * 100)})
    end
    if stat.memory ~= nil then
        if stat.memory.total ~= nil then
            self:put({_("  Total memory (MB)"),
                     string.format("%.2f", stat.memory.total / 1024)})
        end
        if stat.memory.free ~= nil then
            self:put({_("  Free memory (MB)"),
                     string.format("%.2f", stat.memory.free / 1024)})
        end
        if stat.memory.available ~= nil then
            self:put({_("  Available memory (MB)"),
                     string.format("%.2f", stat.memory.available / 1024)})
        end
    end
end

function SystemStat:appendProcessInfo()
    local stat = io.open("/proc/self/stat", "r")
    if stat == nil then return end

    local t = util.splitToArray(stat:read("*all"), " ")
    stat:close()

    local n1, n2

    if #t == 0 then return end
    self:put({_("Process"), ""})

    self:put({_("  ID"), t[1]})

    if #t < 14 then return end
    n1 = tonumber(t[14])
    n2 = tonumber(t[15])
    if n1 ~= nil then
        if n2 ~= nil then
            n1 = n1 + n2
        end
        local sys_stat = systemInfo()
        if sys_stat.cpu ~= nil and sys_stat.cpu.total ~= nil then
            self:put({_("  Processor usage %"),
                     string.format("%.2f", n1 / sys_stat.cpu.total * 100)})
        else
            self:put({_("  Processor usage ticks (million)"), n1 / 1000000})
        end
    end

    if #t < 20 then return end
    n1 = tonumber(t[20])
    if n1 ~= nil then
        self:put({_("  Threads"), tostring(n1)})
    end

    if #t < 23 then return end
    n1 = tonumber(t[23])
    if n1 ~= nil then
        self:put({_("  Virtual memory (MB)"), string.format("%.2f", n1 / 1024 / 1024)})
    end

    if #t < 24 then return end
    n1 = tonumber(t[24])
    if n1 ~= nil then
        self:put({_("  RAM usage (MB)"), string.format("%.2f", n1 / 256)})
    end
end

function SystemStat:appendStorageInfo()
    if self.storage_filter == nil then return end

    local std_out = io.popen(
        "df -h | sed -r 's/ +/ /g' | grep " .. self.storage_filter ..
        " | sed 's/ /\\t/g' | cut -f 2,4,5,6"
    )
    if not std_out then return end

    self:put({_("Storage information"), ""})
    for line in util.gsplit(std_out:read("*all"), "\n", false) do
        local t = util.splitToArray(line, "\t")
        if #t ~= 4 then
            self:put({_("  Unexpected"), line})
        else
            self:put({_("  Mount point"), t[4]})
            self:put({_("    Available"), t[2]})
            self:put({_("    Total"), t[1]})
            self:put({_("    Used percentage"), t[3]})
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
        keep_menu_open = true,
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
