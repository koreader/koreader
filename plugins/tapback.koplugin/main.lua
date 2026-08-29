local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Device = require("device")
local _ = require("gettext")

local Tapback = WidgetContainer:extend{
    name = "tapback",
    is_doc_only = false,
}

local function write_thresh(axis, val)
    local path = "/sys/devices/platform/11007000.i2c/i2c-0/0-0019/iio:device5/threshold_tap_" .. axis
    local f = io.open(path, "w")
    if f then
        f:write(tostring(val))
        f:close()
    end
end

function Tapback:init()
    if not Device:hasFancyTaps() then
        return
    end

    self.ui.menu:registerToMainMenu(self)

    self.thresh_x = G_reader_settings:readSetting("tapback_thresh_x") or 5
    self.thresh_y = G_reader_settings:readSetting("tapback_thresh_y") or 5
    self.thresh_z = G_reader_settings:readSetting("tapback_thresh_z") or 5

    write_thresh("x", self.thresh_x)
    write_thresh("y", self.thresh_y)
    write_thresh("z", self.thresh_z)
end

function Tapback:addToMainMenu(menu_items)
    menu_items.tapback_settings = {
        text = _("Tapback sensitivity"),
        sorting_hint = "more_tools",
        callback = function()
            self:showConfigDialog()
        end,
    }
end

function Tapback:showConfigDialog()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Tapback sensitivity\n\n1 = Most sensitive | 31 = Hardest | 0 = Disabled"),
        fields = {
            {
                description = _("X-axis: Tapping on the sides of the Kindle (left or right)."),
                input_type = "number",
                text = tostring(self.thresh_x),
            },
            {
                description = _("Y-axis: Tapping vertically (top or bottom)."),
                input_type = "number",
                text = tostring(self.thresh_y),
            },
            {
                description = _("Z-axis: Tapping on the back (or front screen)."),
                input_type = "number",
                text = tostring(self.thresh_z),
            }
        },
        buttons = {
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local fields = dialog:getFields()
                    local x = tonumber(fields[1]) or 5
                    local y = tonumber(fields[2]) or 5
                    local z = tonumber(fields[3]) or 5

                    self.thresh_x = x
                    self.thresh_y = y
                    self.thresh_z = z

                    G_reader_settings:saveSetting("tapback_thresh_x", x)
                    G_reader_settings:saveSetting("tapback_thresh_y", y)
                    G_reader_settings:saveSetting("tapback_thresh_z", z)

                    write_thresh("x", x)
                    write_thresh("y", y)
                    write_thresh("z", z)

                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Tapback sensitivity adjusted!"),
                    })
                end,
            },
        }
    }
    UIManager:show(dialog)
end

return Tapback
