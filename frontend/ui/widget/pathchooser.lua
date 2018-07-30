local ButtonDialog = require("ui/widget/buttondialog")
local FileChooser = require("ui/widget/filechooser")
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")

local PathChooser = FileChooser:extend{
    title = _("Choose Path"),
    no_title = false,
    show_path = true,
    is_popout = false,
    covers_fullscreen = true, -- set it to false if you set is_popout = true
    is_borderless = true,
    show_filesize = false,
    file_filter = function() return false end, -- filter out regular files
}

function PathChooser:onMenuSelect(item)
    self.path = util.realpath(item.path)
    local sub_table = self:genItemTableFromPath(self.path)
    -- if sub table only have one entry(itself) we do nothing
    if #sub_table > 1 then
        self:changeToPath(item.path)
    end
    return true
end

function PathChooser:onMenuHold(item)
    local onConfirm = self.onConfirm
    self.button_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("Confirm"),
                    callback = function()
                        if onConfirm then onConfirm(item.path) end
                        UIManager:close(self.button_dialog)
                        UIManager:close(self)
                    end,
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.button_dialog)
                        UIManager:close(self)
                    end,
                },
            },
        },
    }
    UIManager:show(self.button_dialog)
    return true
end

return PathChooser
