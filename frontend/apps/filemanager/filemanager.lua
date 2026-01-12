local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
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
local NetworkListener = require("ui/network/networklistener")
local PluginLoader = require("pluginloader")
local ReadCollection = require("readcollection")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReadHistory = require("readhistory")
local Screenshoter = require("ui/widget/screenshoter")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local Screen = Device.screen
local T = ffiUtil.template

local FileManager = InputContainer:extend{
    title = _("KOReader"),
    active_widgets = nil, -- array
    root_path = lfs.currentdir(),

    clipboard = nil, -- for single file operations
    selected_files = nil, -- for group file operations

    mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv",
    cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp",
}

local function isFile(file)
    return lfs.attributes(file, "mode") == "file"
end

function FileManager:setRotationMode()
    local locked = G_reader_settings:isTrue("lock_rotation")
    if not locked then
        local mode = G_reader_settings:readSetting("fm_rotation_mode") or Screen.DEVICE_ROTATED_UPRIGHT
        self:onSetRotationMode(mode)
    end
end

function FileManager:onSetRotationMode(mode)
    local old_mode = Screen:getRotationMode()
    if mode ~= nil and mode ~= old_mode then
        Screen:setRotationMode(mode)
        if FileManager.instance then
            self:rotate()
        end
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

function FileManager:updateTitleBarPath(path)
    local text = BD.directory(filemanagerutil.abbreviate(path))
    if self.folder_shortcuts:hasFolderShortcut(path) then
        text = "☆ " .. text
    end
    self.title_bar:setSubTitle(text)
end

FileManager.onPathChanged = FileManager.updateTitleBarPath

function FileManager:setupLayout()
    self.show_parent = self.show_parent or self
    self.title_bar = TitleBar:new{
        show_parent = self.show_parent,
        fullscreen = "true",
        align = "center",
        title = self.title,
        title_top_padding = Screen:scaleBySize(6),
        subtitle = "",
        subtitle_truncate_left = true,
        subtitle_fullwidth = true,
        button_padding = Screen:scaleBySize(5),
        left_icon = "home",
        left_icon_size_ratio = 1,
        left_icon_tap_callback = function() self:onHome() end,
        left_icon_hold_callback = function() self:onShowFolderMenu() end,
        right_icon = self.selected_files and "check" or "plus",
        right_icon_size_ratio = 1,
        right_icon_tap_callback = function() self:onShowPlusMenu() end,
        right_icon_hold_callback = false, -- propagate long-press to dispatcher
    }

    local file_chooser = FileChooser:new{
        name = "filemanager",
        path = self.root_path,
        focused_path = self.focused_file,
        show_parent = self.show_parent,
        file_filter = function(filename) return DocumentRegistry:hasProvider(filename) end,
        close_callback = function() return self:onClose() end,
        -- allow left bottom tap gesture, otherwise it is eaten by hidden return button
        return_arrow_propagation = true,
        -- allow Menu widget to delegate handling of some gestures to GestureManager
        ui = self,
        -- Tell FileChooser (i.e., Menu) to use our own title bar instead of Menu's default one
        custom_title_bar = self.title_bar,
        search_callback = function(search_string)
            self.filesearcher:onShowFileSearch(search_string)
        end,
    }
    self.file_chooser = file_chooser
    self.focused_file = nil -- use it only once

    local file_manager = self

    function file_chooser:onFileSelect(item)
        if file_manager.selected_files then -- toggle selection
            item.dim = not item.dim and true or nil
            file_manager.selected_files[item.path] = item.dim
            self:updateItems(1, true)
        else
            file_manager:openFile(item.path)
        end
        return true
    end

    function file_chooser:onFileHold(item)
        if file_manager.selected_files then
            file_manager:onShowPlusMenu()
        else
            self:showFileDialog(item)
        end
    end

    function file_chooser:showFileDialog(item)
        local file = item.path
        local is_file = item.is_file
        local is_not_parent_folder = not item.is_go_up

        local function close_dialog_callback()
            UIManager:close(self.file_dialog)
        end
        local function refresh_callback()
            self:refreshPath()
        end
        local function close_dialog_refresh_callback()
            UIManager:close(self.file_dialog)
            self:refreshPath()
        end

        local buttons = {
            {
                {
                    text = C_("File", "Paste"),
                    enabled = file_manager.clipboard and true or false,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:pasteFileFromClipboard(file)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:onToggleSelectMode()
                        if is_file then
                            file_manager.selected_files[file] = true
                            item.dim = true
                            self:updateItems(1, true)
                        end
                    end,
                },
                {
                    text = _("Rename"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showRenameFileDialog(file, is_file)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showDeleteFileDialog(file, refresh_callback)
                    end,
                },
                {
                    text = _("Cut"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:cutFile(file)
                    end,
                },
                {
                    text = C_("File", "Copy"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:copyFile(file)
                    end,
                },
            },
            {}, -- separator
        }

        local book_props
        if is_file then
            local has_provider = DocumentRegistry:hasProvider(file)
            local been_opened = BookList.hasBookBeenOpened(file)
            local doc_settings_or_file = file
            if has_provider or been_opened then
                book_props = file_manager.coverbrowser and file_manager.coverbrowser:getBookInfo(file)
                if been_opened then
                    doc_settings_or_file = BookList.getDocSettings(file)
                    if not book_props then
                        local props = doc_settings_or_file:readSetting("doc_props")
                        book_props = FileManagerBookInfo.extendProps(props, file)
                        book_props.has_cover = true -- to enable "Book cover" button, we do not know if cover exists
                    end
                end
                table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_refresh_callback))
                table.insert(buttons, {}) -- separator
                table.insert(buttons, {
                    filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_refresh_callback),
                    file_manager.collections:genAddToCollectionButton(file, close_dialog_callback, refresh_callback),
                })
            end
            if Device:canExecuteScript(file) then
                table.insert(buttons, {
                    filemanagerutil.genExecuteScriptButton(file, close_dialog_callback),
                })
            end
            if FileManagerConverter:isSupported(file) then
                table.insert(buttons, {
                    FileManagerConverter:genConvertButton(file, close_dialog_callback, refresh_callback)
                })
            end
            table.insert(buttons, {
                {
                    text = _("Open with…"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showOpenWithDialog(file)
                    end,
                },
                filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
            })
            if has_provider then
                table.insert(buttons, {
                    filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
                    filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
                })
            end
        else -- folder
            local folder = ffiUtil.realpath(file)
            table.insert(buttons, {
                {
                    text = _("Set as HOME folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:setHome(folder)
                    end
                },
            })
            table.insert(buttons, {
                file_manager.folder_shortcuts:genAddRemoveShortcutButton(folder, close_dialog_callback, refresh_callback)
            })
        end

        if file_manager.file_dialog_added_buttons ~= nil then
            for _, row_func in ipairs(file_manager.file_dialog_added_buttons) do
                local row = row_func(file, is_file, book_props)
                if row ~= nil then
                    table.insert(buttons, row)
                end
            end
        end

        self.file_dialog = ButtonDialog:new{
            title = is_file and BD.filename(file:match("([^/]+)$")) or BD.directory(file:match("([^/]+)$")),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.file_dialog)
        return true
    end

    local fm_ui = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        file_chooser,
    }

    self[1] = fm_ui

    -- No need to reinvent the wheel, use FileChooser's layout
    self.layout = file_chooser.layout

    self:registerKeyEvents()
end

function FileManager:registerKeyEvents()
    -- NOTE: We need to be surgical here, because this is called through reinit at runtime.
    if Device:hasKeys() then
        self.key_events.Home = { { "Home" } }
        -- Override the menu.lua way of handling the back key
        self.file_chooser.key_events.Back = { { Device.input.group.Back } }
        if Device:hasScreenKB() then
            self.key_events.ToggleWifi = { { "ScreenKB", "Home" } }
        elseif Device:hasKeyboard() then
            self.key_events.ToggleWifi = { { "Shift", "Home" } }
        end
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
    self.active_widgets = {}

    self:registerModule("screenshot", Screenshoter:new{
        prefix = "FileManager",
        ui = self,
    }, true)
    self:registerModule("menu", FileManagerMenu:new{ ui = self })
    self:registerModule("history", FileManagerHistory:new{ ui = self })
    self:registerModule("bookinfo", FileManagerBookInfo:new{ ui = self })
    self:registerModule("collections", FileManagerCollection:new{ ui = self })
    self:registerModule("filesearcher", FileManagerFileSearcher:new{ ui = self })
    self:registerModule("folder_shortcuts", FileManagerShortcuts:new{ ui = self })
    self:registerModule("languagesupport", LanguageSupport:new{ ui = self })
    self:registerModule("dictionary", ReaderDictionary:new{ ui = self })
    self:registerModule("wikipedia", ReaderWikipedia:new{ ui = self })
    self:registerModule("devicestatus", ReaderDeviceStatus:new{ ui = self })
    self:registerModule("devicelistener", DeviceListener:new{ ui = self })
    self:registerModule("networklistener", NetworkListener:new{ ui = self })

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

    self:setupLayout()
    self:initGesListener()
    self:handleEvent(Event:new("SetDimensions", self.dimen))
    self:handleEvent(Event:new("PathChanged", self.file_chooser.path))

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
                end,
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

function FileManager:addFileDialogButtons(row_id, row_func)
    -- long-press file_dialog in FileManager, History, Collections, FileSearcher
    self.file_dialog_added_buttons = self.file_dialog_added_buttons or { index = {} }
    if self.file_dialog_added_buttons.index[row_id] == nil then
        table.insert(self.file_dialog_added_buttons, row_func)
        self.file_dialog_added_buttons.index[row_id] = #self.file_dialog_added_buttons
    end
end

function FileManager:removeFileDialogButtons(row_id)
    local index = self.file_dialog_added_buttons and self.file_dialog_added_buttons.index[row_id]
    if index ~= nil then
        table.remove(self.file_dialog_added_buttons, index)
        if #self.file_dialog_added_buttons == 0 then
            self.file_dialog_added_buttons = nil
        else
            self.file_dialog_added_buttons.index[row_id] = nil
            for id, idx in pairs(self.file_dialog_added_buttons.index) do
                if idx > index then
                    self.file_dialog_added_buttons.index[id] = idx - 1
                end
            end
        end
    end
end

function FileManager.getMenuInstance()
    return FileManager.instance.file_chooser
end

function FileManager:onToggleSelectMode(do_refresh)
    logger.dbg("toggle select mode")
    if self.selected_files then
        self.selected_files = nil
        self.title_bar:setRightIcon("plus")
        if do_refresh then
            self.file_chooser:refreshPath()
        else
            self.file_chooser:selectAllFilesInFolder(false) -- undim
        end
    else
        self.selected_files = {}
        self.title_bar:setRightIcon("check")
    end
    return true
end

function FileManager:getPlusDialogButtons()
    local function close_dialog_callback()
        UIManager:close(self.plus_dialog)
    end

    local title, buttons
    if self.selected_files then
        local function close_dialog_toggle_select_mode_callback()
            UIManager:close(self.plus_dialog)
            self:onToggleSelectMode(true)
        end
        local function toggle_select_mode_callback()
            self:onToggleSelectMode(true)
        end
        local select_count = util.tableSize(self.selected_files)
        local actions_enabled = select_count > 0
        title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
            or _("No files selected")
        buttons = {
            {
                {
                    text = _("Delete"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete selected files?\nIf you delete a file, it is permanently lost."),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(self.plus_dialog)
                                self:deleteSelectedFiles()
                            end,
                        })
                    end,
                },
                {
                    text = _("Move"),
                    enabled = actions_enabled,
                    callback = function()
                        self.cutfile = true
                        self:showCopyMoveSelectedFilesDialog(close_dialog_callback)
                    end,
                },
                {
                    text = _("Copy"),
                    enabled = actions_enabled,
                    callback = function()
                        self.cutfile = false
                        self:showCopyMoveSelectedFilesDialog(close_dialog_callback)
                    end,
                },
            },
            {}, -- separator
            filemanagerutil.genMultipleStatusButtonsRow(self.selected_files,
                close_dialog_toggle_select_mode_callback, not actions_enabled),
            {}, -- separator
            {
                filemanagerutil.genMultipleResetSettingsButton(self.selected_files,
                    close_dialog_toggle_select_mode_callback, not actions_enabled),
                self.collections:genAddToCollectionButton(self.selected_files,
                    close_dialog_callback, toggle_select_mode_callback, not actions_enabled),
            },
            {
                {
                    text = _("Export highlights"),
                    enabled = (actions_enabled and self.exporter) and true or false,
                    callback = function()
                        self.exporter:exportFilesNotes(self.selected_files)
                    end,
                },
            },
            {}, -- separator
            {
                {
                    text = _("Deselect all"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        for file in pairs (self.selected_files) do
                            self.selected_files[file] = nil
                        end
                        self.file_chooser:selectAllFilesInFolder(false) -- undim
                    end,
                },
                {
                    text = _("Select all files in folder"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self.file_chooser:selectAllFilesInFolder(true)
                    end,
                },
            },
            {
                {
                    text = _("Exit select mode"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:onToggleSelectMode()
                    end,
                },
                {
                    text = _("Show selected files list"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:showSelectedFilesList()
                    end,
                },
            },
            {}, -- separator
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:createFolder()
                    end,
                },
                self.folder_shortcuts:genShowFolderShortcutsButton(close_dialog_callback),
            },
        }

        local refresh_button = self.coverbrowser
            and self.coverbrowser:genMultipleRefreshBookInfoButton(close_dialog_toggle_select_mode_callback, not actions_enabled)
        if refresh_button ~= nil then
            table.insert(buttons, 7, refresh_button) -- before 'select mode' buttons
        end

    else -- no selected files
        local folder = self.file_chooser.path
        local function refresh_titlebar_callback()
            self:updateTitleBarPath(folder)
        end
        title = BD.dirpath(filemanagerutil.abbreviate(folder))
        buttons = {
            {
                {
                    text = _("Select files"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:onToggleSelectMode()
                    end,
                },
            },
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:createFolder()
                    end,
                },
            },
            {
                {
                    text = _("Paste"),
                    enabled = self.clipboard and true or false,
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:pasteFileFromClipboard()
                    end,
                },
            },
            {
                {
                    text = _("Set as HOME folder"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:setHome()
                    end
                },
            },
            {
                {
                    text = _("Go to HOME folder"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        self:onHome()
                    end
                },
            },
            {
                {
                    text = _("Open random document"),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        -- any random document
                        self:openRandomFile(folder, false)
                    end,
                    hold_callback = function()
                        UIManager:close(self.plus_dialog)
                        -- only previously unopened
                        self:openRandomFile(folder, true)
                    end
                },
            },
            {
                self.folder_shortcuts:genShowFolderShortcutsButton(close_dialog_callback),
            },
            {
                self.folder_shortcuts:genAddRemoveShortcutButton(folder, close_dialog_callback, refresh_titlebar_callback),
            },
        }

        if Device:hasExternalSD() then
            table.insert(buttons, 4, { -- after "Paste" or "Import files here" button
                {
                    text_func = function()
                        return Device:isValidPath(folder)
                            and _("Switch to SDCard") or _("Switch to internal storage")
                    end,
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        if Device:isValidPath(folder) then
                            local ok, sd_path = Device:hasExternalSD()
                            if ok then
                                self.file_chooser:changeToPath(sd_path)
                            end
                        else
                            self.file_chooser:changeToPath(Device.home_dir)
                        end
                    end,
                },
            })
        end

        if Device:canImportFiles() then
            table.insert(buttons, 4, { -- always after "Paste" button
                {
                    text = _("Import files here"),
                    enabled = Device:isValidPath(folder),
                    callback = function()
                        UIManager:close(self.plus_dialog)
                        Device.importFile(folder)
                    end,
                },
            })
        end

        local extract_button = self.coverbrowser and self.coverbrowser:genExtractBookInfoButton(close_dialog_callback)
        if extract_button ~= nil then
            table.insert(buttons, {}) -- separator
            table.insert(buttons, extract_button)
        end

    end

    return title, buttons
end

function FileManager:onShowPlusMenu()
    local title, buttons = self:getPlusDialogButtons()
    self.plus_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.plus_dialog)
    return true
end

function FileManager:reinit(path, focused_file)
    path = path or self.path
    focused_file = focused_file or self.focused_file
    UIManager:flushSettings()
    self.dimen = Screen:getSize()
    -- backup the root path and path items
    self.root_path = ffiUtil.realpath(path or self.file_chooser.path)
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
end

FileManager.rotate = FileManager.reinit

-- So that the key navigation shortcuts apply right away.
-- This will also naturally call registerKeyEvents
FileManager.onPhysicalKeyboardConnected = FileManager.reinit
FileManager.onPhysicalKeyboardDisconnected = FileManager.reinit

function FileManager:onClose()
    logger.dbg("close filemanager")
    PluginLoader:finalize()
    self:handleEvent(Event:new("SaveSettings"))
    G_reader_settings:flush()
    UIManager:close(self)
    return true
end

function FileManager:onFlushSettings()
    self:handleEvent(Event:new("SaveSettings"))
    G_reader_settings:flush()
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

FileManager.onRefreshContent = FileManager.onRefresh
FileManager.onBookMetadataChanged = FileManager.onRefresh

function FileManager:onHome()
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
            if G_reader_settings:isTrue("lock_home_folder") then
                self:onRefresh()
            end
        end,
    })
    return true
end

function FileManager:openRandomFile(dir, unopened_only)
    local match_func = function(file)
        if unopened_only then
            return DocumentRegistry:hasProvider(file) and not BookList.hasBookBeenOpened(file)
        else
            return DocumentRegistry:hasProvider(file)
        end
    end
    local random_file = filemanagerutil.getRandomFile(dir, match_func)
    if random_file then
        UIManager:show(MultiConfirmBox:new{
            text = T(_("Do you want to open %1?"), BD.filename(ffiUtil.basename(random_file))),
            choice1_text = _("Open"),
            choice1_callback = function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(random_file)
            end,
            -- @translators Another file. This is a button on the open random file dialog. It presents a file with the choices Open/Another.
            choice2_text = _("Another"),
            choice2_callback = function()
                self:openRandomFile(dir, unopened_only)
            end,
        })
    else
        UIManager:show(InfoMessage:new{
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

function FileManager:pasteFileFromClipboard(file)
    local orig_file = ffiUtil.realpath(self.clipboard)
    local orig_name = ffiUtil.basename(orig_file)
    local dest_path = ffiUtil.realpath(file or self.file_chooser.path)
    dest_path = isFile(dest_path) and dest_path:match("(.*/)") or dest_path
    local dest_file = ffiUtil.joinPath(dest_path, orig_name)
    if orig_file == dest_file or orig_file == dest_path then -- do not paste to itself
        self.clipboard = nil
        return
    end
    local is_file = isFile(orig_file)

    local function doPaste()
        local ok
        if self.cutfile then
            ok = self:moveFile(orig_file, dest_path)
        else
            ok = self:copyRecursive(orig_file, dest_path)
        end
        if ok then
            if is_file then -- move or copy sdr
                DocSettings.updateLocation(orig_file, dest_file, not self.cutfile)
            end
            if self.cutfile then -- for move only
                if is_file then
                    ReadHistory:updateItem(orig_file, dest_file)
                    ReadCollection:updateItem(orig_file, dest_file)
                else
                    ReadHistory:updateItemsByPath(orig_file, dest_file)
                    ReadCollection:updateItemsByPath(orig_file, dest_file)
                end
            end
            self.clipboard = nil
            self:onRefresh()
        else
            local text = self.cutfile and "Failed to move:\n%1\nto:\n%2"
                                       or "Failed to copy:\n%1\nto:\n%2"
            UIManager:show(InfoMessage:new{
                text = T(_(text), BD.filepath(orig_name), BD.dirpath(dest_path)),
                icon = "notice-warning",
            })
        end
    end

    local mode_dest = lfs.attributes(dest_file, "mode")
    if mode_dest then -- file or folder with target name already exists
        local can_overwrite = (mode_dest == "file") == is_file
        local text = can_overwrite == is_file and T(_("File already exists:\n%1"), BD.filename(orig_name))
                                               or T(_("Folder already exists:\n%1"), BD.directory(orig_name))
        if can_overwrite then
            UIManager:show(ConfirmBox:new{
                text = text,
                ok_text = _("Overwrite"),
                ok_callback = function()
                    doPaste()
                end,
            })
        else
            UIManager:show(InfoMessage:new{
                text = text,
                icon = "notice-warning",
            })
        end
    else
        doPaste()
    end
end

function FileManager:showCopyMoveSelectedFilesDialog(close_callback)
    local text, ok_text
    if self.cutfile then
        text = _("Move selected files to the current folder?")
        ok_text = _("Move")
    else
        text = _("Copy selected files to the current folder?")
        ok_text = _("Copy")
    end
    local confirmbox, check_button_overwrite
    confirmbox = ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = function()
            close_callback()
            self:pasteSelectedFiles(check_button_overwrite.checked)
        end,
    }
    check_button_overwrite = CheckButton:new{
        text = _("overwrite existing files"),
        checked = true,
        parent = confirmbox,
    }
    confirmbox:addWidget(check_button_overwrite)
    UIManager:show(confirmbox)
end

function FileManager:pasteSelectedFiles(overwrite)
    local dest_path = ffiUtil.realpath(self.file_chooser.path)
    local ok_files = {}
    for orig_file in pairs(self.selected_files) do
        local orig_name = ffiUtil.basename(orig_file)
        local dest_file = ffiUtil.joinPath(dest_path, orig_name)
        if ffiUtil.realpath(orig_file) == dest_file then -- do not paste to itself
            self.selected_files[orig_file] = nil
        else
            local ok
            local dest_mode = lfs.attributes(dest_file, "mode")
            if not dest_mode or (dest_mode == "file" and overwrite) then
                if self.cutfile then
                    ok = self:moveFile(orig_file, dest_path)
                else
                    ok = self:copyRecursive(orig_file, dest_path)
                end
            end
            if ok then
                DocSettings.updateLocation(orig_file, dest_file, not self.cutfile)
                ok_files[orig_file] = true
                self.selected_files[orig_file] = nil
            end
        end
    end
    local skipped_nb = util.tableSize(self.selected_files)
    if util.tableSize(ok_files) > 0 then
        if self.cutfile then -- for move only
            ReadHistory:updateItems(ok_files, dest_path)
            ReadCollection:updateItems(ok_files, dest_path)
        end
        if skipped_nb > 0 then
            self:onRefresh()
        end
    end
    if skipped_nb > 0 then -- keep select mode on
        local text = self.cutfile and T(N_("1 file was not moved", "%1 files were not moved", skipped_nb), skipped_nb)
                                   or T(N_("1 file was not copied", "%1 files were not copied", skipped_nb), skipped_nb)
        UIManager:show(InfoMessage:new{
            text = text,
            icon = "notice-warning",
        })
    else
        self:onToggleSelectMode(true)
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
                        if util.makePath(new_folder) then
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

function FileManager:showDeleteFileDialog(filepath, post_delete_callback, pre_delete_callback)
    local file = ffiUtil.realpath(filepath)
    if file == nil then
        UIManager:show(InfoMessage:new{
            text = T(_("File not found:\n%1"), BD.filepath(filepath)),
            icon = "notice-warning",
        })
        return
    end
    local is_file = isFile(file)
    local text = (is_file and _("Delete file permanently?") or _("Delete folder permanently?")) .. "\n\n" .. BD.filepath(file)
    if is_file and BookList.hasBookBeenOpened(file) then
        text = text .. "\n\n" .. _("Book settings, highlights and notes will be deleted.")
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Delete"),
        ok_callback = function()
            if pre_delete_callback then
                pre_delete_callback()
            end
            if self:deleteFile(file, is_file) and post_delete_callback then
                post_delete_callback()
            end
        end,
    })
end

function FileManager:deleteFile(file, is_file)
    if is_file then
        local ok = os.remove(file)
        if ok then
            BookList.resetBookInfoCache(file)
            DocSettings.updateLocation(file) -- delete sdr
            ReadHistory:fileDeleted(file)
            ReadCollection:removeItem(file)
            return true
        end
    else
        local ok = ffiUtil.purgeDir(file)
        if ok then
            ReadHistory:folderDeleted(file) -- will delete sdr
            ReadCollection:removeItemsByPath(file)
            return true
        end
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Failed to delete:\n%1"), BD.filepath(file)),
        icon = "notice-warning",
    })
end

function FileManager:deleteSelectedFiles()
    local ok_files = {}
    for orig_file in pairs(self.selected_files) do
        local file_abs_path = ffiUtil.realpath(orig_file)
        local ok = file_abs_path and os.remove(file_abs_path)
        if ok then
            BookList.resetBookInfoCache(file_abs_path)
            DocSettings.updateLocation(file_abs_path) -- delete sdr
            ok_files[orig_file] = true
            self.selected_files[orig_file] = nil
        end
    end
    local skipped_nb = util.tableSize(self.selected_files)
    if util.tableSize(ok_files) > 0 then
        ReadHistory:removeItems(ok_files)
        ReadCollection:removeItems(ok_files)
        if skipped_nb > 0 then
            self:onRefresh()
        end
    end
    if skipped_nb > 0 then -- keep select mode on
        UIManager:show(InfoMessage:new{
            text = T(N_("Failed to delete 1 file.", "Failed to delete %1 files.", skipped_nb), skipped_nb),
            icon = "notice-warning",
        })
    else
        self:onToggleSelectMode(true)
    end
end

function FileManager:showRenameFileDialog(file, is_file)
    local dialog
    dialog = InputDialog:new{
        title = is_file and _("Rename file") or _("Rename folder"),
        input = ffiUtil.basename(file),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Rename"),
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name ~= "" then
                        UIManager:close(dialog)
                        self:renameFile(file, new_name, is_file)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FileManager:renameFile(file, basename, is_file)
    if ffiUtil.basename(file) == basename then return end
    local dest = ffiUtil.joinPath(ffiUtil.dirname(file), basename)

    local function doRenameFile()
        if self:moveFile(file, dest) then
            if is_file then
                DocSettings.updateLocation(file, dest)
                ReadHistory:updateItem(file, dest) -- (will update "lastfile" if needed)
                ReadCollection:updateItem(file, dest)
            else
                ReadHistory:updateItemsByPath(file, dest)
                ReadCollection:updateItemsByPath(file, dest)
            end
            self:onRefresh()
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Failed to rename:\n%1\nto:\n%2"), BD.filepath(file), BD.filepath(dest)),
                icon = "notice-warning",
            })
        end
    end

    local mode_dest = lfs.attributes(dest, "mode")
    if mode_dest then
        local text, ok_text
        if (mode_dest == "file") ~= is_file then
            if is_file then
                text = T(_("Folder already exists:\n%1\nFile cannot be renamed."), BD.directory(basename))
            else
                text = T(_("File already exists:\n%1\nFolder cannot be renamed."), BD.filename(basename))
            end
            UIManager:show(InfoMessage:new{
                text = text,
                icon = "notice-warning",
            })
        else
            if is_file then
                text = T(_("File already exists:\n%1\nOverwrite file?"), BD.filename(basename))
                ok_text = _("Overwrite")
            else
                text = T(_("Folder already exists:\n%1\nMove the folder inside it?"), BD.directory(basename))
                ok_text = _("Move")
            end
            UIManager:show(ConfirmBox:new{
                text = text,
                ok_text = ok_text,
                ok_callback = function()
                    doRenameFile()
                end,
            })
        end
    else
        doRenameFile()
    end
end

--- @note: This is the *only* safe way to instantiate a new FileManager instance!
function FileManager:showFiles(path, focused_file, selected_files)
    -- Warn about and close any pre-existing FM instances first...
    if FileManager.instance then
        logger.warn("FileManager instance mismatch! Tried to spin up a new instance, while we still have an existing one:", tostring(FileManager.instance))
        -- Close the old one first!
        FileManager.instance:onClose()
    end

    path = ffiUtil.realpath(path or G_reader_settings:readSetting("lastdir") or filemanagerutil.getDefaultDir())
    G_reader_settings:saveSetting("lastdir", path)
    self:setRotationMode()
    local file_manager = FileManager:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        root_path = path,
        focused_file = focused_file,
        selected_files = selected_files,
    }
    UIManager:show(file_manager)
end

--- A shortcut to execute mv.
-- @treturn boolean result of mv command
function FileManager:moveFile(from, to)
    return ffiUtil.execute(self.mv_bin, from, to) == 0
end

--- A shortcut to execute cp.
-- @treturn boolean result of cp command
function FileManager:copyFileFromTo(from, to)
    return ffiUtil.execute(self.cp_bin, from, to) == 0
end

--- A shortcut to execute cp recursively.
-- @treturn boolean result of cp command
function FileManager:copyRecursive(from, to)
    return ffiUtil.execute(self.cp_bin, "-r", from, to ) == 0
end

function FileManager:onShowFolderMenu()
    local button_dialog
    local function genButton(button_text, button_path)
        return {{
            text = button_text,
            avoid_text_truncation = false,
            menu_style = true,
            callback = function()
                UIManager:close(button_dialog)
                self.file_chooser:changeToPath(button_path)
            end,
            hold_callback = function()
                return true -- do not move the menu
            end,
        }}
    end

    local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    local home_dir_shortened = G_reader_settings:nilOrTrue("shorten_home_dir")
    local home_dir_not_locked = G_reader_settings:nilOrFalse("lock_home_folder")
    local home_dir_suffix = "  \u{f015}" -- "home" character
    local buttons = {}
    -- root folder
    local text
    local path = "/"
    local is_home = path == home_dir
    local home_found = is_home or home_dir_not_locked
    if home_found then
        text = path
        if is_home and home_dir_shortened then
            text = text .. home_dir_suffix
        end
        table.insert(buttons, genButton(text, path))
    end
    -- other folders
    local indent = ""
    for part in self.file_chooser.path:gmatch("([^/]+)") do
        text = (#buttons == 0 and path or indent .. "└ ") .. part
        path = path .. part .. "/"
        is_home = path == home_dir or path == home_dir .. "/"
        if not home_found and is_home then
            home_found = true
        end
        if home_found then
            if is_home and home_dir_shortened then
                text = text .. home_dir_suffix
            end
            table.insert(buttons, genButton(text, path))
            indent = indent .. " "
        end
    end

    button_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(button_dialog)
end

function FileManager:showSelectedFilesList()
    local selected_files = {}
    for file in pairs(self.selected_files) do
        table.insert(selected_files, {
            text = filemanagerutil.abbreviate(file),
            filepath = file,
            bidi_wrap_func = BD.filepath,
        })
    end
    local function sorting(a, b)
        local a_path, a_name = util.splitFilePathName(a.text)
        local b_path, b_name = util.splitFilePathName(b.text)
        if a_path == b_path then
            return ffiUtil.strcoll(a_name, b_name)
        end
        return ffiUtil.strcoll(a_path, b_path)
    end
    table.sort(selected_files, sorting)

    local menu
    menu = BookList:new{
        title = T(_("Selected files (%1)"), #selected_files),
        item_table = selected_files,
        truncate_left = true,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            self.file_chooser:changeToPath(util.splitFilePathName(item.filepath), item.filepath)
        end,
    }
    UIManager:show(menu)
end

function FileManager:showOpenWithDialog(file)
    local file_associated_provider_key = DocumentRegistry:getAssociatedProviderKey(file, false)
    local type_associated_provider_key = DocumentRegistry:getAssociatedProviderKey(file, true)
    local file_provider_key = file_associated_provider_key
                           or type_associated_provider_key
                           or DocumentRegistry:getProvider(file).provider

    -- radio buttons (all providers)
    local function genRadioButton(provider, is_unsupported)
        return {{
            -- @translators %1 is the provider name, such as Cool Reader Engine or MuPDF.
            text = is_unsupported and T(_("%1 ~Unsupported"), provider.provider_name) or provider.provider_name,
            checked = provider.provider == file_provider_key,
            provider = provider,
        }}
    end
    local radio_buttons = {}
    local providers = DocumentRegistry:getProviders(file) -- document providers
    if providers then
        for _, provider in ipairs(providers) do
            table.insert(radio_buttons, genRadioButton(provider.provider))
        end
    else
        local provider = DocumentRegistry:getFallbackProvider()
        table.insert(radio_buttons, genRadioButton(provider, true))
    end
    for _, provider in ipairs(DocumentRegistry:getAuxProviders()) do -- auxiliary providers
        local is_filetype_supported
        if provider.enabled_func then -- module
            is_filetype_supported = provider.enabled_func(file)
        else -- plugin
            is_filetype_supported = self[provider.provider]:isFileTypeSupported(file)
        end
        if is_filetype_supported then
            table.insert(radio_buttons, genRadioButton(provider))
        end
    end

    -- buttons
    local __, filename_pure = util.splitFilePathName(file)
    filename_pure = BD.filename(filename_pure)
    local filename_suffix = util.getFileNameSuffix(file):lower()
    local dialog
    local buttons = {}
    -- row: wide button
    if file_associated_provider_key then
        table.insert(buttons, {{
            text = _("Reset default for this file"),
            callback = function()
                DocumentRegistry:setProvider(file, nil, false)
                UIManager:close(dialog)
            end,
        }})
    end
    -- row: wide button
    if type_associated_provider_key then
        table.insert(buttons, {{
            text = T(_("Reset default for %1 files"), filename_suffix),
            callback = function()
                DocumentRegistry:setProvider(file, nil, true)
                UIManager:close(dialog)
            end,
        }})
    end
    -- row: wide button
    local associated_providers = DocumentRegistry:getAssociatedProviderKey() -- hash table
    if associated_providers ~= nil and next(associated_providers) ~= nil then
        table.insert(buttons, {{
            text = _("View defaults for file types"),
            callback = function()
                local max_len = 0 -- align extensions
                for extension in pairs(associated_providers) do
                    if max_len < #extension then
                        max_len = #extension
                    end
                end
                local t = {}
                for extension, provider_key in pairs(associated_providers) do
                    local provider = DocumentRegistry:getProviderFromKey(provider_key)
                    if provider then
                        local space = string.rep(" ", max_len - #extension)
                        table.insert(t, T("%1%2: %3", extension, space, provider.provider_name))
                    end
                end
                table.sort(t)
                UIManager:show(InfoMessage:new{
                    text = table.concat(t, "\n"),
                    monospace_font = true,
                })
            end,
        }})
    end
    -- row: 2 buttons
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(dialog)
            end,
        },
        {
            text = _("Open"),
            is_enter_default = true,
            callback = function()
                local provider = dialog.radio_button_table.checked_button.provider
                if dialog._check_file_button.checked then -- set this file associated provider
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open '%2' with %1?"), provider.provider_name, filename_pure),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, false)
                            self:openFile(file, provider)
                            UIManager:close(dialog)
                        end,
                    })
                elseif dialog._check_global_button.checked then -- set file type associated provider
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open %2 files with %1?"), provider.provider_name, filename_suffix),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, true)
                            self:openFile(file, provider)
                            UIManager:close(dialog)
                        end,
                    })
                else -- open just once
                    self:openFile(file, provider)
                    UIManager:close(dialog)
                end
            end,
        },
    })

    local OpenWithDialog = require("ui/widget/openwithdialog")
    dialog = OpenWithDialog:new{
        title = T(_("Open %1 with:"), filename_pure),
        radio_buttons = radio_buttons,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function FileManager:openFile(file, provider, doc_caller_callback, aux_caller_callback)
    local is_provider_forced = provider ~= nil
    provider = provider or DocumentRegistry:getProvider(file, true) -- include auxiliary
    if provider and provider.order then -- auxiliary
        if aux_caller_callback then
            aux_caller_callback()
        end
        if provider.callback then -- module
            provider.callback(file)
        else -- plugin
            self[provider.provider]:openFile(file)
        end
    else -- document
        if doc_caller_callback then
            doc_caller_callback()
        end
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file, provider, nil, is_provider_forced)
    end
end

-- Dispatcher helpers

function FileManager.getDisplayModeActions()
    local action_names, action_texts = { "classic" }, { _("Classic (filename only)") }
    local ui = FileManager.instance or require("apps/reader/readerui").instance
    if ui.coverbrowser then
        for _, v in ipairs(ui.coverbrowser.modes) do
            local action_text, action_name = unpack(v)
            if action_name then -- skip Classic
                table.insert(action_names, action_name)
                table.insert(action_texts, action_text)
            end
        end
    end
    return action_names, action_texts
end

function FileManager:onSetDisplayMode(mode)
    if self.coverbrowser then
        mode = mode ~= "classic" and mode or nil
        self.coverbrowser:setDisplayMode(mode)
    end
    return true
end

function FileManager.getSortByActions()
    local collates = {}
    for k, v in pairs(FileChooser.collates) do
        table.insert(collates, {
            name = k,
            text = v.text,
            menu_order = v.menu_order,
        })
    end
    table.sort(collates, function(a, b) return a.menu_order < b.menu_order end)

    local action_names, action_texts = {}, {}
    for _, v in ipairs(collates) do
        table.insert(action_names, v.name)
        table.insert(action_texts, v.text)
    end
    return action_names, action_texts
end

function FileManager:onSetSortBy(mode)
    G_reader_settings:saveSetting("collate", mode)
    self.file_chooser:clearSortingCache()
    self.file_chooser:refreshPath()
    return true
end

function FileManager:onSetReverseSorting(toggle)
    G_reader_settings:saveSetting("reverse_collate", toggle or nil)
    self.file_chooser:refreshPath()
    return true
end

function FileManager:onSetMixedSorting(toggle)
    G_reader_settings:saveSetting("collate_mixed", toggle or nil)
    self.file_chooser:refreshPath()
    return true
end

function FileManager:onOpenNextOrPreviousFileInFolder(prev)
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file then return true end
    local file = self.file_chooser:getNextOrPreviousFileInFolder(last_file, prev)
    if file then
        self:openFile(file)
    else
        UIManager:show(InfoMessage:new{
            text = prev and _("Last book is the first file in the folder. No previous file to open.")
                         or _("Last book is the last file in the folder. No next file to open."),
        })
    end
    return true
end

return FileManager
