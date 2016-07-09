local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local DocumentRegistry = require("document/documentregistry")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screenshoter = require("ui/widget/screenshoter")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local VerticalSpan = require("ui/widget/verticalspan")
local FileChooser = require("ui/widget/filechooser")
local TextWidget = require("ui/widget/textwidget")
local Blitbuffer = require("ffi/blitbuffer")
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Device = require("device")
local util = require("ffi/util")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")


local function getDefaultDir()
    if Device:isKindle() then
        return "/mnt/us/documents"
    elseif Device:isKobo() then
        return "/mnt/onboard"
    elseif Device:isAndroid() then
        return "/sdcard"
    else
        return "."
    end
end

local function restoreScreenMode()
    local screen_mode = G_reader_settings:readSetting("fm_screen_mode")
    if Screen:getScreenMode() ~= screen_mode then
        Screen:setScreenMode(screen_mode or "portrait")
    end
end

local FileManager = InputContainer:extend{
    title = _("FileManager"),
    root_path = lfs.currentdir(),
    -- our own size
    dimen = Geom:new{ w = 400, h = 600 },
    onExit = function() end,

    mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv",
    cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp",
    rm_bin = Device:isAndroid() and "/system/bin/rm" or "/bin/rm",
}

function FileManager:init()
    self.show_parent = self.show_parent or self

    self.path_text = TextWidget:new{
        face = Font:getFace("infofont", 18),
        text = self.root_path,
    }

    self.banner = VerticalGroup:new{
        TextWidget:new{
            face = Font:getFace("tfont", 24),
            text = self.title,
        },
        CenterContainer:new{
            dimen = { w = Screen:getWidth(), h = nil },
            self.path_text,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(10) }
    }

    local g_show_hidden = G_reader_settings:readSetting("show_hidden")
    local show_hidden = g_show_hidden == nil and DSHOWHIDDENFILES or g_show_hidden
    local file_chooser = FileChooser:new{
        -- remeber to adjust the height when new item is added to the group
        path = self.root_path,
        collate = G_reader_settings:readSetting("collate") or "strcoll",
        show_parent = self.show_parent,
        show_hidden = show_hidden,
        width = Screen:getWidth(),
        height = Screen:getHeight() - self.banner:getSize().h,
        is_popout = false,
        is_borderless = true,
        has_close_button = true,
        file_filter = function(filename)
            if DocumentRegistry:getProvider(filename) then
                return true
            end
        end,
        close_callback = function() return self:onClose() end,
    }
    self.file_chooser = file_chooser

    function file_chooser:onPathChanged(path)  -- luacheck: ignore
        FileManager.instance.path_text:setText(path)
        UIManager.setDirty(FileManager.instance, function()
            return "ui", FileManager.instance.banner.dimen
        end)
        return true
    end

    function file_chooser:onFileSelect(file)  -- luacheck: ignore
        FileManager.instance:onClose()
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
        return true
    end

    local copyFile = function(file) self:copyFile(file) end
    local pasteHere = function(file) self:pasteHere(file) end
    local cutFile = function(file) self:cutFile(file) end
    local deleteFile = function(file) self:deleteFile(file) end
    local renameFile = function(file) self:renameFile(file) end
    local fileManager = self

    function file_chooser:onFileHold(file)  -- luacheck: ignore
        local buttons = {
            {
                {
                    text = _("Copy"),
                    callback = function()
                        copyFile(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Paste"),
                    enabled = fileManager.clipboard and true or false,
                    callback = function()
                        pasteHere(file)
                        self:refreshPath()
                        UIManager:close(self.file_dialog)
                    end,
                },
            },
            {
                {
                    text = _("Cut"),
                    callback = function()
                        cutFile(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Delete"),
                    callback = function()
                        local ConfirmBox = require("ui/widget/confirmbox")
                        UIManager:close(self.file_dialog)
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure that you want to delete this file?\n") .. file .. ("\n") .. _("If you delete a file, it is permanently lost."),
                            ok_callback = function()
                                deleteFile(file)
                                self:refreshPath()
                            end,
                        })
                    end,
                },
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        fileManager.rename_dialog = InputDialog:new{
                            title = _("Rename file"),
                            input = util.basename(file),
                            buttons = {{
                                {
                                    text = _("OK"),
                                    enabled = true,
                                    callback = function()
                                        renameFile(file)
                                        self:refreshPath()
                                        UIManager:close(fileManager.rename_dialog)
                                    end,
                                },
                                {
                                    text = _("Cancel"),
                                    enabled = true,
                                    callback = function()
                                        UIManager:close(fileManager.rename_dialog)
                                    end,
                                },
                            }},
                        }
                        fileManager.rename_dialog:onShowKeyboard()
                        UIManager:show(fileManager.rename_dialog)
                    end,
                }
            },
        }
        if lfs.attributes(file, "mode") == "directory" then
            local realpath = util.realpath(file)
            table.insert(buttons, {
                {
                    text = _("Set as HOME directory"),
                    callback = function()
                        G_reader_settings:saveSetting("home_dir", realpath)
                        UIManager:close(self.file_dialog)
                    end
                }
            })
        end
        self.file_dialog = ButtonDialog:new{
            buttons = buttons,
        }
        UIManager:show(self.file_dialog)
        return true
    end

    self.layout = VerticalGroup:new{
        self.banner,
        file_chooser,
    }

    local fm_ui = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.layout,
    }

    self[1] = fm_ui

    self.menu = FileManagerMenu:new{
        ui = self
    }
    self.active_widgets = { Screenshoter:new{ prefix = 'FileManager' } }
    table.insert(self, self.menu)
    table.insert(self, FileManagerHistory:new{
        ui = self,
        menu = self.menu
    })

    if Device:hasKeys() then
        self.key_events.Close = { {"Home"}, doc = "close filemanager" }
    end

    self:handleEvent(Event:new("SetDimensions", self.dimen))
end

function FileManager:reinit(path)
    self.dimen = Screen:getSize()
    -- backup the root path and path items
    self.root_path = path or self.file_chooser.path
    local path_items_backup = {}
    for k, v in pairs(self.file_chooser.path_items) do
        path_items_backup[k] = v
    end
    -- reinit filemanager
    self:init()
    self.file_chooser.path_items = path_items_backup
    self:onRefresh()
end

function FileManager:toggleHiddenFiles()
    self.file_chooser:toggleHiddenFiles()
    G_reader_settings:saveSetting("show_hidden", self.file_chooser.show_hidden)
end

function FileManager:setCollate(collate)
    self.file_chooser:setCollate(collate)
    G_reader_settings:saveSetting("collate", self.file_chooser.collate)
end

function FileManager:toggleReverseCollate()
    self.file_chooser:toggleReverseCollate()
    G_reader_settings:saveSetting("reverse_collate", self.file_chooser.reverse_collate)
end

function FileManager:onClose()
    DEBUG("close filemanager")
    G_reader_settings:saveSetting("fm_screen_mode", Screen:getScreenMode())
    UIManager:close(self)
    if self.onExit then
        self:onExit()
    end
    return true
end

function FileManager:onRefresh()
    self.file_chooser:refreshPath()
    return true
end

function FileManager:copyFile(file)
    self.cutfile = false
    self.clipboard = file
end

function FileManager:cutFile(file)
    self.cutfile = true
    self.clipboard = file
end

function FileManager:pasteHere(file)
    if self.clipboard then
        file = util.realpath(file)
        local orig = util.realpath(self.clipboard)
        local dest = lfs.attributes(file, "mode") == "directory" and
            file or file:match("(.*/)")
        if self.cutfile then
            self:moveFile(orig, dest)
        else
            util.execute(self.cp_bin, "-r", orig, dest)
        end
    end
end

function FileManager:deleteFile(file)
    local ok, err
    local InfoMessage = require("ui/widget/infomessage")
    local file_abs_path = util.realpath(file)
    if file_abs_path == nil then
        UIManager:show(InfoMessage:new{
            text = util.template(_("File %1 not found"), file),
        })
        return
    end

    local is_doc = DocumentRegistry:getProvider(file_abs_path)
    ok, err = os.remove(file_abs_path)
    if ok and err == nil then
        if is_doc ~= nil then
            DocSettings:open(file):purge()
        end
        UIManager:show(InfoMessage:new{
            text = util.template(_("Deleted %1"), file),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = util.template(_("An error occurred while trying to delete %1"), file),
        })
    end
end

function FileManager:renameFile(file)
    local InfoMessage = require("ui/widget/infomessage")
    if util.basename(file) ~= self.rename_dialog:getInputText() then
        local dest = util.joinPath(util.dirname(file), self.rename_dialog:getInputText())
        if self:moveFile(file, dest) then
            if lfs.attributes(dest, "mode") == "file" then
                local doc = require("docsettings")
                local move_history = true;
                if lfs.attributes(doc:getHistoryPath(file), "mode") == "file" and
                   not self:moveFile(doc:getHistoryPath(file), doc:getHistoryPath(dest)) then
                   move_history = false
                end
                if lfs.attributes(doc:getSidecarDir(file), "mode") == "directory" and
                   not self:moveFile(doc:getSidecarDir(file), doc:getSidecarDir(dest)) then
                   move_history = false
                end
                if move_history then
                    UIManager:show(InfoMessage:new{
                        text = util.template(_("Renamed from %1 to %2"), file, dest),
                        timeout = 2,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = util.template(_(
                            "Failed to move history data of %1 to %2.\n" ..
                            "The reading history may be lost."), file, dest),
                    })
                end
            end
        else
            UIManager:show(InfoMessage:new{
                text = util.template(
                           _("Failed to rename from %1 to %2"), file, dest),
            })
        end
    end
end

function FileManager:getSortingMenuTable()
    local fm = self
    local collates = {
        strcoll = {_("by title"), _("Sort by title")},
        access = {_("by date"), _("Sort by date")},
    }
    local set_collate_table = function(collate)
        return {
            text = collates[collate][2],
            checked_func = function()
                return fm.file_chooser.collate == collate
            end,
            callback = function() fm:setCollate(collate) end,
        }
    end
    return {
        text_func = function()
            return util.template(
                _("Sort order: %1"),
                collates[fm.file_chooser.collate][1]
            )
        end,
        sub_item_table = {
            set_collate_table("strcoll"),
            set_collate_table("access"),
        }
    }
end

function FileManager:showFiles(path)
    path = path or G_reader_settings:readSetting("lastdir") or getDefaultDir()
    G_reader_settings:saveSetting("lastdir", path)
    restoreScreenMode()
    local file_manager = FileManager:new{
        dimen = Screen:getSize(),
        root_path = path,
        onExit = function()
            self.instance = nil
        end
    }
    UIManager:show(file_manager)
    self.instance = file_manager
end

--[[
A shortcut to execute mv command (self.mv_bin) with from and to as parameters.
Returns a boolean value to indicate the result of mv command.
--]]
function FileManager:moveFile(from, to)
    return util.execute(self.mv_bin, from, to) == 0
end

return FileManager
