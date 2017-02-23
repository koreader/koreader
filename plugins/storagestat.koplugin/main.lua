
local Device = require("device")

local filter

-- TODO(Hzj_jie): Find the right filter for PocketBook
if Device:isKobo() or Device:isPocketBook() then
    filter = "mmcblk"
elseif Device:isKindle() then
    filter = "' /mnt/us$'"
elseif Device:isSDL() then
    filter = "/dev/sd"
else
    return { disabled = true, }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local StorageStat = WidgetContainer:new{
    name = "storagestat",
    menuItem = {
        text = _("Storage statistics"),
        callback = function()
            local std_out = io.popen(
                "df -h | sed -r 's/ +/ /g' | grep " .. filter ..
                " | cut -d ' ' -f 2,3,4,5,6 | " ..
                "awk '{print $5\": \\n Available: \" $3\"/\" $1 \"\\n Used: \" $4}'"
            )
            local msg
            if std_out then
                msg = std_out:read("*all")
                std_out:close()
            end
            if msg == nil or msg == "" then
                msg = _("Failed to retrieve storage information.")
            end

            UIManager:show(InfoMessage:new{
                text = msg,
            })
        end
    }
}

function StorageStat:init()
    self.ui.menu:registerToMainMenu(self)
end

function StorageStat:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, self.menuItem)
end

return StorageStat
