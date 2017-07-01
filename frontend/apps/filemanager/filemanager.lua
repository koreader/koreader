local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileChooser = require("ui/widget/filechooser")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local PluginLoader = require("pluginloader")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderUI = require("apps/reader/readerui")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local Screenshoter = require("ui/widget/screenshoter")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen

local function restoreScreenMode()
    local screen_mode = G_reader_settings:readSetting("fm_screen_mode")
    if Screen:getScreenMode() ~= screen_mode then
        Screen:setScreenMode(screen_mode or "portrait")
    end
end

local FileManager = InputContainer:extend{
    title = _("KOReader File Browser"),
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
        face = Font:getFace("xx_smallinfofont"),
        text = filemanagerutil.abbreviate(self.root_path),
    }

    self.banner = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        VerticalGroup:new{
            TextWidget:new{
                face = Font:getFace("smalltfont"),
                text = self.title,
            },
            CenterContainer:new{
                dimen = { w = Screen:getWidth(), h = nil },
                self.path_text,
            },
            VerticalSpan:new{ width = Screen:scaleBySize(10) }
        }
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
        FileManager.instance.path_text:setText(filemanagerutil.abbreviate(path))
        UIManager:setDirty(FileManager.instance, function()
            return "ui", FileManager.instance.banner.dimen
        end)
        return true
    end

    function file_chooser:onFileSelect(file)  -- luacheck: ignore
        FileManager.instance:onClose()
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
                {
                    text = _("Purge .sdr"),
                    enabled = DocSettings:hasSidecarFile(util.realpath(file)),
                    callback = function()
                        local file_abs_path = util.realpath(file)
                        if file_abs_path then
                            local autoremove_deleted_items_from_history = G_reader_settings:readSetting("autoremove_deleted_items_from_history") or false
                            os.remove(DocSettings:getSidecarFile(file_abs_path))
                            -- If the sidecar folder is empty, os.remove() can
                            -- delete it. Otherwise, the following statement has no
                            -- effect.
                            os.remove(DocSettings:getSidecarDir(file_abs_path))
                            self:refreshPath()
                            -- also delete from history if autoremove_deleted_items_from_history is enabled
                            if autoremove_deleted_items_from_history then
                                require("readhistory"):removeItemByPath(file_abs_path)
                            end
                        end
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
                            ok_text = _("Delete"),
                            ok_callback = function()
                                local autoremove_deleted_items_from_history = G_reader_settings:readSetting("autoremove_deleted_items_from_history") or false
                                local file_abs_path = util.realpath(file)
                                deleteFile(file)
                                -- also delete from history if autoremove_deleted_items_from_history is enabled
                                if autoremove_deleted_items_from_history then
                                    if file_abs_path then
                                        require("readhistory"):removeItemByPath(file_abs_path)
                                    end
                                end
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
                                    text = _("Cancel"),
                                    enabled = true,
                                    callback = function()
                                        UIManager:close(fileManager.rename_dialog)
                                    end,
                                },
                                {
                                    text = _("Rename"),
                                    enabled = true,
                                    callback = function()
                                        renameFile(file)
                                        self:refreshPath()
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
            -- a little hack to get visual functionality grouping
            {},
            {
                {
                    text = _("Convert"),
                    enabled = lfs.attributes(file, "mode") == "file"
                        and FileManagerConverter:isSupported(file),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        FileManagerConverter:showConvertButtons(file, self)
                    end,
                },
                {
                    text = _("Book information"),
                    enabled = FileManagerBookInfo:isSupported(file),
                    callback = function()
                        FileManagerBookInfo:show(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
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

        self.file_dialog = ButtonDialogTitle:new{
            title = file:match("([^/]+)$"),
            title_align = "center",
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
    })
    table.insert(self, ReaderDictionary:new{ ui = self })
    table.insert(self, ReaderWikipedia:new{ ui = self })

    -- koreader plugins
    for _,plugin_module in ipairs(PluginLoader:loadPlugins()) do
        if not plugin_module.is_doc_only then
            local ok, plugin_or_err = PluginLoader:createPluginInstance(
                plugin_module, { ui = self, })
            -- Keep references to the modules which do not register into menu.
            if ok then
                table.insert(self, plugin_or_err)
                logger.info("FM loaded plugin", plugin_module.name,
                            "at", plugin_module.path)
            end
        end
    end

    if Device:hasKeys() then
        self.key_events.Close = { {"Home"}, doc = "Close file manager" }
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
    logger.dbg("close filemanager")
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
            -- if we move a file, also move its sidecar directory
            if DocSettings:hasSidecarFile(orig) then
                self:moveFile(DocSettings:getSidecarDir(orig), dest) -- dest is always a directory
            end
            self:moveFile(orig, dest)
        else
            util.execute(self.cp_bin, "-r", orig, dest)
        end
    end
end

function FileManager:deleteFile(file)
    local ok, err
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
                        text = util.template(
                            _("Failed to move history data of %1 to %2.\nThe reading history may be lost."),
                            file, dest),
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
        strcoll = {_("title"), _("Sort by title")},
        access = {_("date read"), _("Sort by last read date")},
        change = {_("date added"), _("Sort by date added")},
        modification = {_("date modified"), _("Sort by date modified")},
        size = {_("size"), _("Sort by size")},
        type = {_("type"), _("Sort by type")},
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
                _("Sort by %1"),
                collates[fm.file_chooser.collate][1]
            )
        end,
        sub_item_table = {
            set_collate_table("strcoll"),
            set_collate_table("access"),
            set_collate_table("change"),
            set_collate_table("modification"),
            set_collate_table("size"),
            set_collate_table("type"),
        }
    }
end

function FileManager:showFiles(path)
    path = path or G_reader_settings:readSetting("lastdir") or filemanagerutil.getDefaultDir()
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
