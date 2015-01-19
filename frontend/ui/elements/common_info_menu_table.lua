local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local common_info = {}

if Device:isKindle() or Device:isKobo() or Device:isPocketBook() then
    local OTAManager = require("ui/otamanager")
    table.insert(common_info, OTAManager:getOTAMenuTable())
end
table.insert(common_info, {
    text = _("Version"),
    callback = function()
        UIManager:show(InfoMessage:new{
            text = io.open("git-rev", "r"):read(),
        })
    end
})
table.insert(common_info, {
    text = _("Help"),
    callback = function()
        UIManager:show(InfoMessage:new{
            text = _("Please report bugs to \nhttps://github.com/koreader/koreader/issues"),
        })
    end
})

return common_info
