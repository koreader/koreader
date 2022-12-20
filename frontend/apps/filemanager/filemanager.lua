local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DeviceListener = require("device/devicelistener")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileChooser = require("ui/widget/filechooser")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local FrameContainer = require("ui/widget/container/framecontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LanguageSupport = require("languagesupport")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local PluginLoader = require("pluginloader")
local ReadCollection = require("readcollection")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local Screenshoter = require("ui/widget/screenshoter")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local BaseUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local Screen = Device.screen
local T = BaseUtil.template

local FileManager = InputContainer:extend{
    title = _("KOReader"),
    active_widgets = nil, -- array
    root_path = lfs.currentdir(),

    clipboard = nil, -- for single file operations
    selected_files = nil, -- for group file operations

    mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv",
    cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp",
    mkdir_bin =  Device:isAndroid() and "/system/bin/mkdir" or "/bin/mkdir",
}

function FileManager:onSetRotationMode(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        Screen:setRotationMode(rotation)
        if FileManager.instance then
            self:reinit(self.path, self.focused_file)
        end
    end
    return true
end

function FileManager:onPhysicalKeyboardConnected()
    -- So that the key navigation shortcuts apply right away.
    -- This will also naturally call registerKeyEvents
    self:reinit(self.path, self.focused_file)
end
FileManager.onPhysicalKeyboardDisconnected = FileManager.onPhysicalKeyboardConnected

function FileManager:setRotationMode()
    local locked = G_reader_settings:isTrue("lock_rotation")
    if not locked then
        local rotation_mode = G_reader_settings:readSetting("fm_rotation_mode") or Screen.DEVICE_ROTATED_UPRIGHT
        self:onSetRotationMode(rotation_mode)
    end
end

function FileManager:initGesListener()
    if not Device:isTouchDevice() then
        return
    end

    self:registerTouchZones({
        {
            id = "filemanager_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = 0,
                ratio_w = Screen:getWidth(), ratio_h = Screen:getHeight(),
            },
            handler = function(ges)
                self:onSwipeFM(ges)
            end,
        },
    })
end

function FileManager:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:updateTouchZonesOnScreenResize(dimen)
    end
end

function FileManager:setupLayout()
    self.show_parent = self.show_parent or self
    self.title_bar = TitleBar:new{
        fullscreen = "true",
        align = "center",
        title = self.title,
        title_top_padding = Screen:scaleBySize(6),
        subtitle = BD.directory(filemanagerutil.abbreviate(self.root_path)),
        subtitle_truncate_left = true,
        subtitle_fullwidth = true,
        button_padding = Screen:scaleBySize(5),
        left_icon = "home",
        left_icon_size_ratio = 1,
        left_icon_tap_callback = function() self:goHome() end,
        left_icon_hold_callback = false, -- propagate long-press to dispatcher
        right_icon = "plus",
        right_icon_size_ratio = 1,
        right_icon_tap_callback = function() self:onShowPlusMenu() end,
        right_icon_hold_callback = false, -- propagate long-press to dispatcher
    }

    local show_hidden = G_reader_settings:isTrue("show_hidden") or G_defaults:readSetting("DSHOWHIDDENFILES")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local file_chooser = FileChooser:new{
        -- remember to adjust the height when new item is added to the group
        path = self.root_path,
        focused_path = self.focused_file,
        collate = G_reader_settings:readSetting("collate") or "strcoll",
        reverse_collate = G_reader_settings:isTrue("reverse_collate"),
        show_parent = self.show_parent,
        show_hidden = show_hidden,
        width = Screen:getWidth(),
        height = Screen:getHeight() - self.title_bar:getHeight(),
        is_popout = false,
        is_borderless = true,
        has_close_button = true,
        show_unsupported = show_unsupported,
        file_filter = function(filename)
            if DocumentRegistry:hasProvider(filename) then
                return true
            end
        end,
        close_callback = function() return self:onClose() end,
        -- allow left bottom tap gesture, otherwise it is eaten by hidden return button
        return_arrow_propagation = true,
        -- allow Menu widget to delegate handling of some gestures to GestureManager
        filemanager = self,
        -- let Menu widget merge our title_bar into its own TitleBar's FocusManager layout
        outer_title_bar = self.title_bar,
    }
    self.file_chooser = file_chooser
    self.focused_file = nil -- use it only once

    local file_manager = self

    function file_chooser:onPathChanged(path)  -- luacheck: ignore
        file_manager.title_bar:setSubTitle(BD.directory(filemanagerutil.abbreviate(path)))
        return true
    end

    function file_chooser:onFileSelect(file)  -- luacheck: ignore
        if file_manager.select_mode then
            if file_manager.selected_files[file] then
                file_manager.selected_files[file] = nil
            else
                file_manager.selected_files[file] = true
            end
            self:refreshPath()
        else
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(file)
        end
        return true
    end

    local copyFile = function(file) self:copyFile(file) end
    local pasteHere = function(file) self:pasteHere(file) end
    local cutFile = function(file) self:cutFile(file) end
    local deleteFile = function(file) self:deleteFile(file) end
    local renameFile = function(file) self:renameFile(file) end
    local setHome = function(path) self:setHome(path) end

    function file_chooser:onFileHold(file)
        if file_manager.select_mode then
            file_manager:tapPlus()
        else
            self:showFileDialog(file)
        end
    end

    function file_chooser:showFileDialog(file)  -- luacheck: ignore
        local is_file = lfs.attributes(file, "mode") == "file"
        local is_folder = lfs.attributes(file, "mode") == "directory"
        local is_not_parent_folder = BaseUtil.basename(file) ~= ".."
        local buttons = {
            {
                {
                    text = C_("File", "Copy"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        copyFile(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = C_("File", "Paste"),
                    enabled = file_manager.clipboard and true or false,
                    callback = function()
                        pasteHere(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:onToggleSelectMode(true) -- no full screen refresh
                        if is_file then
                            file_manager.selected_files[file] = true
                            self:refreshPath()
                        end
                    end,
                },
            },
            {
                {
                    text = _("Cut"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        cutFile(file)
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Delete"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        UIManager:show(ConfirmBox:new{
                            text = is_file and T(_("Delete file?\n\n%1\n\nIf you delete a file, it is permanently lost."), BD.filepath(file)) or
                                T(_("Delete folder?\n\n%1\n\nIf you delete a folder, its content is permanently lost."), BD.filepath(file)),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                deleteFile(file)
                                require("readhistory"):fileDeleted(file)
                                self:refreshPath()
                            end,
                        })
                    end,
                },
                {
                    text = _("Rename"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager.rename_dialog = InputDialog:new{
                            title = is_file and _("Rename file") or _("Rename folder"),
                            input = BaseUtil.basename(file),
                            buttons = {{
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    enabled = true,
                                    callback = function()
                                        UIManager:close(file_manager.rename_dialog)
                                    end,
                                },
                                {
                                    text = _("Rename"),
                                    enabled = true,
                                    callback = function()
                                        if file_manager.rename_dialog:getInputText() ~= "" then
                                            renameFile(file)
                                            UIManager:close(file_manager.rename_dialog)
                                        end
                                    end,
                                },
                            }},
                        }
                        UIManager:show(file_manager.rename_dialog)
                        file_manager.rename_dialog:onShowKeyboard()
                    end,
                }
            },
            -- a little hack to get visual functionality grouping
            {
            },
        }

        if is_file and Device:canExecuteScript(file) then
            -- NOTE: We populate the empty separator, in order not to mess with the button reordering code in CoverMenu
            table.insert(buttons[3],
                {
                    -- @translators This is the script's programming language (e.g., shell or python)
                    text = T(_("Execute %1 script"), util.getScriptType(file)),
                    enabled = true,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        local script_is_running_msg = InfoMessage:new{
                                -- @translators %1 is the script's programming language (e.g., shell or python), %2 is the filename
                                text = T(_("Running %1 script %2…"), util.getScriptType(file), BD.filename(BaseUtil.basename(file))),
                        }
                        UIManager:show(script_is_running_msg)
                        UIManager:scheduleIn(0.5, function()
                            local rv
                            if Device:isAndroid() then
                                Device:setIgnoreInput(true)
                                rv = os.execute("sh " .. BaseUtil.realpath(file)) -- run by sh, because sdcard has no execute permissions
                                Device:setIgnoreInput(false)
                            else
                                rv = os.execute(BaseUtil.realpath(file))
                            end
                            UIManager:close(script_is_running_msg)
                            if rv == 0 then
                                UIManager:show(InfoMessage:new{
                                    text = _("The script exited successfully."),
                                })
                            else
                                --- @note: Lua 5.1 returns the raw return value from the os's system call. Counteract this madness.
                                UIManager:show(InfoMessage:new{
                                    text = T(_("The script returned a non-zero status code: %1!"), bit.rshift(rv, 8)),
                                    icon = "notice-warning",
                                })
                            end
                        end)
                    end,
                }
            )
        end

        if is_file then
            table.insert(buttons, {
                {
                    text = _("Reset settings"),
                    id = "reset_settings", -- used by covermenu
                    enabled = is_file and DocSettings:hasSidecarFile(BaseUtil.realpath(file)),
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Reset settings for this document?\n\n%1\n\nAny highlights or bookmarks will be permanently lost."), BD.filepath(file)),
                            ok_text = _("Reset"),
                            ok_callback = function()
                                filemanagerutil.purgeSettings(file)
                                require("readhistory"):fileSettingsPurged(file)
                                self:refreshPath()
                                UIManager:close(self.file_dialog)
                            end,
                        })
                    end,
                },
                {
                    text_func = function()
                        if ReadCollection:checkItemExist(file) then
                            return _("Remove from favorites")
                        else
                            return _("Add to favorites")
                        end
                    end,
                    enabled = DocumentRegistry:getProviders(file) ~= nil,
                    callback = function()
                        if ReadCollection:checkItemExist(file) then
                            ReadCollection:removeItem(file)
                        else
                            ReadCollection:addItem(file)
                        end
                        UIManager:close(self.file_dialog)
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Open with…"),
                    enabled = DocumentRegistry:getProviders(file) == nil or #(DocumentRegistry:getProviders(file)) > 1 or file_manager.texteditor,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        local one_time_providers = {}
                        table.insert(one_time_providers, {
                            provider_name = _("Text viewer"),
                            callback = function()
                                file_manager:openTextViewer(file)
                            end,
                        })
                        if file_manager.texteditor then
                            table.insert(one_time_providers, {
                                provider_name = _("Text editor"),
                                callback = function()
                                    file_manager.texteditor:checkEditFile(file)
                                end,
                            })
                        end
                        self:showSetProviderButtons(file, one_time_providers)
                    end,
                },
                {
                    text = _("Book information"),
                    id = "book_information", -- used by covermenu
                    enabled = FileManagerBookInfo:isSupported(file),
                    callback = function()
                        FileManagerBookInfo:show(file)
                        UIManager:close(self.file_dialog)
                    end,
                }
            })
            if FileManagerConverter:isSupported(file) then
                table.insert(buttons, {
                    {
                        text = _("Convert"),
                        enabled = true,
                        callback = function()
                            UIManager:close(self.file_dialog)
                            FileManagerConverter:showConvertButtons(file, self)
                        end,
                    }
                })
            end
        end
        if is_folder then
            local realpath = BaseUtil.realpath(file)
            table.insert(buttons, {
                {
                    text = _("Set as HOME folder"),
                    callback = function()
                        setHome(realpath)
                        UIManager:close(self.file_dialog)
                    end
                }
            })
        end

        local title
        if is_folder then
            title = BD.directory(file:match("([^/]+)$"))
        else
            title = BD.filename(file:match("([^/]+)$"))
        end

        self.file_dialog = ButtonDialogTitle:new{
            title = title,
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.file_dialog)
        return true
    end

    self.layout = VerticalGroup:new{
        self.title_bar,
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

    self:registerKeyEvents()
end

function FileManager:registerKeyEvents()
    -- NOTE: We need to be surgical here, because this is called through reinit at runtime.
    if Device:hasKeys() then
        self.key_events.Home = { { "Home" } }
        -- Override the menu.lua way of handling the back key
        self.file_chooser.key_events.Back = { { Device.input.group.Back } }
        if not Device:hasFewKeys() then
            -- Also remove the handler assigned to the "Back" key by menu.lua
            self.file_chooser.key_events.Close = nil
        end
    else
        self.key_events.Home = nil
        self.file_chooser.key_events.Back = nil
        self.file_chooser.key_events.Close = nil
    end
end

function FileManager:registerModule(name, ui_module, always_active)
    if name then
        self[name] = ui_module
        ui_module.name = "filemanager" .. name
    end
    table.insert(self, ui_module)
    if always_active then
        -- to get events even when hidden
        table.insert(self.active_widgets, ui_module)
    end
end

-- NOTE: The only thing that will *ever* instantiate a new FileManager object is our very own showFiles below!
function FileManager:init()
    self:setupLayout()
    self.active_widgets = {}

    self:registerModule("screenshot", Screenshoter:new{
        prefix = 'FileManager',
        ui = self,
    }, true)

    self:registerModule("menu", self.menu)
    self:registerModule("history", FileManagerHistory:new{ ui = self })
    self:registerModule("collections", FileManagerCollection:new{ ui = self })
    self:registerModule("filesearcher", FileManagerFileSearcher:new{ ui = self })
    self:registerModule("folder_shortcuts", FileManagerShortcuts:new{ ui = self })
    self:registerModule("languagesupport", LanguageSupport:new{ ui = self })
    self:registerModule("dictionary", ReaderDictionary:new{ ui = self })
    self:registerModule("wikipedia", ReaderWikipedia:new{ ui = self })
    self:registerModule("devicestatus", ReaderDeviceStatus:new{ ui = self })
    self:registerModule("devicelistener", DeviceListener:new{ ui = self })

    -- koreader plugins
    for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
        if not plugin_module.is_doc_only then
            local ok, plugin_or_err = PluginLoader:createPluginInstance(
                plugin_module, { ui = self, })
            -- Keep references to the modules which do not register into menu.
            if ok then
                self:registerModule(plugin_module.name, plugin_or_err)
                logger.dbg("FM loaded plugin", plugin_module.name,
                            "at", plugin_module.path)
            end
        end
    end

    if Device:hasWifiToggle() then
        local NetworkListener = require("ui/network/networklistener")
        table.insert(self, NetworkListener:new{ ui = self })
    end

    self:initGesListener()
    self:handleEvent(Event:new("SetDimensions", self.dimen))

    -- NOTE: ReaderUI has a _getRunningInstance method for this, because it used to store the instance reference in a private module variable.
    if FileManager.instance == nil then
        logger.dbg("Spinning up new FileManager instance", tostring(self))
    else
        -- Should never happen, given what we did in showFiles...
        logger.err("FileManager instance mismatch! Opened", tostring(self), "while we still have an existing instance:", tostring(FileManager.instance), debug.traceback())
    end
    FileManager.instance = self
end

function FileChooser:onBack()
    local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
    local back_in_filemanager = G_reader_settings:readSetting("back_in_filemanager", "default")
    if back_in_filemanager == "default" then
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
    elseif back_in_filemanager == "parent_folder" then
        self:changeToPath(string.format("%s/..", self.path))
        return true
    end
end

function FileManager:onSwipeFM(ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        self.file_chooser:onNextPage()
    elseif direction == "east" then
        self.file_chooser:onPrevPage()
    end
    return true
end

function FileManager:onShowPlusMenu()
    self:tapPlus()
    return true
end

function FileManager:onToggleSelectMode(no_refresh)
    logger.dbg("toggle select mode")
    self.select_mode = not self.select_mode
    self.selected_files = self.select_mode and {} or nil
    self.title_bar:setRightIcon(self.select_mode and "check" or "plus")
    if not no_refresh then
        self:onRefresh()
    end
end

function FileManager:tapPlus()
    local title, buttons
    if self.select_mode then
        local select_count = util.tableSize(self.selected_files)
        local actions_enabled = select_count > 0
        title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
            or _("No files selected")
        buttons = {
            {
                {
                    text = _("Select all files in folder"),
                    callback = function()
                        self.file_chooser:selectAllFilesInFolder()
                        self:onRefresh()
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Copy"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Copy selected files to the current folder?"),
                            ok_text = _("Copy"),
                            ok_callback = function()
                                self.cutfile = false
                                for file in pairs(self.selected_files) do
                                    self.clipboard = file
                                    self:pasteHere(self.file_chooser.path)
                                end
                                self:onToggleSelectMode()
                                UIManager:close(self.file_dialog)
                            end,
                        })
                    end
                },
            },
            {
                {
                    text = _("Deselect all"),
                    enabled = actions_enabled,
                    callback = function()
                        self.selected_files = {}
                        self:onRefresh()
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Move"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Move selected files to the current folder?"),
                            ok_text = _("Move"),
                            ok_callback = function()
                                self.cutfile = true
                                for file in pairs(self.selected_files) do
                                    self.clipboard = file
                                    self:pasteHere(self.file_chooser.path)
                                end
                                self:onToggleSelectMode()
                                UIManager:close(self.file_dialog)
                            end,
                        })
                    end
                },
            },
            {
                {
                    text = _("Exit select mode"),
                    callback = function()
                        self:onToggleSelectMode()
                        UIManager:close(self.file_dialog)
                    end,
                },
                {
                    text = _("Delete"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete selected files?\nIf you delete a file, it is permanently lost."),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                local readhistory = require("readhistory")
                                for file in pairs(self.selected_files) do
                                    self:deleteFile(file)
                                    readhistory:fileDeleted(file)
                                end
                                self:onToggleSelectMode()
                                UIManager:close(self.file_dialog)
                            end,
                        })
                    end
                },
            },
            {},
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:createFolder()
                    end,
                },
                {
                    text = _("Folder shortcuts"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:handleEvent(Event:new("ShowFolderShortcutsDialog"))
                    end
                },
            },
        }
    else
        title = BD.dirpath(filemanagerutil.abbreviate(self.file_chooser.path))
        buttons = {
            {
                {
                    text = _("Select files"),
                    callback = function()
                        self:onToggleSelectMode(true) -- no full screen refresh
                        UIManager:close(self.file_dialog)
                    end,
                },
            },
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:createFolder()
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
                    text = _("Set as HOME folder"),
                    callback = function()
                        self:setHome(self.file_chooser.path)
                        UIManager:close(self.file_dialog)
                    end
                }
            },
            {
                {
                    text = _("Go to HOME folder"),
                    callback = function()
                        self:goHome()
                        UIManager:close(self.file_dialog)
                    end
                }
            },
            {
                {
                    text = _("Open random document"),
                    callback = function()
                        self:openRandomFile(self.file_chooser.path)
                        UIManager:close(self.file_dialog)
                    end
                }
            },
            {
                {
                    text = _("Folder shortcuts"),
                    callback = function()
                        self:handleEvent(Event:new("ShowFolderShortcutsDialog"))
                        UIManager:close(self.file_dialog)
                    end
                }
            }
        }

        if Device:canImportFiles() then
            table.insert(buttons, 4, {
                {
                    text = _("Import files here"),
                    enabled = Device:isValidPath(self.file_chooser.path),
                    callback = function()
                        local current_dir = self.file_chooser.path
                        UIManager:close(self.file_dialog)
                        Device.importFile(current_dir)
                    end,
                },
            })
        end

        if Device:hasExternalSD() then
            table.insert(buttons, 5, {
                {
                    text_func = function()
                        if Device:isValidPath(self.file_chooser.path) then
                            return _("Switch to SDCard")
                        else
                            return _("Switch to internal storage")
                        end
                    end,
                    callback = function()
                        if Device:isValidPath(self.file_chooser.path) then
                            local ok, sd_path = Device:hasExternalSD()
                            UIManager:close(self.file_dialog)
                            if ok then
                                self.file_chooser:changeToPath(sd_path)
                            end
                        else
                            UIManager:close(self.file_dialog)
                            self.file_chooser:changeToPath(Device.home_dir)
                        end
                    end,
                },
            })
        end
    end

    self.file_dialog = ButtonDialogTitle:new{
        title = title,
        title_align = "center",
        buttons = buttons,
        select_mode = self.select_mode, -- for coverbrowser
    }
    UIManager:show(self.file_dialog)
end

function FileManager:reinit(path, focused_file)
    UIManager:flushSettings()
    self.dimen = Screen:getSize()
    -- backup the root path and path items
    self.root_path = path or self.file_chooser.path
    local path_items_backup = {}
    for k, v in pairs(self.file_chooser.path_items) do
        path_items_backup[k] = v
    end
    -- reinit filemanager
    self.focused_file = focused_file
    self:setupLayout()
    self:handleEvent(Event:new("SetDimensions", self.dimen))
    self.file_chooser.path_items = path_items_backup
    -- self:init() has already done file_chooser:refreshPath()
    -- (by virtue of rebuilding file_chooser), so this one
    -- looks unnecessary (cheap with classic mode, less cheap with
    -- CoverBrowser plugin's cover image renderings)
    -- self:onRefresh()
    if self.select_mode then
        self.title_bar:setRightIcon("check")
    end
end

function FileManager:getCurrentDir()
    if FileManager.instance then
        return FileManager.instance.file_chooser.path
    end
end

function FileManager:toggleHiddenFiles()
    self.file_chooser:toggleHiddenFiles()
    G_reader_settings:saveSetting("show_hidden", self.file_chooser.show_hidden)
end

function FileManager:toggleUnsupportedFiles()
    self.file_chooser:toggleUnsupportedFiles()
    G_reader_settings:saveSetting("show_unsupported", self.file_chooser.show_unsupported)
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
    PluginLoader:finalize()
    self:handleEvent(Event:new("SaveSettings"))
    G_reader_settings:flush()
    UIManager:close(self)
    return true
end

function FileManager:onCloseWidget()
    if FileManager.instance == self then
        logger.dbg("Tearing down FileManager", tostring(self))
    else
        logger.warn("FileManager instance mismatch! Closed", tostring(self), "while the active one is supposed to be", tostring(FileManager.instance))
    end
    FileManager.instance = nil
end

function FileManager:onShowingReader()
    -- Allows us to optimize out a few useless refreshes in various CloseWidgets handlers...
    self.tearing_down = true
    -- Clear the dither flag to prevent it from infecting the queue and re-inserting a full-screen refresh...
    self.dithered = nil

    self:onClose()
end

-- Same as above, except we don't close it yet. Useful for plugins that need to close custom Menus before calling showReader.
function FileManager:onSetupShowReader()
    self.tearing_down = true
    self.dithered = nil
end

function FileManager:onRefresh()
    self.file_chooser:refreshPath()
    return true
end

function FileManager:goHome()
    if not self.file_chooser:goHome() then
        self:setHome()
    end
    return true
end

function FileManager:setHome(path)
    path = path or self.file_chooser.path
    UIManager:show(ConfirmBox:new{
        text = T(_("Set '%1' as HOME folder?"), BD.dirpath(path)),
        ok_text = _("Set as HOME"),
        ok_callback = function()
            G_reader_settings:saveSetting("home_dir", path)
        end,
    })
    return true
end

function FileManager:openRandomFile(dir)
    local random_file = DocumentRegistry:getRandomFile(dir, false)
    if random_file then
        UIManager:show(MultiConfirmBox:new {
            text = T(_("Do you want to open %1?"), BD.filename(BaseUtil.basename(random_file))),
            choice1_text = _("Open"),
            choice1_callback = function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(random_file)
            end,
            -- @translators Another file. This is a button on the open random file dialog. It presents a file with the choices Open/Another.
            choice2_text = _("Another"),
            choice2_callback = function()
                self:openRandomFile(dir)
            end,
        })
        UIManager:close(self.file_dialog)
    else
        UIManager:show(InfoMessage:new {
            text = _("File not found"),
        })
    end
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
        file = BaseUtil.realpath(file)
        local orig_basename = BaseUtil.basename(self.clipboard)
        local orig = BaseUtil.realpath(self.clipboard)
        local dest = lfs.attributes(file, "mode") == "directory" and
            file or file:match("(.*/)")

        local function infoCopyFile()
            -- if we copy a file, also copy its sidecar directory
            if DocSettings:hasSidecarFile(orig) then
                BaseUtil.execute(self.cp_bin, "-r", DocSettings:getSidecarDir(orig), dest)
            end
            if BaseUtil.execute(self.cp_bin, "-r", orig, dest) ~= 0 then
                UIManager:show(InfoMessage:new {
                    text = T(_("Failed to copy:\n%1\nto:\n%2"), BD.filepath(orig_basename), BD.dirpath(dest)),
                    icon = "notice-warning",
                })
            end
        end

        local function infoMoveFile()
            -- if we move a file, also move its sidecar directory
            if DocSettings:hasSidecarFile(orig) then
                self:moveFile(DocSettings:getSidecarDir(orig), dest) -- dest is always a directory
            end
            if self:moveFile(orig, dest) then
                -- Update history and collections.
                local dest_file = string.format("%s/%s", dest, BaseUtil.basename(orig))
                require("readhistory"):updateItemByPath(orig, dest_file) -- (will update "lastfile" if needed)
                ReadCollection:updateItemByPath(orig, dest_file)
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("Failed to move:\n%1\nto:\n%2"), BD.filepath(orig_basename), BD.dirpath(dest)),
                    icon = "notice-warning",
                })
            end
        end

        local info_file
        if self.cutfile then
            info_file = infoMoveFile
        else
            info_file = infoCopyFile
        end
        local basename = BaseUtil.basename(self.clipboard)
        local mode = lfs.attributes(string.format("%s/%s", dest, basename), "mode")
        if mode == "file" or mode == "directory" then
            local text
            if mode == "file" then
                text = T(_("File already exists:\n%1\nOverwrite file?"), BD.filename(basename))
            else
                text = T(_("Folder already exists:\n%1\nOverwrite folder?"), BD.directory(basename))
            end

            UIManager:show(ConfirmBox:new {
                text = text,
                ok_text = _("Overwrite"),
                ok_callback = function()
                    info_file()
                    self:onRefresh()
                    self.clipboard = nil
                end,
            })
        else
            info_file()
            self:onRefresh()
            self.clipboard = nil
        end
    end
end

function FileManager:createFolder()
    local input_dialog, check_button_enter_folder
    input_dialog = InputDialog:new{
        title = _("New folder"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local new_folder_name = input_dialog:getInputText()
                        if new_folder_name == "" then return end
                        UIManager:close(input_dialog)
                        local new_folder = string.format("%s/%s", self.file_chooser.path, new_folder_name)
                        if BaseUtil.execute(self.mkdir_bin, new_folder) == 0 then
                            if check_button_enter_folder.checked then
                                self.file_chooser:changeToPath(new_folder)
                            else
                                self.file_chooser:refreshPath()
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = T(_("Failed to create folder:\n%1"), BD.directory(new_folder_name)),
                                icon = "notice-warning",
                            })
                        end
                    end,
                },
            }
        },
    }
    check_button_enter_folder = CheckButton:new{
        text = _("Enter folder after creation"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_enter_folder)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManager:deleteFile(file)
    local ok, err, is_dir
    local file_abs_path = BaseUtil.realpath(file)
    if file_abs_path == nil then
        UIManager:show(InfoMessage:new{
            text = T(_("File not found:\n%1"), BD.filepath(file)),
            icon = "notice-warning",
        })
        return
    end

    local is_doc = DocumentRegistry:hasProvider(file_abs_path)
    if lfs.attributes(file_abs_path, "mode") == "file" then
        ok, err = os.remove(file_abs_path)
    else
        ok, err = BaseUtil.purgeDir(file_abs_path)
        is_dir = true
    end
    if ok and not err then
        if is_doc then
            local doc_settings = DocSettings:open(file)
            -- remove cache if any
            local cache_file_path = doc_settings:readSetting("cache_file_path")
            if cache_file_path then
                os.remove(cache_file_path)
            end
            doc_settings:purge()
        end
        ReadCollection:removeItemByPath(file, is_dir)
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Failed to delete:\n%1"), BD.filepath(file)),
            icon = "notice-warning",
        })
    end
end

function FileManager:renameFile(file)
    local basename = self.rename_dialog:getInputText()
    if BaseUtil.basename(file) ~= basename then
        local dest = BaseUtil.joinPath(BaseUtil.dirname(file), basename)
        local function doRenameFile()
            if self:moveFile(file, dest) then
                require("readhistory"):updateItemByPath(file, dest) -- (will update "lastfile" if needed)
                ReadCollection:updateItemByPath(file, dest)
                if lfs.attributes(dest, "mode") == "file" then
                    local doc = require("docsettings")
                    local move_history = true
                    if lfs.attributes(doc:getHistoryPath(file), "mode") == "file" and
                       not self:moveFile(doc:getHistoryPath(file), doc:getHistoryPath(dest)) then
                       move_history = false
                    end
                    if lfs.attributes(doc:getSidecarDir(file), "mode") == "directory" and
                       not self:moveFile(doc:getSidecarDir(file), doc:getSidecarDir(dest)) then
                       move_history = false
                    end
                    if not move_history then
                        UIManager:show(InfoMessage:new{
                            text = T(_("Renamed file:\n%1\nto:\n%2\n\nFailed to move history data.\nThe reading history may be lost."),
                                BD.filepath(file), BD.filepath(dest)),
                            icon = "notice-warning",
                        })
                    end
                end
            else
                UIManager:show(InfoMessage:new{
                    text = T(_("Failed to rename:\n%1\nto:\n%2"), BD.filepath(file), BD.filepath(dest)),
                    icon = "notice-warning",
                })
            end
        end

        local mode_dest = lfs.attributes(dest, "mode")
        local mode_file = lfs.attributes(file, "mode")
        if mode_dest then
            local text, ok_text
            if mode_dest ~= mode_file then
                if mode_file == "file" then
                    text = T(_("Folder already exists:\n%1\nFile cannot be renamed."), BD.directory(basename))
                else
                    text = T(_("File already exists:\n%1\nFolder cannot be renamed."), BD.filename(basename))
                end
                UIManager:show(InfoMessage:new {
                    text = text,
                    icon = "notice-warning",
                })
            else
                if mode_file == "file" then
                    text = T(_("File already exists:\n%1\nOverwrite file?"), BD.filename(basename))
                    ok_text = _("Overwrite")
                else
                    text = T(_("Folder already exists:\n%1\nMove the folder inside it?"), BD.directory(basename))
                    ok_text = _("Move")
                end
                UIManager:show(ConfirmBox:new {
                    text = text,
                    ok_text = ok_text,
                    ok_callback = function()
                        doRenameFile()
                        self:onRefresh()
                    end,
                })
            end
        else
            doRenameFile()
            self:onRefresh()
        end
    end
end

function FileManager:getSortingMenuTable()
    local fm = self
    local collates = {
        strcoll = {_("filename"), _("Sort by filename")},
        natural = {_("natural"), _("Sort by filename (natural sorting)")},
        strcoll_mixed = {_("name mixed"), _("Sort by name – mixed files and folders")},
        access = {_("date read"), _("Sort by last read date")},
        change = {_("date added"), _("Sort by date added")},
        modification = {_("date modified"), _("Sort by date modified")},
        size = {_("size"), _("Sort by size")},
        type = {_("type"), _("Sort by type")},
        percent_unopened_first = {_("percent – unopened first"), _("Sort by percent – unopened first")},
        percent_unopened_last = {_("percent – unopened last"), _("Sort by percent – unopened last")},
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
    local get_collate_percent = function()
        local collate_type = G_reader_settings:readSetting("collate")
        if collate_type == "percent_unopened_first" or collate_type == "percent_unopened_last" then
            return collates[collate_type][2]
        else
            return _("Sort by percent")
        end
    end
    return {
        text_func = function()
            return T(
                _("Sort by: %1"),
                collates[fm.file_chooser.collate][1]
            )
        end,
        sub_item_table = {
            set_collate_table("strcoll"),
            set_collate_table("natural"),
            set_collate_table("strcoll_mixed"),
            set_collate_table("access"),
            set_collate_table("change"),
            set_collate_table("modification"),
            set_collate_table("size"),
            set_collate_table("type"),
            {
                text_func =  get_collate_percent,
                checked_func = function()
                    return fm.file_chooser.collate == "percent_unopened_first"
                        or fm.file_chooser.collate == "percent_unopened_last"
                end,
                sub_item_table = {
                    set_collate_table("percent_unopened_first"),
                    set_collate_table("percent_unopened_last"),
                }
            },
        }
    }
end

function FileManager:getStartWithMenuTable()
    local start_with_setting = G_reader_settings:readSetting("start_with") or "filemanager"
    local start_withs = {
        filemanager = {_("file browser"), _("Start with file browser")},
        history = {_("history"), _("Start with history")},
        favorites = {_("favorites"), _("Start with favorites")},
        folder_shortcuts = {_("folder shortcuts"), _("Start with folder shortcuts")},
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
            return T(
                _("Start with: %1"),
                start_withs[start_with_setting][1]
            )
        end,
        sub_item_table = {
            set_sw_table("filemanager"),
            set_sw_table("history"),
            set_sw_table("favorites"),
            set_sw_table("folder_shortcuts"),
            set_sw_table("last"),
        }
    }
end

--- @note: This is the *only* safe way to instantiate a new FileManager instance!
function FileManager:showFiles(path, focused_file)
    -- Warn about and close any pre-existing FM instances first...
    if FileManager.instance then
        logger.warn("FileManager instance mismatch! Tried to spin up a new instance, while we still have an existing one:", tostring(FileManager.instance))
        -- Close the old one first!
        FileManager.instance:onClose()
    end

    path = path or G_reader_settings:readSetting("lastdir") or filemanagerutil.getDefaultDir()
    G_reader_settings:saveSetting("lastdir", path)
    self:setRotationMode()
    local file_manager = FileManager:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        root_path = path,
        focused_file = focused_file,
    }
    UIManager:show(file_manager)
end

function FileManager:openTextViewer(file_path)
    local function _openTextViewer(filepath)
        local file = io.open(filepath, "rb")
        if not file then return end
        local file_content = file:read("*all")
        file:close()
        UIManager:show(require("ui/widget/textviewer"):new{
            title = filepath,
            title_multilines = true,
            justified = false,
            text = file_content,
        })
    end
    local attr = lfs.attributes(file_path)
    if attr then
        if attr.size > 400000 then
            UIManager:show(ConfirmBox:new{
                text = T(_("This file is %2:\n\n%1\n\nAre you sure you want to open it?\n\nOpening big files may take some time."),
                    BD.filepath(file_path), util.getFriendlySize(attr.size)),
                ok_text = _("Open"),
                ok_callback = function()
                    _openTextViewer(file_path)
                end,
            })
        else
            _openTextViewer(file_path)
        end
    end
end

--- A shortcut to execute mv.
-- @treturn boolean result of mv command
function FileManager:moveFile(from, to)
    return BaseUtil.execute(self.mv_bin, from, to) == 0
end

--- A shortcut to execute cp.
-- @treturn boolean result of cp command
function FileManager:copyFileFromTo(from, to)
    return BaseUtil.execute(self.cp_bin, from, to) == 0
end

--- A shortcut to execute cp recursively.
-- @treturn boolean result of cp command
function FileManager:copyRecursive(from, to)
    return BaseUtil.execute(self.cp_bin, "-r", from, to ) == 0
end

function FileManager:onHome()
    return self:goHome()
end

function FileManager:onRefreshContent()
    self:onRefresh()
end

return FileManager
