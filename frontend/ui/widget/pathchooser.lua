local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")
local _ = require("gettext")
local T = util.template

local PathChooser = FileChooser:extend{
    title = nil, -- a generic title will be set in init() if none given
    no_title = false,
    show_path = true,
    is_popout = false,
    covers_fullscreen = true, -- set it to false if you set is_popout = true
    is_borderless = true,
    -- smaller font to allow displaying our long titles
    tface = Font:getFace("smalltfont"),

    select_directory = true, -- allow selecting directories
    select_file = true,      -- allow selecting files
    show_files = true, -- show files, even if select_files=false
    -- (directories are always shown, to allow navigation)
    show_hidden = G_reader_settings:readSetting("show_hidden"),
}

function PathChooser:init()
    if not title then -- default titles depending on options
        if self.select_directory and not self.select_file then
            self.title = _("Select directory (long press to confirm)")
        elseif not self.select_directory and self.select_file then
            self.title = _("Select file (long press to confirm)")
        else
            self.title = _("Select path (long press to confirm)")
        end
    end
    if not self.show_files then
        self.file_filter = function() return false end -- filter out regular files
    end
    if self.select_directory then
        -- Let FileChooser display "Long press to select current directory"
        self.show_current_dir_for_hold = true
    end
    FileChooser.init(self)
end

function PathChooser:onMenuSelect(item)
    local path = item.path
    if path:sub(-2, -1) == "/." then -- with show_current_dir_for_hold
        -- Don't navigate to same directory
        return true
    end
    local path = util.realpath(path)
    if lfs.attributes(path, "mode") ~= "directory" then
        -- Do nothing if Tap on other than directories
        return true
    end
    -- Let this method check permissions and if we can list
    -- this directory: we should get at least one item: ".."
    local sub_table = self:genItemTableFromPath(path)
    if #sub_table > 0 then
        self:changeToPath(path)
    end
    return true
end

function PathChooser:onMenuHold(item)
    local path = item.path
    if path:sub(-2, -1) == "/." then -- with show_current_dir_for_hold
        path = path:sub(1, -3)
    end
    local path = util.realpath(path)
    local path_type = lfs.attributes(path, "mode")
    if path_type == "file" and not self.select_file then
        return true
    end
    if path_type == "directory" and not self.select_directory then
        return true
    end
    local title
    if path_type == "file" then
        title = T(_("Select this file?\n%1"), path)
    elseif path_type == "directory" then
        title = T(_("Select this directory?\n%1"), path)
    else -- just in case we get something else
        title = T(_("Select this path?\n%1"), path)
    end
    local onConfirm = self.onConfirm
    self.button_dialog = ButtonDialogTitle:new{
        title = title,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.button_dialog)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        if onConfirm then
                            onConfirm(path)
                        end
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
