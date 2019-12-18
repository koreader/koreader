local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local common_info = {}

if Device:hasOTAUpdates() then
    local OTAManager = require("ui/otamanager")
    common_info.ota_update = OTAManager:getOTAMenuTable()
end
local version = require("version"):getCurrentRevision()
common_info.version = {
    text = _("Version"),
    keep_menu_open = true,
    callback = function()
        UIManager:show(InfoMessage:new{
            text = version,
        })
    end
}
common_info.help = {
    text = _("Help"),
}
common_info.more_plugins = {
    text = _("More plugins"),
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
            text = T(_("KOReader %1\n\nA document viewer for E Ink devices.\n\nLicensed under Affero GPL v3. All dependencies are free software.\n\nhttp://koreader.rocks/"), BD.ltr(version)),
            icon_file = "resources/ko-icon.png",
            alpha = true,
        })
    end
}
common_info.report_bug = {
    text = _("Report a bug"),
    keep_menu_open = true,
    callback = function()
        local device = Device.model
        if Device:isAndroid() then
            device = Device:info()
        end

        UIManager:show(InfoMessage:new{
            text = T(_("Please report bugs to \nhttps://github.com/koreader/koreader/issues\n\nVersion:\n%1\n\nDetected device:\n%2"),
                version, device),
        })
    end
}

if Device:isCervantes() or Device:isKindle() or Device:isKobo() then
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
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to reboot the device?"),
                ok_text = _("Reboot"),
                ok_callback = function()
                    UIManager:nextTick(UIManager.reboot_action)
                end,
            })
        end
    }
end
if Device:canPowerOff() then
    common_info.poweroff = {
        text = _("Power off"),
        keep_menu_open = true,
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to power off the device?"),
                ok_text = _("Power off"),
                ok_callback = function()
                    UIManager:nextTick(UIManager.poweroff_action)
                end,
            })
        end
    }
end

return common_info
