local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local PathChooser = FileChooser:extend{
    title = true, -- or a string
        -- if let to true, a generic title will be set in init()
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
    detailed_file_info = false, -- show size and last mod time in Select message
}

function PathChooser:init()
    if self.title == true then -- default title depending on options
        if self.select_directory and not self.select_file then
            self.title = _("Long-press to select directory")
        elseif not self.select_directory and self.select_file then
            self.title = _("Long-press to select file")
        else
            self.title = _("Long-press to select")
        end
    end
    self.show_hidden = G_reader_settings:readSetting("show_hidden")
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
    path = ffiutil.realpath(path)
    if not path then
        -- If starting in a no-more existing directory, allow
        -- not getting stuck in it
        self:changeToPath("/")
        return true
    end
    local attr = lfs.attributes(path)
    if not attr then
        -- Same as above
        self:changeToPath("/")
        return true
    end
    if attr.mode ~= "directory" then
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
    path = ffiutil.realpath(path)
    if not path then
        return true
    end
    local attr = lfs.attributes(path)
    if not attr then
        return true
    end
    if attr.mode == "file" and not self.select_file then
        return true
    end
    if attr.mode == "directory" and not self.select_directory then
        return true
    end
    local title
    if attr.mode == "file" then
        if self.detailed_file_info then
            local filesize = util.getFormattedSize(attr.size)
            local lastmod = os.date("%Y-%m-%d %H:%M", attr.modification)
            title = T(_("Select this file?\n\n%1\n\nFile size: %2 bytes\nLast modified: %3"),
                        BD.filepath(path), filesize, lastmod)
        else
            title = T(_("Select this file?\n\n%1"), BD.filepath(path))
        end
    elseif attr.mode == "directory" then
        title = T(_("Select this directory?\n\n%1"), BD.dirpath(path))
    else -- just in case we get something else
        title = T(_("Select this path?\n\n%1"), BD.path(path))
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
