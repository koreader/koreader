local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
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

local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local _FileManagerHistory_updateItemTable_orig = FileManagerHistory.updateItemTable

local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local _FileManagerCollection_updateItemTable_orig = FileManagerCollection.updateItemTable

local FileManager = require("apps/filemanager/filemanager")
local _FileManager_tapPlus_orig = FileManager.tapPlus

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
local collection_display_mode = false -- not initialized yet
local series_mode = nil -- defaults to not display series

local CoverBrowser = WidgetContainer:extend{
    name = "coverbrowser",
    modes = {
        { _("Classic (filename only)") },
        { _("Mosaic with cover images"), "mosaic_image" },
        { _("Mosaic with text covers"), "mosaic_text" },
        { _("Detailed list with cover images and metadata"), "list_image_meta" },
        { _("Detailed list with metadata, no images"), "list_only_meta" },
        { _("Detailed list with cover images and filenames"), "list_image_filename" },
    },
}

function CoverBrowser:init()
    if self.ui.file_chooser then -- FileManager menu only
        self.ui.menu:registerToMainMenu(self)
    end

    if init_done then -- things already patched according to current modes
        return
    end

    -- Set up default display modes on first launch
    if not G_reader_settings:isTrue("coverbrowser_initial_default_setup_done") then
        -- Only if no display mode has been set yet
        if not BookInfoManager:getSetting("filemanager_display_mode")
            and not BookInfoManager:getSetting("history_display_mode") then
            logger.info("CoverBrowser: setting default display modes")
            BookInfoManager:saveSetting("filemanager_display_mode", "list_image_meta")
            BookInfoManager:saveSetting("history_display_mode", "mosaic_image")
            BookInfoManager:saveSetting("collection_display_mode", "mosaic_image")
        end
        G_reader_settings:makeTrue("coverbrowser_initial_default_setup_done")
    end

    self:setupFileManagerDisplayMode(BookInfoManager:getSetting("filemanager_display_mode"))
    self:setupHistoryDisplayMode(BookInfoManager:getSetting("history_display_mode"))
    self:setupCollectionDisplayMode(BookInfoManager:getSetting("collection_display_mode"))
    series_mode = BookInfoManager:getSetting("series_mode")
    init_done = true
    BookInfoManager:closeDbConnection() -- will be re-opened if needed
end

function CoverBrowser:addToMainMenu(menu_items)
    local sub_item_table, history_sub_item_table, collection_sub_item_table = {}, {}, {}
    for i, v in ipairs(self.modes) do
        local text, mode = unpack(v)
        sub_item_table[i] = {
            text = text,
            checked_func = function()
                return mode == filemanager_display_mode
            end,
            callback = function()
                self:setDisplayMode(mode)
            end,
        }
        history_sub_item_table[i] = {
            text = text,
            checked_func = function()
                return mode == history_display_mode
            end,
            callback = function()
                self:setupHistoryDisplayMode(mode)
            end,
        }
        collection_sub_item_table[i] = {
            text = text,
            checked_func = function()
                return mode == collection_display_mode
            end,
            callback = function()
                self:setupCollectionDisplayMode(mode)
            end,
        }
    end
    sub_item_table[#self.modes].separator = true
    table.insert(sub_item_table, {
        text = _("Use this mode everywhere"),
        checked_func = function()
            return BookInfoManager:getSetting("unified_display_mode")
        end,
        callback = function()
            if BookInfoManager:toggleSetting("unified_display_mode") then
                self:setupHistoryDisplayMode(filemanager_display_mode)
                self:setupCollectionDisplayMode(filemanager_display_mode)
            end
        end,
    })
    table.insert(sub_item_table, {
        text = _("History display mode"),
        enabled_func = function()
            return not BookInfoManager:getSetting("unified_display_mode")
        end,
        sub_item_table = history_sub_item_table,
    })
    table.insert(sub_item_table, {
        text = _("Collections display mode"),
        enabled_func = function()
            return not BookInfoManager:getSetting("unified_display_mode")
        end,
        sub_item_table = collection_sub_item_table,
    })
    menu_items.filemanager_display_mode = {
        text = _("Display mode"),
        sub_item_table = sub_item_table,
    }

    -- add Mosaic / Detailed list mode settings to File browser Settings submenu
    -- next to Classic mode settings
    if menu_items.filebrowser_settings == nil then return end
    local fc = self.ui.file_chooser
    table.insert (menu_items.filebrowser_settings.sub_item_table, 5, {
        text = _("Mosaic and detailed list settings"),
        separator = true,
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Items per page in portrait mosaic mode: %1 × %2"), fc.nb_cols_portrait, fc.nb_rows_portrait)
                end,
                -- Best to not "keep_menu_open = true", to see how this apply on the full view
                callback = function()
                    local nb_cols = fc.nb_cols_portrait
                    local nb_rows = fc.nb_rows_portrait
                    local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
                    local widget = DoubleSpinWidget:new{
                        title_text = _("Portrait mosaic mode"),
                        width_factor = 0.6,
                        left_text = _("Columns"),
                        left_value = nb_cols,
                        left_min = 2,
                        left_max = 8,
                        left_default = 3,
                        left_precision = "%01d",
                        right_text = _("Rows"),
                        right_value = nb_rows,
                        right_min = 2,
                        right_max = 8,
                        right_default = 3,
                        right_precision = "%01d",
                        keep_shown_on_apply = true,
                        callback = function(left_value, right_value)
                            fc.nb_cols_portrait = left_value
                            fc.nb_rows_portrait = right_value
                            if fc.display_mode_type == "mosaic" and fc.portrait_mode then
                                fc.no_refresh_covers = true
                                fc:updateItems()
                            end
                        end,
                        close_callback = function()
                            if fc.nb_cols_portrait ~= nb_cols or fc.nb_rows_portrait ~= nb_rows then
                                BookInfoManager:saveSetting("nb_cols_portrait", fc.nb_cols_portrait)
                                BookInfoManager:saveSetting("nb_rows_portrait", fc.nb_rows_portrait)
                                FileChooser.nb_cols_portrait = fc.nb_cols_portrait
                                FileChooser.nb_rows_portrait = fc.nb_rows_portrait
                                if fc.display_mode_type == "mosaic" and fc.portrait_mode then
                                    fc.no_refresh_covers = nil
                                    fc:updateItems()
                                end
                            end
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
            {
                text_func = function()
                    return T(_("Items per page in landscape mosaic mode: %1 × %2"), fc.nb_cols_landscape, fc.nb_rows_landscape)
                end,
                callback = function()
                    local nb_cols = fc.nb_cols_landscape
                    local nb_rows = fc.nb_rows_landscape
                    local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
                    local widget = DoubleSpinWidget:new{
                        title_text = _("Landscape mosaic mode"),
                        width_factor = 0.6,
                        left_text = _("Columns"),
                        left_value = nb_cols,
                        left_min = 2,
                        left_max = 8,
                        left_default = 4,
                        left_precision = "%01d",
                        right_text = _("Rows"),
                        right_value = nb_rows,
                        right_min = 2,
                        right_max = 8,
                        right_default = 2,
                        right_precision = "%01d",
                        keep_shown_on_apply = true,
                        callback = function(left_value, right_value)
                            fc.nb_cols_landscape = left_value
                            fc.nb_rows_landscape = right_value
                            if fc.display_mode_type == "mosaic" and not fc.portrait_mode then
                                fc.no_refresh_covers = true
                                fc:updateItems()
                            end
                        end,
                        close_callback = function()
                            if fc.nb_cols_landscape ~= nb_cols or fc.nb_rows_landscape ~= nb_rows then
                                BookInfoManager:saveSetting("nb_cols_landscape", fc.nb_cols_landscape)
                                BookInfoManager:saveSetting("nb_rows_landscape", fc.nb_rows_landscape)
                                FileChooser.nb_cols_landscape = fc.nb_cols_landscape
                                FileChooser.nb_rows_landscape = fc.nb_rows_landscape
                                if fc.display_mode_type == "mosaic" and not fc.portrait_mode then
                                    fc.no_refresh_covers = nil
                                    fc:updateItems()
                                end
                            end
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
            {
                text_func = function()
                    -- default files_per_page should be calculated by ListMenu on the first drawing,
                    -- use 10 if ListMenu has not been drawn yet
                    return T(_("Items per page in portrait list mode: %1"), fc.files_per_page or 10)
                end,
                callback = function()
                    local files_per_page = fc.files_per_page or 10
                    local SpinWidget = require("ui/widget/spinwidget")
                    local widget = SpinWidget:new{
                        title_text = _("Portrait list mode"),
                        value = files_per_page,
                        value_min = 4,
                        value_max = 20,
                        default_value = 10,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            fc.files_per_page = spin.value
                            if fc.display_mode_type == "list" then
                                fc.no_refresh_covers = true
                                fc:updateItems()
                            end
                        end,
                        close_callback = function()
                            if fc.files_per_page ~= files_per_page then
                                BookInfoManager:saveSetting("files_per_page", fc.files_per_page)
                                FileChooser.files_per_page = fc.files_per_page
                                if fc.display_mode_type == "list" then
                                    fc.no_refresh_covers = nil
                                    fc:updateItems()
                                end
                            end
                        end,
                    }
                    UIManager:show(widget)
                end,
                separator = true,
            },
            {
                text = _("Progress"),
                sub_item_table = {
                    {
                        text = _("Show progress in mosaic mode"),
                        checked_func = function() return BookInfoManager:getSetting("show_progress_in_mosaic") end,
                        callback = function()
                            BookInfoManager:toggleSetting("show_progress_in_mosaic")
                            fc:updateItems(1, true)
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show progress in detailed list mode"),
                        checked_func = function() return not BookInfoManager:getSetting("hide_page_info") end,
                        callback = function()
                            BookInfoManager:toggleSetting("hide_page_info")
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Show number of pages read instead of progress %"),
                        enabled_func = function() return not BookInfoManager:getSetting("hide_page_info") end,
                        checked_func = function() return BookInfoManager:getSetting("show_pages_read_as_progress") end,
                        callback = function()
                            BookInfoManager:toggleSetting("show_pages_read_as_progress")
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Show number of pages left to read"),
                        enabled_func = function() return not BookInfoManager:getSetting("hide_page_info") end,
                        checked_func = function() return BookInfoManager:getSetting("show_pages_left_in_progress") end,
                        callback = function()
                            BookInfoManager:toggleSetting("show_pages_left_in_progress")
                            fc:updateItems(1, true)
                        end,
                    },
                },
            },
            {
                text = _("Display hints"),
                sub_item_table = {
                    {
                        text = _("Show hint for books with description"),
                        checked_func = function() return not BookInfoManager:getSetting("no_hint_description") end,
                        callback = function()
                            BookInfoManager:toggleSetting("no_hint_description")
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Show hint for book status in history"),
                        checked_func = function() return BookInfoManager:getSetting("history_hint_opened") end,
                        callback = function()
                            BookInfoManager:toggleSetting("history_hint_opened")
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Show hint for book status in collections"),
                        checked_func = function() return BookInfoManager:getSetting("collections_hint_opened") end,
                        callback = function()
                            BookInfoManager:toggleSetting("collections_hint_opened")
                            fc:updateItems(1, true)
                        end,
                    }
                }
            },
            {
                text = _("Series"),
                sub_item_table = {
                    {
                        text = _("Append series metadata to authors"),
                        checked_func = function() return series_mode == "append_series_to_authors" end,
                        callback = function()
                            if series_mode == "append_series_to_authors" then
                                series_mode = nil
                            else
                                series_mode = "append_series_to_authors"
                            end
                            BookInfoManager:saveSetting("series_mode", series_mode)
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Append series metadata to title"),
                        checked_func = function() return series_mode == "append_series_to_title" end,
                        callback = function()
                            if series_mode == "append_series_to_title" then
                                series_mode = nil
                            else
                                series_mode = "append_series_to_title"
                            end
                            BookInfoManager:saveSetting("series_mode", series_mode)
                            fc:updateItems(1, true)
                        end,
                    },
                    {
                        text = _("Show series metadata in separate line"),
                        checked_func = function() return series_mode == "series_in_separate_line" end,
                        callback = function()
                            if series_mode == "series_in_separate_line" then
                                series_mode = nil
                            else
                                series_mode = "series_in_separate_line"
                            end
                            BookInfoManager:saveSetting("series_mode", series_mode)
                            fc:updateItems(1, true)
                        end,
                    },
                },
            },
            {
                text = _("Show file properties"),
                checked_func = function()
                    return not BookInfoManager:getSetting("hide_file_info")
                end,
                callback = function()
                    BookInfoManager:toggleSetting("hide_file_info")
                    fc:updateItems(1, true)
                end,
                separator = true,
            },
            {
                text = _("Book info cache management"),
                sub_item_table = {
                    {
                        text_func = function() -- add current db size to menu text
                            local sstr = BookInfoManager:getDbSize()
                            return _("Current cache size: ") .. sstr
                        end,
                        keep_menu_open = true,
                        callback = function() end, -- no callback, only for information
                    },
                    {
                        text = _("Prune cache of removed books"),
                        keep_menu_open = true,
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
                        keep_menu_open = true,
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
                        keep_menu_open = true,
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
    })
end

function CoverBrowser.initGrid(menu, display_mode)
    if menu == nil then return end
    if menu.nb_cols_portrait == nil then
        menu.nb_cols_portrait  = BookInfoManager:getSetting("nb_cols_portrait") or 3
        menu.nb_rows_portrait  = BookInfoManager:getSetting("nb_rows_portrait") or 3
        menu.nb_cols_landscape = BookInfoManager:getSetting("nb_cols_landscape") or 4
        menu.nb_rows_landscape = BookInfoManager:getSetting("nb_rows_landscape") or 2
        -- initial List mode files_per_page will be calculated and saved by ListMenu on the first drawing
        menu.files_per_page = BookInfoManager:getSetting("files_per_page")
    end
    menu.display_mode_type = display_mode and display_mode:gsub("_.*", "") -- "mosaic" or "list"
end

function CoverBrowser:refreshFileManagerInstance()
    local fc = self.ui.file_chooser
    if fc then
        if not filemanager_display_mode and fc.showFileDialog_orig then
            fc.showFileDialog = fc.showFileDialog_orig
            fc.showFileDialog_orig = nil
            fc.showFileDialog_ours = nil
        end
        fc:_recalculateDimen()
        fc:changeToPath(fc.path, fc.prev_focused_path)
    end
end

function CoverBrowser:setDisplayMode(display_mode)
    self:setupFileManagerDisplayMode(display_mode)
    if BookInfoManager:getSetting("unified_display_mode") then
        self:setupHistoryDisplayMode(display_mode)
        self:setupCollectionDisplayMode(display_mode)
    end
end

function CoverBrowser:setupFileManagerDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknown mode, fallback to classic
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

    -- init Mosaic and List grid dimensions (in Classic mode used in the settings menu)
    CoverBrowser.initGrid(FileChooser, display_mode)

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    if not display_mode then -- classic mode
        -- Put back original methods
        FileChooser.updateItems = _FileChooser_updateItems_orig
        FileChooser.onCloseWidget = _FileChooser_onCloseWidget_orig
        FileChooser._recalculateDimen = _FileChooser__recalculateDimen_orig
        FileManager.tapPlus = _FileManager_tapPlus_orig
        -- Also clean-up what we added, even if it does not bother original code
        FileChooser.updateCache = nil
        FileChooser._updateItemsBuildUI = nil
        FileChooser._do_cover_images = nil
        FileChooser._do_filename_only = nil
        FileChooser._do_hint_opened = nil
        FileChooser._do_center_partial_rows = nil
        self:refreshFileManagerInstance()
        return
    end

    -- In both mosaic and list modes, replace original methods with those from
    -- our generic CoverMenu
    local CoverMenu = require("covermenu")
    FileChooser.updateCache = CoverMenu.updateCache
    FileChooser.updateItems = CoverMenu.updateItems
    FileChooser.onCloseWidget = CoverMenu.onCloseWidget
    if FileChooser.display_mode_type == "mosaic" then
        -- Replace some other original methods with those from our MosaicMenu
        local MosaicMenu = require("mosaicmenu")
        FileChooser._recalculateDimen = MosaicMenu._recalculateDimen
        FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
        -- Set MosaicMenu behaviour:
        FileChooser._do_cover_images = display_mode ~= "mosaic_text"
        FileChooser._do_hint_opened = true -- dogear at bottom
        -- Don't have "../" centered in empty directories
        FileChooser._do_center_partial_rows = false
    elseif FileChooser.display_mode_type == "list" then
        -- Replace some other original methods with those from our ListMenu
        local ListMenu = require("listmenu")
        FileChooser._recalculateDimen = ListMenu._recalculateDimen
        FileChooser._updateItemsBuildUI = ListMenu._updateItemsBuildUI
        -- Set ListMenu behaviour:
        FileChooser._do_cover_images = display_mode ~= "list_only_meta"
        FileChooser._do_filename_only = display_mode == "list_image_filename"
        FileChooser._do_hint_opened = true -- dogear at bottom
    end

    -- Replace this FileManager method with the one from CoverMenu
    -- (but first, make the original method saved here as local available
    -- to CoverMenu)
    CoverMenu._FileManager_tapPlus_orig = _FileManager_tapPlus_orig
    FileManager.tapPlus = CoverMenu.tapPlus

    if init_done then
        self:refreshFileManagerInstance()
    else
        -- If KOReader has started directly to FileManager, the FileManager
        -- instance is being init()'ed and there is no FileManager.instance yet,
        -- but there'll be one at next tick.
        UIManager:nextTick(function()
            self:refreshFileManagerInstance()
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
        hist_menu.updateCache = CoverMenu.updateCache
        hist_menu.updateItems = CoverMenu.updateItems
        hist_menu.onCloseWidget = CoverMenu.onCloseWidget
        -- Also replace original onMenuHold (it will use original method, so remember it)
        hist_menu.onMenuHold_orig = hist_menu.onMenuHold
        hist_menu.onMenuHold = CoverMenu.onHistoryMenuHold

        CoverBrowser.initGrid(hist_menu, display_mode)
        if hist_menu.display_mode_type == "mosaic" then
            -- Replace some other original methods with those from our MosaicMenu
            local MosaicMenu = require("mosaicmenu")
            hist_menu._recalculateDimen = MosaicMenu._recalculateDimen
            hist_menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
            -- Set MosaicMenu behaviour:
            hist_menu._do_cover_images = display_mode ~= "mosaic_text"
            hist_menu._do_center_partial_rows = true -- nicer looking when few elements

        elseif hist_menu.display_mode_type == "list" then
            -- Replace some other original methods with those from our ListMenu
            local ListMenu = require("listmenu")
            hist_menu._recalculateDimen = ListMenu._recalculateDimen
            hist_menu._updateItemsBuildUI = ListMenu._updateItemsBuildUI
            -- Set ListMenu behaviour:
            hist_menu._do_cover_images = display_mode ~= "list_only_meta"
            hist_menu._do_filename_only = display_mode == "list_image_filename"

        end
        hist_menu._do_hint_opened = BookInfoManager:getSetting("history_hint_opened")
    end

    -- And do now what the original does
    _FileManagerHistory_updateItemTable_orig(self)
end

function CoverBrowser:setupHistoryDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknown mode, fallback to classic
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

local function _FileManagerCollections_updateItemTable(self)
    -- 'self' here is the single FileManagerCollections instance
    -- FileManagerCollections has just created a new instance of Menu as 'coll_menu'
    -- at each display of Collection/Favorites. Soon after instantiation, this method
    -- is called. The first time it is called, we replace some methods.
    local display_mode = self.display_mode
    local coll_menu = self.coll_menu

    if not coll_menu._coverbrowser_overridden then
        coll_menu._coverbrowser_overridden = true

        -- In both mosaic and list modes, replace original methods with those from
        -- our generic CoverMenu
        local CoverMenu = require("covermenu")
        coll_menu.updateCache = CoverMenu.updateCache
        coll_menu.updateItems = CoverMenu.updateItems
        coll_menu.onCloseWidget = CoverMenu.onCloseWidget
        -- Also replace original onMenuHold (it will use original method, so remember it)
        coll_menu.onMenuHold_orig = coll_menu.onMenuHold
        coll_menu.onMenuHold = CoverMenu.onCollectionsMenuHold

        CoverBrowser.initGrid(coll_menu, display_mode)
        if coll_menu.display_mode_type == "mosaic" then
            -- Replace some other original methods with those from our MosaicMenu
            local MosaicMenu = require("mosaicmenu")
            coll_menu._recalculateDimen = MosaicMenu._recalculateDimen
            coll_menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
            -- Set MosaicMenu behaviour:
            coll_menu._do_cover_images = display_mode ~= "mosaic_text"
            coll_menu._do_center_partial_rows = true -- nicer looking when few elements

        elseif coll_menu.display_mode_type == "list" then
            -- Replace some other original methods with those from our ListMenu
            local ListMenu = require("listmenu")
            coll_menu._recalculateDimen = ListMenu._recalculateDimen
            coll_menu._updateItemsBuildUI = ListMenu._updateItemsBuildUI
            -- Set ListMenu behaviour:
            coll_menu._do_cover_images = display_mode ~= "list_only_meta"
            coll_menu._do_filename_only = display_mode == "list_image_filename"

        end
        coll_menu._do_hint_opened = BookInfoManager:getSetting("collections_hint_opened")
    end

    -- And do now what the original does
    _FileManagerCollection_updateItemTable_orig(self)
end

function CoverBrowser:setupCollectionDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknown mode, fallback to classic
    end
    if init_done and display_mode == collection_display_mode then -- no change
        return
    end
    if init_done then -- save new mode in db
        BookInfoManager:saveSetting("collection_display_mode", display_mode)
    end
    -- remember current mode in module variable
    collection_display_mode = display_mode
    logger.dbg("CoverBrowser: setting Collection display mode to:", display_mode or "classic")

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    -- We only need to replace one FileManagerCollection method
    if not display_mode then -- classic mode
        -- Put back original methods
        FileManagerCollection.updateItemTable = _FileManagerCollection_updateItemTable_orig
        FileManagerCollection.display_mode = nil
    else
        -- Replace original method with the one defined above
        FileManagerCollection.updateItemTable = _FileManagerCollections_updateItemTable
        -- And let it know which display_mode we should use
        FileManagerCollection.display_mode = display_mode
    end
end

function CoverBrowser:getBookInfo(file)
    return BookInfoManager:getBookInfo(file)
end

function CoverBrowser:onInvalidateMetadataCache(file)
    BookInfoManager:deleteBookInfo(file)
    return true
end

function CoverBrowser:onDocSettingsItemsChanged(file, doc_settings)
    local status -- nil to wipe the covermenu book cache
    if doc_settings then
        status = doc_settings.summary and doc_settings.summary.status
        if not status then return end -- changes not for us
    end
    if filemanager_display_mode and self.ui.file_chooser then
        self.ui.file_chooser:updateCache(file, status)
    end
    if history_display_mode and self.ui.history and self.ui.history.hist_menu then
        self.ui.history.hist_menu:updateCache(file, status)
    end
    if collection_display_mode and self.ui.collections and self.ui.collections.coll_menu then
        self.ui.collections.coll_menu:updateCache(file, status)
    end
end

function CoverBrowser:extractBooksInDirectory(path)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        BookInfoManager:extractBooksInDirectory(path)
    end)
end

return CoverBrowser
