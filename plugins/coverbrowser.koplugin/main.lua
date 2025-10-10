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

local FileManager = require("apps/filemanager/filemanager")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")

local _modified_widgets = {
    filemanager  = FileManager,
    history      = FileManagerHistory,
    collections  = FileManagerCollection,
    filesearcher = FileManagerFileSearcher,
}
local _updateItemTable_orig_funcs = {
    history      = FileManagerHistory.updateItemTable,
    collections  = FileManagerCollection.updateItemTable,
    filesearcher = FileManagerFileSearcher.updateItemTable,
}

-- Available display modes
local DISPLAY_MODES = {
    -- nil or ""                -- classic : filename only
    mosaic_image        = true, -- 3x3 grid covers with images
    mosaic_text         = true, -- 3x3 grid covers text only
    list_image_meta     = true, -- image with metadata (title/authors)
    list_only_meta      = true, -- metadata with no image
    list_image_filename = true, -- image with filename (no metadata)
}
local display_mode_db_names = {
    filemanager  = "filemanager_display_mode",
    history      = "history_display_mode",
    collections  = "collection_display_mode",
}

-- Store some states as locals, to be permanent across instantiations
local init_done = false
local curr_display_modes = {
    filemanager  = false, -- not initialized yet
    history      = false, -- not initialized yet
    collections  = false, -- not initialized yet
}
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
    if not self.ui.document then -- FileManager menu only
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
    CoverBrowser.setupWidgetDisplayMode("history", true)
    CoverBrowser.setupWidgetDisplayMode("collections", true)
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
                return mode == curr_display_modes["filemanager"]
            end,
            radio = true,
            callback = function()
                self:setDisplayMode(mode)
            end,
        }
        history_sub_item_table[i] = {
            text = text,
            checked_func = function()
                return mode == curr_display_modes["history"]
            end,
            radio = true,
            callback = function()
                CoverBrowser.setupWidgetDisplayMode("history", mode)
            end,
        }
        collection_sub_item_table[i] = {
            text = text,
            checked_func = function()
                return mode == curr_display_modes["collections"]
            end,
            radio = true,
            callback = function()
                CoverBrowser.setupWidgetDisplayMode("collections", mode)
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
                CoverBrowser.setupWidgetDisplayMode("history", curr_display_modes["filemanager"])
                CoverBrowser.setupWidgetDisplayMode("collections", curr_display_modes["filemanager"])
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
    local function genSeriesSubMenuItem(item_text, item_series_mode)
        return {
            text = item_text,
            radio = true,
            checked_func = function()
                return series_mode == item_series_mode
            end,
            callback = function()
                if series_mode ~= item_series_mode then
                    series_mode = item_series_mode
                    BookInfoManager:saveSetting("series_mode", series_mode)
                    fc:updateItems(1, true)
                end
            end,
        }
    end

    table.insert (menu_items.filebrowser_settings.sub_item_table, 4, {
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
                    local DoubleSpinWidget = require("ui/widget/doublespinwidget")
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
                    local DoubleSpinWidget = require("ui/widget/doublespinwidget")
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
                separator = true,
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
            },
            {
                text = _("Shrink item font size to fit more text"),
                checked_func = function()
                    return not BookInfoManager:getSetting("fixed_item_font_size")
                end,
                callback = function()
                    BookInfoManager:toggleSetting("fixed_item_font_size")
                    fc:updateItems(1, true)
                end,
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
                        separator = true,
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
                    },
                },
            },
            {
                text = _("Series"),
                sub_item_table = {
                    genSeriesSubMenuItem(_("Do not show series metadata"), nil),
                    genSeriesSubMenuItem(_("Show series metadata in separate line"), "series_in_separate_line"),
                    genSeriesSubMenuItem(_("Append series metadata to title"), "append_series_to_title"),
                    genSeriesSubMenuItem(_("Append series metadata to authors"), "append_series_to_authors"),
                },
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
                                        UIManager:show(InfoMessage:new{ text = summary })
                                    end)
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Compact cache database"),
                        keep_menu_open = true,
                        callback = function()
                            local ConfirmBox = require("ui/widget/confirmbox")
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
                                        UIManager:show(InfoMessage:new{ text = summary })
                                    end)
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Delete cache database"),
                        keep_menu_open = true,
                        callback = function()
                            local ConfirmBox = require("ui/widget/confirmbox")
                            UIManager:show(ConfirmBox:new{
                                text = _("Are you sure that you want to delete cover and metadata cache?\n(This will also reset your display mode settings.)"),
                                ok_text = _("Purge"),
                                ok_callback = function()
                                    BookInfoManager:deleteDb()
                                end,
                            })
                        end,
                    },
                },
            },
        },
    })
end

function CoverBrowser:genExtractBookInfoButton(close_dialog_callback) -- for FileManager Plus dialog
    return curr_display_modes["filemanager"] and {
        {
            text = _("Extract and cache book information"),
            callback = function()
                close_dialog_callback()
                local fc = self.ui.file_chooser
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                    BookInfoManager:extractBooksInDirectory(fc.path, fc.cover_specs)
                end)
            end,
        },
    }
end

function CoverBrowser:genMultipleRefreshBookInfoButton(close_dialog_toggle_select_mode_callback, button_disabled)
    return curr_display_modes["filemanager"] and {
        {
            text = _("Refresh cached book information"),
            enabled = not button_disabled,
            callback = function()
                for file in pairs(self.ui.selected_files) do
                    BookInfoManager:deleteBookInfo(file)
                    self.ui.file_chooser.resetBookInfoCache(file)
                end
                close_dialog_toggle_select_mode_callback()
            end,
        },
    }
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

function CoverBrowser.addFileDialogButtons(widget_id)
    local widget = _modified_widgets[widget_id]
    FileManager.addFileDialogButtons(widget, "coverbrowser_1", function(file, is_file, bookinfo)
        if is_file then
            return bookinfo and {
                { -- Allow user to ignore some offending cover image
                    text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
                    enabled = bookinfo.has_cover and true or false,
                    callback = function()
                        BookInfoManager:setBookInfoProperties(file, {
                            ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                        })
                        widget.files_updated = true
                        local menu = widget.getMenuInstance()
                        UIManager:close(menu.file_dialog)
                        menu:updateItems(1, true)
                    end,
                },
                { -- Allow user to ignore some bad metadata (filename will be used instead)
                    text = bookinfo.ignore_meta and _("Unignore metadata") or _("Ignore metadata"),
                    enabled = bookinfo.has_meta and true or false,
                    callback = function()
                        BookInfoManager:setBookInfoProperties(file, {
                            ["ignore_meta"] = not bookinfo.ignore_meta and 'Y' or false,
                        })
                        widget.files_updated = true
                        local menu = widget.getMenuInstance()
                        UIManager:close(menu.file_dialog)
                        menu:updateItems(1, true)
                    end,
                },
            }
        end
    end)
    FileManager.addFileDialogButtons(widget, "coverbrowser_2", function(file, is_file, bookinfo)
        if is_file then
            return bookinfo and {
                { -- Allow a new extraction (multiple interruptions, book replaced)...
                    text = _("Refresh cached book information"),
                    callback = function()
                        BookInfoManager:deleteBookInfo(file)
                        widget.files_updated = true
                        local menu = widget.getMenuInstance()
                        menu.resetBookInfoCache(file)
                        UIManager:close(menu.file_dialog)
                        menu:updateItems(1, true)
                    end,
                },
            }
        end
    end)
end

function CoverBrowser.removeFileDialogButtons(widget_id)
    local widget = _modified_widgets[widget_id]
    FileManager.removeFileDialogButtons(widget, "coverbrowser_2")
    FileManager.removeFileDialogButtons(widget, "coverbrowser_1")
end

function CoverBrowser:refreshFileManagerInstance()
    local fc = self.ui.file_chooser
    if fc then
        fc:_recalculateDimen()
        fc:switchItemTable(nil, nil, fc.prev_itemnumber, { dummy = "" }) -- dummy itemmatch to draw focus
    end
end

function CoverBrowser:setDisplayMode(display_mode)
    self:setupFileManagerDisplayMode(display_mode)
    if BookInfoManager:getSetting("unified_display_mode") then
        CoverBrowser.setupWidgetDisplayMode("history", display_mode)
        CoverBrowser.setupWidgetDisplayMode("collections", display_mode)
    end
end

function CoverBrowser:setupFileManagerDisplayMode(display_mode)
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknown mode, fallback to classic
    end
    if init_done and display_mode == curr_display_modes["filemanager"] then -- no change
        return
    end
    if init_done then -- save new mode in db
        BookInfoManager:saveSetting(display_mode_db_names["filemanager"], display_mode)
    end
    -- remember current mode in module variable
    curr_display_modes["filemanager"] = display_mode
    logger.dbg("CoverBrowser: setting FileManager display mode to:", display_mode or "classic")

    -- init Mosaic and List grid dimensions (in Classic mode used in the settings menu)
    CoverBrowser.initGrid(FileChooser, display_mode)

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    if not display_mode then -- classic mode
        CoverBrowser.removeFileDialogButtons("filesearcher")
        _modified_widgets["filesearcher"].updateItemTable = _updateItemTable_orig_funcs["filesearcher"]
        -- Put back original methods
        FileChooser.updateItems = _FileChooser_updateItems_orig
        FileChooser.onCloseWidget = _FileChooser_onCloseWidget_orig
        FileChooser._recalculateDimen = _FileChooser__recalculateDimen_orig
        CoverBrowser.removeFileDialogButtons("filemanager")
        -- Also clean-up what we added, even if it does not bother original code
        FileChooser._updateItemsBuildUI = nil
        FileChooser._do_cover_images = nil
        FileChooser._do_filename_only = nil
        FileChooser._do_hint_opened = nil
        FileChooser._do_center_partial_rows = nil
        self:refreshFileManagerInstance()
        return
    end

    CoverBrowser.addFileDialogButtons("filesearcher")
    _modified_widgets["filesearcher"].updateItemTable = CoverBrowser.getUpdateItemTableFunc(display_mode)
    -- In both mosaic and list modes, replace original methods with those from
    -- our generic CoverMenu
    local CoverMenu = require("covermenu")
    FileChooser.updateItems = CoverMenu.updateItems
    FileChooser.onCloseWidget = CoverMenu.onCloseWidget
    CoverBrowser.addFileDialogButtons("filemanager")
    if FileChooser.display_mode_type == "mosaic" then
        -- Replace some other original methods with those from our MosaicMenu
        local MosaicMenu = require("mosaicmenu")
        FileChooser._recalculateDimen = MosaicMenu._recalculateDimen
        FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
        -- Set MosaicMenu behaviour:
        FileChooser._do_cover_images = display_mode ~= "mosaic_text"
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
    end
    FileChooser._do_hint_opened = true -- dogear at bottom

    if init_done then
        self:refreshFileManagerInstance()
    end
end

function CoverBrowser.setupWidgetDisplayMode(widget_id, display_mode)
    if display_mode == true then -- init
        display_mode = BookInfoManager:getSetting(display_mode_db_names[widget_id])
    end
    if not DISPLAY_MODES[display_mode] then
        display_mode = nil -- unknown mode, fallback to classic
    end
    if init_done and display_mode == curr_display_modes[widget_id] then -- no change
        return
    end
    if init_done then -- save new mode in db
        BookInfoManager:saveSetting(display_mode_db_names[widget_id], display_mode)
    end
    -- remember current mode in module variable
    curr_display_modes[widget_id] = display_mode
    logger.dbg("CoverBrowser: setting display mode:", widget_id, display_mode or "classic")

    if not init_done and not display_mode then
        return -- starting in classic mode, nothing to patch
    end

    -- We only need to replace one method
    local widget = _modified_widgets[widget_id]
    if display_mode then
        CoverBrowser.addFileDialogButtons(widget_id)
        widget.updateItemTable = CoverBrowser.getUpdateItemTableFunc(display_mode)
    else -- classic mode
        CoverBrowser.removeFileDialogButtons(widget_id)
        widget.updateItemTable = _updateItemTable_orig_funcs[widget_id]
    end
end

function CoverBrowser.getUpdateItemTableFunc(display_mode)
    return function(this, ...)
        -- 'this' here is the single widget instance
        -- The widget has just created a new instance of BookList as 'booklist_menu'
        -- at each display of the widget. Soon after instantiation, this method
        -- is called. The first time it is called, we replace some methods.
        local booklist_menu = this.booklist_menu
        local widget_id = booklist_menu.name

        if not booklist_menu._coverbrowser_overridden then
            booklist_menu._coverbrowser_overridden = true

            -- In both mosaic and list modes, replace original methods with those from
            -- our generic CoverMenu
            local CoverMenu = require("covermenu")
            booklist_menu.updateItems = CoverMenu.updateItems
            booklist_menu.onCloseWidget = CoverMenu.onCloseWidget

            CoverBrowser.initGrid(booklist_menu, display_mode)
            if booklist_menu.display_mode_type == "mosaic" then
                -- Replace some other original methods with those from our MosaicMenu
                local MosaicMenu = require("mosaicmenu")
                booklist_menu._recalculateDimen = MosaicMenu._recalculateDimen
                booklist_menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
                -- Set MosaicMenu behaviour:
                booklist_menu._do_cover_images = display_mode ~= "mosaic_text"
                booklist_menu._do_center_partial_rows = true -- nicer looking when few elements
            elseif booklist_menu.display_mode_type == "list" then
                -- Replace some other original methods with those from our ListMenu
                local ListMenu = require("listmenu")
                booklist_menu._recalculateDimen = ListMenu._recalculateDimen
                booklist_menu._updateItemsBuildUI = ListMenu._updateItemsBuildUI
                -- Set ListMenu behaviour:
                booklist_menu._do_cover_images = display_mode ~= "list_only_meta"
                booklist_menu._do_filename_only = display_mode == "list_image_filename"
            end

            if widget_id == "history" then
                booklist_menu._do_hint_opened = BookInfoManager:getSetting("history_hint_opened")
            elseif widget_id == "collections" then
                booklist_menu._do_hint_opened = BookInfoManager:getSetting("collections_hint_opened")
            else -- "filesearcher"
                booklist_menu._do_hint_opened = true
            end
        end

        -- And do now what the original does
        _updateItemTable_orig_funcs[widget_id](this, ...)
    end
end

function CoverBrowser:getBookInfo(file)
    return BookInfoManager:getBookInfo(file)
end

function CoverBrowser.getDocProps(file)
    return BookInfoManager:getDocProps(file)
end

function CoverBrowser:onInvalidateMetadataCache(file)
    BookInfoManager:deleteBookInfo(file)
    return true
end

function CoverBrowser:extractBooksInDirectory(path)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        BookInfoManager:extractBooksInDirectory(path)
    end)
end

return CoverBrowser
