local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
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
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local PluginLoader = require("pluginloader")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderUI = require("apps/reader/readerui")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local RenderText = require("ui/rendertext")
local Screenshoter = require("ui/widget/screenshoter")
local Size = require("ui/size")
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
local T = require("ffi/util").template

local function restoreScreenMode()
    local screen_mode = G_reader_settings:readSetting("fm_screen_mode")
    if Screen:getScreenMode() ~= screen_mode then
        Screen:setScreenMode(screen_mode or "portrait")
    end
end

local function truncatePath(text)
    local screen_width = Screen:getWidth()
    local face = Font:getFace("xx_smallinfofont")
    -- we want to truncate text on the left, so work with the reverse of text (which is fine as we don't use kerning)
    local reversed_text = require("util").utf8Reverse(text)
    local txt_width = RenderText:sizeUtf8Text(0, screen_width, face, reversed_text, false, false).x
    if  screen_width - 2 * Size.padding.small < txt_width then
        reversed_text = RenderText:truncateTextByWidth(reversed_text, face, screen_width - 2 * Size.padding.small, false, false)
        text = require("util").utf8Reverse(reversed_text)
    end
    return text
end

local FileManager = InputContainer:extend{
    title = _("KOReader File Browser"),
    root_path = lfs.currentdir(),
    onExit = function() end,

    mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv",
    cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp",
    mkdir_bin =  Device:isAndroid() and "/system/bin/mkdir" or "/bin/mkdir",
}

function FileManager:init()
    self.show_parent = self.show_parent or self
    local icon_size = Screen:scaleBySize(35)
    local home_button = IconButton:new{
        icon_file = "resources/icons/appbar.home.png",
        scale_for_dpi = false,
        width = icon_size,
        height = icon_size,
        padding = Size.padding.default,
        padding_left = Size.padding.large,
        padding_right = Size.padding.large,
        padding_bottom = 0,
        callback = function() self:goHome() end,
        hold_callback = function() self:setHome() end,
    }

    local plus_button = IconButton:new{
        icon_file = "resources/icons/appbar.plus.png",
        scale_for_dpi = false,
        width = icon_size,
        height = icon_size,
        padding = Size.padding.default,
        padding_left = Size.padding.large,
        padding_right = Size.padding.large,
        padding_bottom = 0,
        callback = function() self:tapPlus() end,
    }

    self.path_text = TextWidget:new{
        face = Font:getFace("xx_smallinfofont"),
        text = truncatePath(filemanagerutil.abbreviate(self.root_path)),
    }

    self.banner = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        VerticalGroup:new {
            CenterContainer:new {
                dimen = { w = Screen:getWidth(), h = nil },
                HorizontalGroup:new {
                    home_button,
                    VerticalGroup:new {
                        Button:new {
                            readonly = true,
                            bordersize = 0,
                            padding = 0,
                            text_font_bold = false,
                            text_font_face = "smalltfont",
                            text_font_size = 24,
                            text = self.title,
                            width = Screen:getWidth() - 2 * icon_size - 4 * Size.padding.large,
                        },
                    },
                    plus_button,
                }
            },
            CenterContainer:new{
                dimen = { w = Screen:getWidth(), h = nil },
                self.path_text,
            },
            VerticalSpan:new{ width = Screen:scaleBySize(5) },
        }
    }

    local g_show_hidden = G_reader_settings:readSetting("show_hidden")
    local show_hidden = g_show_hidden == nil and DSHOWHIDDENFILES or g_show_hidden
    local file_chooser = FileChooser:new{
        -- remeber to adjust the height when new item is added to the group
        path = self.root_path,
        focused_path = self.focused_file,
        collate = G_reader_settings:readSetting("collate") or "strcoll",
        reverse_collate = G_reader_settings:isTrue("reverse_collate"),
        show_parent = self.show_parent,
        show_hidden = show_hidden,
        width = Screen:getWidth(),
        height = Screen:getHeight() - self.banner:getSize().h,
        is_popout = false,
        is_borderless = true,
        has_close_button = true,
        perpage = G_reader_settings:readSetting("items_per_page"),
        file_filter = function(filename)
            if DocumentRegistry:hasProvider(filename) then
                return true
            end
        end,
        close_callback = function() return self:onClose() end,
    }
    self.file_chooser = file_chooser
    self.focused_file = nil -- use it only once

    function file_chooser:onPathChanged(path)  -- luacheck: ignore
        FileManager.instance.path_text:setText(truncatePath(filemanagerutil.abbreviate(path)))
        UIManager:setDirty(FileManager.instance, function()
            return "ui", FileManager.instance.path_text.dimen
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
    local setHome = function(path) self:setHome(path) end
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
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Purge .sdr"),
                    enabled = DocSettings:hasSidecarFile(util.realpath(file)),
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = util.template(_("Purge .sdr to reset settings for this document?\n\n%1"), self.file_dialog.title),
                            ok_text = _("Purge"),
                            ok_callback = function()
                                filemanagerutil.purgeSettings(file)
                                filemanagerutil.removeFileFromHistoryIfWanted(file)
                                self:refreshPath()
                                UIManager:close(self.file_dialog)
                            end,
                        })
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
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure that you want to delete this file?\n") .. file .. ("\n") .. _("If you delete a file, it is permanently lost."),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                deleteFile(file)
                                filemanagerutil.removeFileFromHistoryIfWanted(file)
                                self:refreshPath()
                                UIManager:close(self.file_dialog)
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
                        UIManager:show(fileManager.rename_dialog)
                        fileManager.rename_dialog:onShowKeyboard()
                    end,
                }
            },
            -- a little hack to get visual functionality grouping
            {},
            {
                {
                    text = _("Open with…"),
                    enabled = lfs.attributes(file, "mode") == "file"
                        and #(DocumentRegistry:getProviders(file)) > 1,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        DocumentRegistry:showSetProviderButtons(file, FileManager.instance, self, ReaderUI)
                    end,
                },
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
                        setHome(realpath)
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
        self.key_events.Home = { {"Home"}, doc = "go home" }
        --Override the menu.lua way of handling the back key
        self.file_chooser.key_events.Back = { {"Back"}, doc = "go back" }
    end

    self:handleEvent(Event:new("SetDimensions", self.dimen))
end

function FileChooser:onBack()
    local back_to_exit = G_reader_settings:readSetting("back_to_exit") or "prompt"
    if back_to_exit == "always" then
        return self:onClose()
    elseif back_to_exit == "disable" then
        return true
    elseif back_to_exit == "prompt" then
            UIManager:show(ConfirmBox:new{
                text = _("Exit KOReader?"),
                ok_text = _("Exit"),
                ok_callback = function()
                    self:onClose()
                end
            })
        return true
    end
end

function FileManager:tapPlus()
    local buttons = {
        {
            {
                text = _("New folder"),
                callback = function()
                    UIManager:close(self.file_dialog)
                    self.input_dialog = InputDialog:new{
                        title = _("Create new folder"),
                        input_type = "text",
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        self:closeInputDialog()
                                    end,
                                },
                                {
                                    text = _("Create"),
                                    callback = function()
                                        self:closeInputDialog()
                                        local new_folder = self.input_dialog:getInputText()
                                        if new_folder and new_folder ~= "" then
                                            self:createFolder(self.file_chooser.path, new_folder)
                                        end
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(self.input_dialog)
                    self.input_dialog:onShowKeyboard()
                end,
            },
        },
        {
            {
                text = _("Paste"),
                enabled = self.clipboard and true or false,
                callback = function()
                    self:pasteHere(self.file_chooser.path)
                    self:onRefresh()
                    UIManager:close(self.file_dialog)
                end,
            },
        },
        {
            {
                text = _("Set as HOME directory"),
                callback = function()
                    self:setHome(self.file_chooser.path)
                    UIManager:close(self.file_dialog)
                end
            }
        },
        {
            {
                text = _("Go to HOME directory"),
                callback = function()
                    self:goHome()
                    UIManager:close(self.file_dialog)
                end
            }
        }
    }

    self.file_dialog = ButtonDialogTitle:new{
        title = filemanagerutil.abbreviate(self.file_chooser.path),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
end

function FileManager:reinit(path, focused_file)
    self.dimen = Screen:getSize()
    -- backup the root path and path items
    self.root_path = path or self.file_chooser.path
    local path_items_backup = {}
    for k, v in pairs(self.file_chooser.path_items) do
        path_items_backup[k] = v
    end
    -- reinit filemanager
    self.focused_file = focused_file
    self:init()
    self.file_chooser.path_items = path_items_backup
    -- self:init() has already done file_chooser:refreshPath(), so this one
    -- looks like not necessary (cheap with classic mode, less cheap with
    -- CoverBrowser plugin's cover image renderings)
    -- self:onRefresh()
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
    G_reader_settings:flush()
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

function FileManager:goHome()
    local home_dir = G_reader_settings:readSetting("home_dir")
    if home_dir then
        self.file_chooser:changeToPath(home_dir)
    else
        self:setHome()
    end
    return true
end

function FileManager:setHome(path)
    path = path or self.file_chooser.path
    UIManager:show(ConfirmBox:new{
        text = util.template(_("Set '%1' as HOME directory?"), path),
        ok_text = _("Set as HOME"),
        ok_callback = function()
            G_reader_settings:saveSetting("home_dir", path)
        end,
    })
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

        local function infoCopyFile()
            -- if we copy a file, also copy its sidecar directory
            if DocSettings:hasSidecarFile(orig) then
                util.execute(self.cp_bin, "-r", DocSettings:getSidecarDir(orig), dest)
            end
            if util.execute(self.cp_bin, "-r", orig, dest) == 0 then
                UIManager:show(InfoMessage:new {
                    text = T(_("Copied to: %1"), dest),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("An error occurred while trying to copy %1"), orig),
                    timeout = 2,
                })
            end
        end

        local function infoMoveFile()
            -- if we move a file, also move its sidecar directory
            if DocSettings:hasSidecarFile(orig) then
                self:moveFile(DocSettings:getSidecarDir(orig), dest) -- dest is always a directory
            end
            if self:moveFile(orig, dest) then
                --update history
                local dest_file = string.format("%s/%s", dest, util.basename(orig))
                require("readhistory"):updateItemByPath(orig, dest_file)
                --update last open file
                if G_reader_settings:readSetting("lastfile") == orig then
                    G_reader_settings:saveSetting("lastfile", dest_file)
                end
                UIManager:show(InfoMessage:new {
                    text = T(_("Moved to: %1"), dest),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("An error occurred while trying to move %1"), orig),
                    timeout = 2,
                })
            end
            util.execute(self.cp_bin, "-r", orig, dest)
        end

        local info_file
        if self.cutfile then
            info_file = infoMoveFile
        else
            info_file = infoCopyFile
        end
        local basename = util.basename(self.clipboard)
        local mode = lfs.attributes(string.format("%s/%s", dest, basename), "mode")
        if mode == "file" or mode == "directory" then
            local text
            if mode == "file" then
                text = T(_("The file %1 already exists. Do you want to overwrite it?"), basename)
            else
                text = T(_("The directory %1 already exists. Do you want to overwrite it?"), basename)
            end

            UIManager:show(ConfirmBox:new {
                text = text,
                ok_text = _("Overwrite"),
                ok_callback = function()
                    info_file()
                    self:onRefresh()
                end,
            })
        else
            info_file()
            self:onRefresh()
        end
    end
end

function FileManager:createFolder(curr_folder, new_folder)
    local folder = string.format("%s/%s", curr_folder, new_folder)
    local code = util.execute(self.mkdir_bin, folder)
    local text
    if code == 0 then
        self:onRefresh()
        text = T(_("Folder created:\n%1"), new_folder)
    else
        text = _("The folder has not been created.")
    end
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 2,
    })
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

    local is_doc = DocumentRegistry:hasProvider(file_abs_path)
    if lfs.attributes(file_abs_path, "mode") == "file" then
        ok, err = os.remove(file_abs_path)
    else
        ok, err = util.purgeDir(file_abs_path)
    end
    if ok and not err then
        if is_doc then
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
        percent_unopened_first = {_("percent - unopened first"), _("Sort by percent - unopened first")},
        percent_unopened_last = {_("percent - unopened last"), _("Sort by percent - unopened last")},
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
                _("Sort by: %1"),
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
            set_collate_table("percent_unopened_first"),
            set_collate_table("percent_unopened_last"),
        }
    }
end

function FileManager:getStartWithMenuTable()
    local start_with_setting = G_reader_settings:readSetting("start_with") or "filemanager"
    local start_withs = {
        filemanager = {_("file browser"), _("Start with file browser")},
        history = {_("history"), _("Start with history")},
        last = {_("last file"), _("Start with last file")},
    }
    local set_sw_table = function(start_with)
        return {
            text = start_withs[start_with][2],
            checked_func = function()
                return start_with_setting == start_with
            end,
            callback = function()
                start_with_setting = start_with
                G_reader_settings:saveSetting("start_with", start_with)
            end,
        }
    end
    return {
        text_func = function()
            return util.template(
                _("Start with: %1"),
                start_withs[start_with_setting][1]
            )
        end,
        sub_item_table = {
            set_sw_table("filemanager"),
            set_sw_table("history"),
            set_sw_table("last"),
        }
    }
end

function FileManager:showFiles(path, focused_file)
    path = path or G_reader_settings:readSetting("lastdir") or filemanagerutil.getDefaultDir()
    G_reader_settings:saveSetting("lastdir", path)
    restoreScreenMode()
    local file_manager = FileManager:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        root_path = path,
        focused_file = focused_file,
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

function FileManager:onHome()
    return self:goHome()
end

return FileManager
