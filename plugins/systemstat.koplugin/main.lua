local Device = require("device")
local Dispatcher = require("dispatcher")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local SEP = " · "

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
    elseif Device:isAndroid() then
        self.storage_filter = "sdcard"
    end
end

function SystemStat:put(p)
    -- compact spaces before a unit or %-symbols
    if p[2] and type(p[2]) == "string" then
        p[2] = p[2]:gsub(" GB", "\u{200a}GB")
        p[2] = p[2]:gsub(" MB", "\u{200a}MB")
        p[2] = p[2]:gsub(" kB", "\u{200a}kB")
        p[2] = p[2]:gsub(" %%", "\u{200a}%%")
    end
    table.insert(self.kv_pairs, p)
end

function SystemStat:putSeparator()
    self.kv_pairs[#self.kv_pairs].separator = true
end

function SystemStat:appendCounters()
    self:put({_("KOReader started at"), os.date("%c", self.start_sec)})
    if self.suspend_sec then
       self:put({_("  Last suspend time"), os.date("%c", self.suspend_sec)})
    end
    if self.resume_sec then
        self:put({_("  Last resume time"), os.date("%c", self.resume_sec)})
    end
    local duration_fmt = G_reader_settings:readSetting("duration_format", "classic")
    self:put({_("  Up time"),
        util.secondsToClockDuration(duration_fmt, os.difftime(os.time(), self.start_sec), true, true, true)})
    self:put({_("Counters"), ""})
    self:put({_("  wake-ups"), self.wakeup_count})
    -- @translators The number of "sleeps", that is the number of times the device has entered standby. This could also be translated as a rendition of a phrase like "entered sleep".
    self:put({_("  sleeps"), self.sleep_count})
    self:put({_("  charge cycles"), self.charge_count})
    self:put({_("  discharge cycles"), self.discharge_count})
end

local function systemInfo()
    local result = {}

    local stat = io.open("/proc/stat", "r")
    if stat ~= nil then
        for line in stat:lines() do
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

    local meminfo = io.open("/proc/meminfo", "r")
    if meminfo ~= nil then
        result.memory = {}
        for line in meminfo:lines() do
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
        self:put({_("  Processor usage"),
            string.format("%.2f %%", (1 - stat.cpu.idle / stat.cpu.total) * 100)})
    end
    if stat.memory ~= nil then
        self:put({_("  Total") .. SEP .. _("free") .. SEP .. _("available"),
            (stat.memory.total and
                (util.getFriendlySize(stat.memory.total * 1024, false) .. SEP) or "N/A") ..
            (stat.memory.free and
                (util.getFriendlySize(stat.memory.free * 1024, false) .. SEP) or "N/A") ..
            (stat.memory.available and
                util.getFriendlySize(stat.memory.available * 1024, false) or "N/A")})
    end
end

function SystemStat:appendProcessInfo()
    local stat = io.open("/proc/self/stat", "r")
    if stat == nil then return end

    local t = util.splitToArray(stat:read("*line"), " ")
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
            self:put({_("  Processor usage"),
                string.format("%.2f %%", n1 / sys_stat.cpu.total * 100)})
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
    local virtual_mem = tonumber(t[23])
    local ram_usage = tonumber(t[24]) -- will give nil if not avail

    if virtual_mem ~= nil then
        local key = _("  Virtual memory") .. (ram_usage and SEP .._("RAM usage") or "")
        local value = util.getFriendlySize(virtual_mem, false) ..
            (ram_usage and (SEP .. util.getFriendlySize(ram_usage * 4 * 1024, false)) or "")
        self:put({key, value})
    end
end

function SystemStat:appendStorageInfo()
    if self.storage_filter == nil then return end

    local df_commands = {
        -- first choice: SI-prefixes
        "df -H",
        -- second choice: binary-prefixes
        "df -h",
        -- use busybox if available (on some Android devices)
        "busybox df -h",
        -- as a last resort try df
        "df",
    }

    self:put({_("Storage information"), ""})

    local std_out
    local is_entry_available
    local command_index = 1
    while not is_entry_available and command_index <= #df_commands do
        std_out = io.popen( df_commands[command_index] )
        command_index = command_index + 1

        for line in std_out:lines() do
            if line:find("^   ") then -- can happen with busybox on long device node paths
                line = "dummy" .. line
            end
            line = line:gsub(" +", "\t")
            local t = util.splitToArray(line, "\t")
            if line:find(self.storage_filter) then
                local total_mem = t[2]:sub(1, #t[2] - 1) .. " " .. t[2]:sub(#t[2]) .. "B"
                local avail_mem = t[4]:sub(1, #t[4] - 1) .. " " .. t[4]:sub(#t[4]) .. "B"
                local percentage_used
                if #t >= 6 then
                    percentage_used = t[5]:sub(1, #t[5] - 1) .. " " .. t[5]:sub(#t[5])
                    self:put({_("  Mount point"), t[6]})
                    is_entry_available = true
                end
                if #t == 5 then -- a pure df on Android/Tolino
                    self:put({_("  Mount point"), t[1]})
                    is_entry_available = true
                end
                self:put({_("    Total" .. SEP .. _("available") .. SEP .. _("used")), total_mem .. SEP ..
                    avail_mem .. SEP .. (percentage_used or "N/A")})
            end
        end
        std_out:close()
    end
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
    self:putSeparator()
    self:appendProcessInfo()
    self:putSeparator()
    self:appendStorageInfo()
    self:putSeparator()
    self:appendSystemInfo()
    UIManager:show(KeyValuePage:new{
        title = _("System statistics"),
        kv_pairs = self.kv_pairs,
        single_page = true,
    })
end

SystemStat:init()

local SystemStatWidget = WidgetContainer:new{
    name = "systemstat",
}

function SystemStatWidget:onDispatcherRegisterActions()
    Dispatcher:registerAction("system_statistics", {category="none", event="ShowSysStatistics", title=_("System statistics"), device=true, separator=true})
end

function SystemStatWidget:init()
    self:onDispatcherRegisterActions()
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

function SystemStatWidget:onShowSysStatistics()
    SystemStat:showStatistics()
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
