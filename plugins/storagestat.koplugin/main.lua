
local Device = require("device")

if not (Device:isKobo() or Device:isKindle() or Device:isPocketBook()) then
end

local filter

-- TODO(Hzj_jie): Find the right filter for PocketBook
if Device:isKobo() or Device:isPocketBook() then
    filter = "mmcblk"
elseif Device:isKindle() then
    filter = "' /mnt/us$'"
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
        text = _("Storage Statistics"),
        callback = function()
            local std_out = io.popen(
                "df -h | sed -r 's/ +/ /g' | grep " .. filter ..
                " | cut -d ' ' -f 3,4,5,6 | " ..
                "awk '{print $4 \" U\" $1 \" F\" $2 \" P\" $3}'"
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
