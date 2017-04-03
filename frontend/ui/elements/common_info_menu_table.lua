local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local common_info = {}

if Device:isKindle() or Device:isKobo() or Device:isPocketBook()
    or Device:isAndroid() then
    local OTAManager = require("ui/otamanager")
    common_info.ota_update = OTAManager:getOTAMenuTable()
end
local version = io.open("git-rev", "r"):read()
common_info.version = {
    text = _("Version"),
    callback = function()
        UIManager:show(InfoMessage:new{
            text = version,
        })
    end
}
common_info.help = {
    text = _("Help"),
}
common_info.about = {
    text = _("About"),
    callback = function()
        UIManager:show(InfoMessage:new{
            text = T(_("KOReader %1\n\nA document viewer for E Ink devices.\n\nLicensed under Affero GPL v3. All dependencies are free software.\n\nhttp://koreader.rocks/"), version),
        })
    end
}
common_info.report_bug = {
    text = _("Report a bug"),
    callback = function()
        local model = Device.model
        UIManager:show(InfoMessage:new{
            text = T(_("Please report bugs to \nhttps://github.com/koreader/koreader/issues\n\nVersion:\n%1\n\nDetected device:\n%2"),
                version, model),
        })
    end
}

return common_info
