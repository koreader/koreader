local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Version = require("version")
local _ = require("gettext")
local T = require("ffi/util").template

local common_info = {}

if Device:hasOTAUpdates() then
    local OTAManager = require("ui/otamanager")
    common_info.ota_update = OTAManager:getOTAMenuTable()
end
common_info.version = {
    text = T(_("Version: %1"), Version:getShortVersion()),
    keep_menu_open = true,
    callback = function()
        UIManager:show(InfoMessage:new{
            text = Version:getCurrentRevision(),
        })
    end
}
common_info.help = {
    text = _("Help"),
}
common_info.more_tools = {
    text = _("More tools"),
}

common_info.device = {
    text = _("Device"),
}
common_info.quickstart_guide = {
    text = _("Quickstart guide"),
    callback = function()
        local QuickStart = require("ui/quickstart")
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(QuickStart:getQuickStart())
    end
}
common_info.about = {
    text = _("About"),
    keep_menu_open = true,
    callback = function()
        UIManager:show(InfoMessage:new{
            text = T(_("KOReader %1\n\nA document viewer for E Ink devices.\n\nLicensed under Affero GPL v3. All dependencies are free software.\n\nhttp://koreader.rocks"), BD.ltr(Version:getCurrentRevision())),
            icon = "koreader",
        })
    end
}
common_info.report_bug = {
    text = _("Report a bug"),
    keep_menu_open = true,
    callback_func = function()
        local DataStorage = require("datastorage")
        local log_path = string.format("%s/%s", DataStorage:getDataDir(), "crash.log")
        local common_msg = T(_("Please report bugs to \nhttps://github.com/koreader/koreader/issues\n\nVersion:\n%1\n\nDetected device:\n%2"),
            Version:getCurrentRevision(), Device:info())
        local log_msg = T(_("Attach %1 to your bug report."), log_path)

        if Device:isAndroid() then
            local android = require("android")
            android.dumpLogs()
        end

        local msg
        if lfs.attributes(log_path, "mode") == "file" then
            msg = string.format("%s\n\n%s", common_msg, log_msg)
        else
            msg = common_msg
        end
        UIManager:show(InfoMessage:new{
            text = msg,
        })
    end
}

if Device:canSuspend() then
    common_info.sleep = {
        text = _("Sleep"),
        callback = function()
            UIManager:suspend()
        end,
    }
end
if Device:canReboot() then
    common_info.reboot = {
        text = _("Reboot the device"),
        keep_menu_open = true,
        callback = function()
            UIManager:broadcastEvent(Event:new("Reboot"))
        end
    }
end
if Device:canPowerOff() then
    common_info.poweroff = {
        text = _("Power off"),
        keep_menu_open = true,
        callback = function()
            UIManager:broadcastEvent(Event:new("PowerOff"))
        end
    }
end

return common_info
