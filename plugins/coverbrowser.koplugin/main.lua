local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local BookInfoManager = require("bookinfomanager")

--[[
    This plugin provides additional display modes to file browsers (File Manager
    and History).
    It does that by dynamically replacing some methods code to their classes
    or instances.
--]]

-- We need to save the original methods early here as locals.
-- For some reason, saving them as attributes in init() does not allow
-- us to get back to classic mode
local FileChooser = require("ui/widget/filechooser")
local _FileChooser__recalculateDimen_orig = FileChooser._recalculateDimen
local _FileChooser_updateItems_orig = FileChooser.updateItems
local _FileChooser_onCloseWidget_orig = FileChooser.onCloseWidget
local _FileChooser_onSwipe_orig = FileChooser.onSwipe

local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local _FileManagerHistory_updateItemTable_orig = FileManagerHistory.updateItemTable

-- Available display modes
local DISPLAY_MODES = {
    -- nil or ""                -- classic : filename only
    mosaic_image        = true, -- 3x3 grid covers with images
    mosaic_text         = true, -- 3x3 grid covers text only
    list_image_meta     = true, -- image with metadata (title/authors)
    list_only_meta      = true, -- metadata with no image
    list_image_filename = true, -- image with filename (no metadata)
}

-- Store some states as locals, to be permanent across instantiations
local init_done = false
local filemanager_display_mode = false -- not initialized yet
local history_display_mode = false -- not initialized yet

local CoverBrowser = InputContainer:new{}

function CoverBrowser:init()
    self.full_featured = true
    -- (Could be set to false for some platforms to provide a fallback
    -- option with only a menu for managing a few core settings)

    self.ui.menu:registerToMainMenu(self)

    if not self.full_featured then -- nothing else than menu registration
        return
    end

    if init_done then -- things already patched according to current modes
        return
    end

    self:setupFileManagerDisplayMode(BookInfoManager:getSetting("filemanager_display_mode"))
    self:setupHistoryDisplayMode(BookInfoManager:getSetting("history_display_mode"))
    init_done = true
end

function CoverBrowser:addToMainMenu(menu_items)
    -- We add it only to FileManager menu
    if self.ui.view then -- Reader
        return
    end

    -- Items available even if not full_featured
    -- (settings used by core, that fit in this menu)
    local generic_items = {
        {
            text_func = function()
                local current_state = _("Show new files in bold")
                if G_reader_settings:readSetting("show_file_in_bold") == "opened" then
                    current_state = _("Show opened files in bold")
                elseif G_reader_settings:readSetting("show_file_in_bold") == false then
                    current_state = _("Show files in bold") -- with checkmark unchecked
                end
                if self.full_featured then
                    -- Inform that this settings applies only to classic file chooser
                    current_state = _("(Classic mode) ") .. current_state
                end
                return current_state
            end,
            checked_func = function() return G_reader_settings:readSetting("show_file_in_bold") ~= false end,
            sub_item_table = {
                {
                    text = _("Don't show files in bold"),
                    checked_func = function() return G_reader_settings:readSetting("show_file_in_bold") == false end,
                    callback = function()
                        G_reader_settings:saveSetting("show_file_in_bold", false)
                        self:refreshFileManagerInstance()
                    end,
                },
                {
                    text = _("Show opened files in bold"),
                    checked_func = function() return G_reader_settings:readSetting("show_file_in_bold") == "opened" end,
                    callback = function()
                        G_reader_settings:saveSetting("show_file_in_bold", "opened")
                        self:refreshFileManagerInstance()
                    end,
                },
                {
                    text = _("Show new (not yet opened) files in bold"),
                    checked_func = function()
                        return G_reader_settings:readSetting("show_file_in_bold") ~= false and G_reader_settings:readSetting("show_file_in_bold") ~= "opened"
                    end,
                    callback = function()
                        G_reader_settings:delSetting("show_file_in_bold")
                        self:refreshFileManagerInstance()
                    end,
                },
            },
            separator = true,
        },
        {
            text = _("Shorten home directory to ~"),
            checked_func = function() return G_reader_settings:readSetting("home_dir_display_name") end,
            callback = function()
                if G_reader_settings:readSetting("home_dir_display_name") then
                    G_reader_settings:delSetting("home_dir_display_name")
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then FileManager.instance:reinit() end
                else
                    G_reader_settings:saveSetting("home_dir_display_name", "~")
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then FileManager.instance:reinit() end
                end
            end,
        },
        {
            text = _("Auto-remove deleted or purged items from history"),
            checked_func = function() return G_reader_settings:readSetting("autoremove_deleted_items_from_history") end,
            callback = function() G_reader_settings:flipNilOrFalse("autoremove_deleted_items_from_history") end,
        },
    }

    if not self.full_featured then
        -- Make the generic items directly as 1st level items,
        -- and use alternate name for main menu, not mentionning
        -- "display mode" that are not available
        menu_items.filemanager_display_mode = {
            text = _("File browser settings"),
            sub_item_table = generic_items
        }
        return
    end

    menu_items.filemanager_display_mode = {
        text = _("Display mode"),
        sub_item_table = {
            -- selecting these does not close menu, which may be nice
            -- so one can see how they look below the menu
            {
                text = _("Classic (filename only)"),
                checked_func = function() return not filemanager_display_mode end,
                callback = function()
                   self:setupFileManagerDisplayMode("")
                end,
            },
            {
                text = _("Mosaic with cover images"),
                checked_func = function() return filemanager_display_mode == "mosaic_image" end,
                callback = function()
                   self:setupFileManagerDisplayMode("mosaic_image")
                end,
            },
            {
                text = _("Mosaic with text covers"),
                checked_func = function() return filemanager_display_mode == "mosaic_text" end,
                callback = function()
                   self:setupFileManagerDisplayMode("mosaic_text")
                end,
            },
            {
                text = _("Detailed list with cover images and metadata"),
                checked_func = function() return filemanager_display_mode == "list_image_meta" end,
                callback = function()
                   self:setupFileManagerDisplayMode("list_image_meta")
                end,
            },
            {
                text = _("Detailed list with metadata, no images"),
                checked_func = function() return filemanager_display_mode == "list_only_meta" end,
                callback = function()
                   self:setupFileManagerDisplayMode("list_only_meta")
                end,
            },
            {
                text = _("Detailed list with cover images and filenames"),
                checked_func = function() return filemanager_display_mode == "list_image_filename" end,
                callback = function()
                   self:setupFileManagerDisplayMode("list_image_filename")
                end,
                separator = true,
            },
            -- Plug the same choices for History here as a submenu
            -- (Any other suitable place for that ?)
            {
                text = _("History display mode"),
                sub_item_table = {
                    {
                        text = _("Classic (filename only)"),
                        checked_func = function() return not history_display_mode end,
                        callback = function()
                           self:setupHistoryDisplayMode("")
                        end,
                    },
                    {
                        text = _("Mosaic with cover images"),
                        checked_func = function() return history_display_mode == "mosaic_image" end,
                        callback = function()
                           self:setupHistoryDisplayMode("mosaic_image")
                        end,
                    },
                    {
                        text = _("Mosaic with text covers"),
                        checked_func = function() return history_display_mode == "mosaic_text" end,
                        callback = function()
                           self:setupHistoryDisplayMode("mosaic_text")
                        end,
                    },
                    {
                        text = _("Detailed list with cover images and metadata"),
                        checked_func = function() return history_display_mode == "list_image_meta" end,
                        callback = function()
                           self:setupHistoryDisplayMode("list_image_meta")
                        end,
                    },
                    {
                        text = _("Detailed list with metadata, no images"),
                        checked_func = function() return history_display_mode == "list_only_meta" end,
                        callback = function()
                           self:setupHistoryDisplayMode("list_only_meta")
                        end,
                    },
                    {
                        text = _("Detailed list with cover images and filenames"),
                        checked_func = function() return history_display_mode == "list_image_filename" end,
                        callback = function()
                           self:setupHistoryDisplayMode("list_image_filename")
                        end,
                        separator = true,
                    },
                },
                separator = true,
            },
            -- Misc settings
            {
                text = _("Other settings"),
                sub_item_table = {
                    {
                        text = _("Show hint for books with description"),
                        checked_func = function() return not BookInfoManager:getSetting("no_hint_description") end,
                        callback = function()
                            if BookInfoManager:getSetting("no_hint_description") then
                                BookInfoManager:saveSetting("no_hint_description", false)
                            else
                                BookInfoManager:saveSetting("no_hint_description", true)
                            end
                            self:refreshFileManagerInstance()
                        end,
                    },
                    {
                        text = _("Show hint for opened books in history"),
                        checked_func = function() return BookInfoManager:getSetting("history_hint_opened") end,
                        callback = function()
                            if BookInfoManager:getSetting("history_hint_opened") then
                                BookInfoManager:saveSetting("history_hint_opened", false)
                            else
                                BookInfoManager:saveSetting("history_hint_opened", true)
                            end
                            self:refreshFileManagerInstance()
                        end,
                    },
                    {
                        text = _("Append series metadata to authors"),
                        checked_func = function() return BookInfoManager:getSetting("append_series_to_authors") end,
                        callback = function()
                            if BookInfoManager:getSetting("append_series_to_authors") then
                                BookInfoManager:saveSetting("append_series_to_authors", false)
                            else
                                BookInfoManager:saveSetting("append_series_to_authors", true)
                            end
                            self:refreshFileManagerInstance()
                        end,
                    },
                    {
                        text = _("Append series metadata to title"),
                        checked_func = function() return BookInfoManager:getSetting("append_series_to_title") end,
                        callback = function()
                            if BookInfoManager:getSetting("append_series_to_title") then
                                BookInfoManager:saveSetting("append_series_to_title", false)
                            else
                                BookInfoManager:saveSetting("append_series_to_title", true)
                            end
                            self:refreshFileManagerInstance()
                        end,
                    },
                    -- generic_items will be inserted here
                },
            },
            {
                text = _("Book info cache management"),
                sub_item_table = {
                    {
                        text_func = function() -- add current db size to menu text
                            local sstr = BookInfoManager:getDbSize()
                            return _("Current cache size: ") .. sstr
                        end,
                        -- no callback, only for information
                    },
                    {
                        text = _("Prune cache of removed books"),
                        callback = function()
                            local ConfirmBox = require("ui/widget/confirmbox")
                            UIManager:close(self.file_dialog)
                            UIManager:show(ConfirmBox:new{
                                -- Checking file existences is quite fast, but deleting entries is slow.
                                text = _("Are you sure that you want to prune cache of removed books?\n(This may take a while.)"),
                                ok_text = _("Prune cache"),
                                ok_callback = function()
                                    local InfoMessage = require("ui/widget/infomessage")
                                    local msg = InfoMessage:new{ text = _("Pruning cache of removed books…") }
                                    UIManager:show(msg)
                                    UIManager:nextTick(function()
                                        local summary = BookInfoManager:removeNonExistantEntries()
                                        UIManager:close(msg)
                                        UIManager:show( InfoMessage:new{ text = summary } )
                                    end)
                                end
                            })
                        end,
                    },
                    {
                        text = _("Compact cache database"),
                        callback = function()
                            local ConfirmBox = require("ui/widget/confirmbox")
                            UIManager:close(self.file_dialog)
                            UIManager:show(ConfirmBox:new{
                                text = _("Are you sure that you want to compact cache database?\n(This may take a while.)"),
                                ok_text = _("Compact database"),
                                ok_callback = function()
                                    local InfoMessage = require("ui/widget/infomessage")
                                    local msg = InfoMessage:new{ text = _("Compacting cache database…") }
                                    UIManager:show(msg)
                                    UIManager:nextTick(function()
                                        local summary = BookInfoManager:compactDb()
                                        UIManager:close(msg)
                                        UIManager:show( InfoMessage:new{ text = summary } )
                                    end)
                                end
                            })
                        end,
                    },
                    {
                        text = _("Delete cache database"),
                        callback = function()
                            local ConfirmBox = require("ui/widget/confirmbox")
                            UIManager:close(self.file_dialog)
                            UIManager:show(ConfirmBox:new{
                                text = _("Are you sure that you want to delete cover and metadata cache?\n(This will also reset your display mode settings.)"),
                                ok_text = _("Purge"),
                                ok_callback = function()
                                    BookInfoManager:deleteDb()
                                end
                            })
                        end,
                    },
                },
            },
        },
    }
    -- Finally, insert the generic items at end of "Other settings" submenu
    local sub_item_table = menu_items.filemanager_display_mode.sub_item_table
    local generic_items_target = sub_item_table[#sub_item_table-1].sub_item_table -- second to last
    for _, item in pairs(generic_items) do
        table.insert(generic_items_target, item)
    end
end

function CoverBrowser:refreshFileManagerInstance(cleanup, post_init)
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if fm then
        local fc = fm.file_chooser
        if cleanup then -- clean instance properties we may have set
            if fc.onFileHold_orig then
                -- remove our onFileHold that extended file_dialog with new buttons
                fc.onFileHold = fc.onFileHold_orig
                fc.onFileHold_orig = nil
                fc.onFileHold_ours = nil
            end
        end
        if filemanager_display_mode then
            if post_init then
                -- FileBrowser was initialized in classic mode, but we changed
                -- display mode: items per page may have changed, and we want
                -- to re-position on the focused_file
                fc:_recalculateDimen()
                fc:changeToPath(fc.path, fc.prev_focused_path)
            else
                fc:updateItems()
            end
        else -- classic file_chooser needs this for a full redraw
            fc:refreshPath()
        end
    end
end

function CoverBrowser:setupFileManagerDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknow mode, fallback to classic
    end
    if init_done and display_mode == filemanager_display_mode then -- no change
        return
    end
    if init_done then -- save new mode in db
        BookInfoManager:saveSetting("filemanager_display_mode", display_mode)
    end
    -- remember current mode in module variable
    filemanager_display_mode = display_mode
    logger.dbg("CoverBrowser: setting FileManager display mode to:", display_mode or "classic")

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    if not display_mode then -- classic mode
        -- Put back original methods
        FileChooser.updateItems = _FileChooser_updateItems_orig
        FileChooser.onCloseWidget = _FileChooser_onCloseWidget_orig
        FileChooser.onSwipe = _FileChooser_onSwipe_orig
        FileChooser._recalculateDimen = _FileChooser__recalculateDimen_orig
        -- Also clean-up what we added, even if it does not bother original code
        FileChooser._updateItemsBuildUI = nil
        FileChooser._do_cover_images = nil
        FileChooser._do_filename_only = nil
        FileChooser._do_hint_opened = nil
        self:refreshFileManagerInstance(true)
        return
    end

    -- In both mosaic and list modes, replace original methods with those from
    -- our generic CoverMenu
    local CoverMenu = require("covermenu")
    FileChooser.updateItems = CoverMenu.updateItems
    FileChooser.onCloseWidget = CoverMenu.onCloseWidget
    FileChooser.onSwipe = CoverMenu.onSwipe

    if display_mode == "mosaic_image" or display_mode == "mosaic_text" then -- mosaic mode
        -- Replace some other original methods with those from our MosaicMenu
        local MosaicMenu = require("mosaicmenu")
        FileChooser._recalculateDimen = MosaicMenu._recalculateDimen
        FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
        -- Set MosaicMenu behaviour:
        FileChooser._do_cover_images = display_mode ~= "mosaic_text"
        FileChooser._do_hint_opened = true -- dogear at bottom
        -- One could override default 3x3 grid here (put that as settings ?)
        -- FileChooser.nb_cols_portrait = 4
        -- FileChooser.nb_rows_portrait = 4
        -- FileChooser.nb_cols_landscape = 6
        -- FileChooser.nb_rows_landscape = 3

    elseif display_mode == "list_image_meta" or display_mode == "list_only_meta" or
                                     display_mode == "list_image_filename" then -- list modes
        -- Replace some other original methods with those from our ListMenu
        local ListMenu = require("listmenu")
        FileChooser._recalculateDimen = ListMenu._recalculateDimen
        FileChooser._updateItemsBuildUI = ListMenu._updateItemsBuildUI
        -- Set ListMenu behaviour:
        FileChooser._do_cover_images = display_mode ~= "list_only_meta"
        FileChooser._do_filename_only = display_mode == "list_image_filename"
        FileChooser._do_hint_opened = true -- dogear at bottom
    end

    if init_done then
        self:refreshFileManagerInstance()
    else
        -- If KOReader has started directly to FileManager, the FileManager
        -- instance is being init()'ed and there is no FileManager.instance yet,
        -- but there'll be one at next tick.
        UIManager:nextTick(function()
            self:refreshFileManagerInstance(false, true)
        end)
    end

end

local function _FileManagerHistory_updateItemTable(self)
    -- 'self' here is the single FileManagerHistory instance
    -- FileManagerHistory has just created a new instance of Menu as 'hist_menu'
    -- at each display of History. Soon after instantiation, this method
    -- is called. The first time it is called, we replace some methods.
    local display_mode = self.display_mode
    local hist_menu = self.hist_menu

    if not hist_menu._coverbrowser_overridden then
        hist_menu._coverbrowser_overridden = true

        -- In both mosaic and list modes, replace original methods with those from
        -- our generic CoverMenu
        local CoverMenu = require("covermenu")
        hist_menu.updateItems = CoverMenu.updateItems
        hist_menu.onCloseWidget = CoverMenu.onCloseWidget
        hist_menu.onSwipe = CoverMenu.onSwipe
        -- Also replace original onMenuHold (it will use original method, so remember it)
        hist_menu.onMenuHold_orig = hist_menu.onMenuHold
        hist_menu.onMenuHold = CoverMenu.onHistoryMenuHold

        if display_mode == "mosaic_image" or display_mode == "mosaic_text" then -- mosaic mode
            -- Replace some other original methods with those from our MosaicMenu
            local MosaicMenu = require("mosaicmenu")
            hist_menu._recalculateDimen = MosaicMenu._recalculateDimen
            hist_menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
            -- Set MosaicMenu behaviour:
            hist_menu._do_cover_images = display_mode ~= "mosaic_text"
            -- no need for do_hint_opened with History

        elseif display_mode == "list_image_meta" or display_mode == "list_only_meta" or
                                 display_mode == "list_image_filename" then -- list modes
            -- Replace some other original methods with those from our ListMenu
            local ListMenu = require("listmenu")
            hist_menu._recalculateDimen = ListMenu._recalculateDimen
            hist_menu._updateItemsBuildUI = ListMenu._updateItemsBuildUI
            -- Set ListMenu behaviour:
            hist_menu._do_cover_images = display_mode ~= "list_only_meta"
            hist_menu._do_filename_only = display_mode == "list_image_filename"
            -- no need for do_hint_opened with History

        end
        hist_menu._do_hint_opened = BookInfoManager:getSetting("history_hint_opened")
    end

    -- And do now what the original does
    _FileManagerHistory_updateItemTable_orig(self)
end

function CoverBrowser:setupHistoryDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknow mode, fallback to classic
    end
    if init_done and display_mode == history_display_mode then -- no change
        return
    end
    if init_done then -- save new mode in db
        BookInfoManager:saveSetting("history_display_mode", display_mode)
    end
    -- remember current mode in module variable
    history_display_mode = display_mode
    logger.dbg("CoverBrowser: setting History display mode to:", display_mode or "classic")

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    -- We only need to replace one FileManagerHistory method
    if not display_mode then -- classic mode
        -- Put back original methods
        FileManagerHistory.updateItemTable = _FileManagerHistory_updateItemTable_orig
        FileManagerHistory.display_mode = nil
    else
        -- Replace original method with the one defined above
        FileManagerHistory.updateItemTable = _FileManagerHistory_updateItemTable
        -- And let it know which display_mode we should use
        FileManagerHistory.display_mode = display_mode
    end
end

return CoverBrowser
