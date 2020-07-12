local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloudStorage = require("apps/cloudstorage/cloudstorage")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginLoader = require("pluginloader")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local dbg = require("dbg")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    menu_items = {},
    registered_widgets = nil,
}

function FileManagerMenu:init()
    self.menu_items = {
        ["KOMenu:menu_buttons"] = {
            -- top menu
        },
        -- items in top menu
        filemanager_settings = {
            icon = "resources/icons/appbar.cabinet.files.png",
        },
        setting = {
            icon = "resources/icons/appbar.settings.png",
        },
        tools = {
            icon = "resources/icons/appbar.tools.png",
        },
        search = {
            icon = "resources/icons/appbar.magnify.browse.png",
        },
        main = {
            icon = "resources/icons/menu-icon.png",
        },
    }

    self.registered_widgets = {}

    if Device:hasKeys() then
        self.key_events = {
            ShowMenu = { { "Menu" }, doc = "show menu" },
        }
    end
    self.activation_menu = G_reader_settings:readSetting("activate_menu")
    if self.activation_menu == nil then
        self.activation_menu = "swipe_tap"
    end
end

function FileManagerMenu:initGesListener()
    if not Device:isTouchDevice() then return end

    self:registerTouchZones({
        {
            id = "filemanager_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            handler = function(ges) return self:onTapShowMenu(ges) end,
        },
        {
            id = "filemanager_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
    })
end

function FileManagerMenu:onOpenLastDoc()
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("Cannot open last document"),
        })
        return
    end
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)

    -- only close menu if we were called from the menu
    if self.menu_container then
        self:onCloseFileManagerMenu()
    end

    local FileManager = require("apps/filemanager/filemanager")
    FileManager.instance:onClose()
end

function FileManagerMenu:setUpdateItemTable()
    for _, widget in pairs(self.registered_widgets) do
        local ok, err = pcall(widget.addToMainMenu, widget, self.menu_items)
        if not ok then
            logger.err("failed to register widget", widget.name, err)
        end
    end

    -- setting tab
    self.menu_items.show_hidden_files = {
        text = _("Show hidden files"),
        checked_func = function() return self.ui.file_chooser.show_hidden end,
        callback = function() self.ui:toggleHiddenFiles() end
    }
    self.menu_items.show_unsupported_files = {
        text = _("Show unsupported files"),
        checked_func = function() return self.ui.file_chooser.show_unsupported end,
        callback = function() self.ui:toggleUnsupportedFiles() end
    }
    self.menu_items.items = {
        text = _("Items"),
        sub_item_table = {
            {
                text = _("Items per page"),
                help_text = _([[This sets the number of items per page in:
- File browser and history in 'classic' display mode
- File and directory selection
- Table of contents
- Bookmarks list]]),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local curr_items = G_reader_settings:readSetting("items_per_page") or 14
                    local items = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = curr_items,
                        value_min = 6,
                        value_max = 24,
                        title_text =  _("Items per page"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            G_reader_settings:saveSetting("items_per_page", spin.value)
                            self.ui:onRefresh()
                        end
                    }
                    UIManager:show(items)
                end
            },
            {
                text = _("Font size"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local curr_items = G_reader_settings:readSetting("items_per_page") or 14
                    local default_font_size = math.floor(24 - ((curr_items - 6)/ 18) * 10 )
                    local curr_font_size = G_reader_settings:readSetting("items_font_size") or default_font_size
                    local items_font = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = curr_font_size,
                        value_min = 10,
                        value_max = 72,
                        default_value = default_font_size,
                        keep_shown_on_apply = true,
                        title_text =  _("Maximum font size for item"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("items_font_size", spin.value)
                            self.ui:onRefresh()
                        end
                    }
                    UIManager:show(items_font)
                end
            },
            {
                text = _("Reduce font size to show more text"),
                keep_menu_open = true,
                checked_func = function()
                    return G_reader_settings:isTrue("items_multilines_show_more_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("items_multilines_show_more_text")
                end
            }
        }
    }
    self.menu_items.sort_by = self.ui:getSortingMenuTable()
    self.menu_items.reverse_sorting = {
        text = _("Reverse sorting"),
        checked_func = function() return self.ui.file_chooser.reverse_collate end,
        callback = function() self.ui:toggleReverseCollate() end
    }
    self.menu_items.start_with = self.ui:getStartWithMenuTable()
    if Device:supportsScreensaver() then
        self.menu_items.screensaver = {
            text = _("Screensaver"),
            sub_item_table = require("ui/elements/screensaver_menu"),
        }
    end
    -- insert common settings
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_settings_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end

    -- tools tab
    self.menu_items.advanced_settings = {
        text = _("Advanced settings"),
        callback = function()
            SetDefaults:ConfirmEdit()
        end,
        hold_callback = function()
            SetDefaults:ConfirmSave()
        end,
    }
    self.menu_items.plugin_management = {
        text = _("Plugin management"),
        sub_item_table = PluginLoader:genPluginManagerSubItem()
    }

    self.menu_items.opds_catalog = {
        text = _("OPDS catalog"),
        callback = function()
            local OPDSCatalog = require("apps/opdscatalog/opdscatalog")
            local filemanagerRefresh = function() self.ui:onRefresh() end
            function OPDSCatalog:onClose()
                filemanagerRefresh()
                UIManager:close(self)
            end
            OPDSCatalog:showCatalog()
        end,
    }
    self.menu_items.developer_options = {
        text = _("Developer options"),
        sub_item_table = {
            {
                text = _("Clear readers' caches"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear cache/ and cr3cache/ ?"),
                        ok_callback = function()
                            local purgeDir = require("ffi/util").purgeDir
                            local DataStorage = require("datastorage")
                            local cachedir = DataStorage:getDataDir() .. "/cache"
                            if lfs.attributes(cachedir, "mode") == "directory" then
                                purgeDir(cachedir)
                            end
                            lfs.mkdir(cachedir)
                            -- Also remove from Cache objet references to
                            -- the cache files we just deleted
                            local Cache = require("cache")
                            Cache.cached = {}
                            local InfoMessage = require("ui/widget/infomessage")
                            UIManager:show(InfoMessage:new{
                                text = _("Caches cleared. Please exit and restart KOReader."),
                            })
                        end,
                    })
                end,
            },
            {
                text = _("Enable debug logging"),
                checked_func = function()
                    return G_reader_settings:isTrue("debug")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("debug")
                    if G_reader_settings:isTrue("debug") then
                        dbg:turnOn()
                    else
                        dbg:setVerbose(false)
                        dbg:turnOff()
                        G_reader_settings:flipFalse("debug_verbose")
                    end
                end,
            },
            {
                text = _("Enable verbose debug logging"),
                enabled_func = function()
                    return G_reader_settings:isTrue("debug")
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("debug_verbose")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("debug_verbose")
                    if G_reader_settings:isTrue("debug_verbose") then
                        dbg:setVerbose(true)
                    else
                        dbg:setVerbose(false)
                    end
                end,
            },
        }
    }
    if Device:isKobo() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable forced 8-bit pixel depth"),
            checked_func = function()
                return G_reader_settings:isTrue("dev_startup_no_fbdepth")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_startup_no_fbdepth")
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        })
    end
    --- @note Currently, only Kobo has a fancy crash display (#5328)
    if Device:isKobo() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Always abort on crash"),
            checked_func = function()
                return G_reader_settings:isTrue("dev_abort_on_crash")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_abort_on_crash")
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        })
    end
    if not Device.should_restrict_JIT then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable C blitter"),
            enabled_func = function()
                return lfs.attributes("libs/libblitbuffer.so", "mode") == "file"
            end,
            checked_func = function()
                return G_reader_settings:isTrue("dev_no_c_blitter")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_no_c_blitter")
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        })
    end
    if Device:hasEinkScreen() and Device:canHWDither() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable HW dithering"),
            checked_func = function()
                return not Device.screen.hw_dithering
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_no_hw_dither")
                Device.screen:toggleHWDithering()
                -- Make sure SW dithering gets disabled when we enable HW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    Device.screen:toggleSWDithering()
                end
                UIManager:setDirty("all", "full")
            end,
        })
    end
    if Device:hasEinkScreen() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable SW dithering"),
            enabled_func = function()
                return Device.screen.fb_bpp == 8
            end,
            checked_func = function()
                return not Device.screen.sw_dithering
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_no_sw_dither")
                Device.screen:toggleSWDithering()
                -- Make sure HW dithering gets disabled when we enable SW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    Device.screen:toggleHWDithering()
                end
                UIManager:setDirty("all", "full")
            end,
        })
    end
    if Device:isAndroid() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Start E-ink test"),
            callback = function()
                Device:epdTest()
            end,
        })
    end

    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("Disable enhanced UI text shaping (xtext)"),
        checked_func = function()
            return G_reader_settings:isFalse("use_xtext")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("use_xtext")
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart."),
            })
        end,
    })
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = "UI layout mirroring and text direction",
        sub_item_table = {
            {
                text = _("Reverse UI layout mirroring"),
                checked_func = function()
                    return G_reader_settings:isTrue("dev_reverse_ui_layout_mirroring")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("dev_reverse_ui_layout_mirroring")
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = _("This will take effect on next restart."),
                    })
                end
            },
            {
                text = _("Reverse UI text direction"),
                checked_func = function()
                    return G_reader_settings:isTrue("dev_reverse_ui_text_direction")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("dev_reverse_ui_text_direction")
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = _("This will take effect on next restart."),
                    })
                end
            }
        }
    })
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text_func = function()
            if G_reader_settings:nilOrTrue("use_cre_call_cache")
                    and G_reader_settings:isTrue("use_cre_call_cache_log_stats") then
                return _("Enable CRE call cache (with stats)")
            end
            return _("Enable CRE call cache")
        end,
        checked_func = function()
            return G_reader_settings:nilOrTrue("use_cre_call_cache")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("use_cre_call_cache")
            -- No need to show "This will take effect on next CRE book opening."
            -- as this menu is only accessible from file browser
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("use_cre_call_cache_log_stats")
            touchmenu_instance:updateItems()
        end,
    })

    self.menu_items.cloud_storage = {
        text = _("Cloud storage"),
        callback = function()
            local cloud_storage = CloudStorage:new{}
            UIManager:show(cloud_storage)
            local filemanagerRefresh = function() self.ui:onRefresh() end
            function cloud_storage:onClose()
                filemanagerRefresh()
                UIManager:close(cloud_storage)
            end
        end,
    }

    self.menu_items.find_file = {
        -- @translators Search for files by name.
        text = _("Find a file"),
        callback = function()
            self.ui:handleEvent(Event:new("ShowFileSearch"))
        end
    }

    -- main menu tab
    self.menu_items.open_last_document = {
        text_func = function()
            if not G_reader_settings:isTrue("open_last_menu_show_filename") or not G_reader_settings:readSetting("lastfile") then
                return _("Open last document")
            end
            local last_file = G_reader_settings:readSetting("lastfile")
            local path, file_name = util.splitFilePathName(last_file); -- luacheck: no unused
            return T(_("Last: %1"), BD.filename(file_name))
        end,
        enabled_func = function()
            return G_reader_settings:readSetting("lastfile") ~= nil
        end,
        callback = function()
            self:onOpenLastDoc()
        end,
        hold_callback = function()
            local last_file = G_reader_settings:readSetting("lastfile")
            UIManager:show(ConfirmBox:new{
                text = T(_("Would you like to open the last document: %1?"), BD.filepath(last_file)),
                ok_text = _("OK"),
                ok_callback = function()
                    self:onOpenLastDoc()
                end,
            })
        end
    }
    -- insert common info
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_info_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end
    self.menu_items.exit_menu = {
        text = _("Exit"),
        hold_callback = function()
            self:exitOrRestart()
        end,
    }
    self.menu_items.exit = {
        text = _("Exit"),
        callback = function()
            self:exitOrRestart()
        end,
    }
    self.menu_items.restart_koreader = {
        text = _("Restart KOReader"),
        callback = function()
            self:exitOrRestart(function()
                UIManager:restartKOReader()
            end)
        end,
    }
    if not Device:canRestart() then
        self.menu_items.exit_menu = self.menu_items.exit
        self.menu_items.exit = nil
        self.menu_items.restart_koreader = nil
    end
    if not Device:isTouchDevice() then
        --add a shortcut on non touch-device
        --because this menu is not accessible otherwise
        self.menu_items.plus_menu = {
            icon = "resources/icons/appbar.plus.png",
            remember = false,
            callback = function()
                self:onCloseFileManagerMenu()
                self.ui:tapPlus()
            end,
        }
    end

    local order = require("ui/elements/filemanager_menu_order")

    local MenuSorter = require("ui/menusorter")
    self.tab_item_table = MenuSorter:mergeAndSort("filemanager", self.menu_items, order)
end
dbg:guard(FileManagerMenu, 'setUpdateItemTable',
    function(self)
        local mock_menu_items = {}
        for _, widget in pairs(self.registered_widgets) do
            -- make sure addToMainMenu works in debug mode
            widget:addToMainMenu(mock_menu_items)
        end
    end)

function FileManagerMenu:exitOrRestart(callback)
    UIManager:close(self.menu_container)
    self.ui:onClose()
    if callback then
        callback()
    end
end

function FileManagerMenu:onShowMenu(tab_index)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end

    if not tab_index then
        tab_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
    end

    local menu_container = CenterContainer:new{
        ignore = "height",
        dimen = Screen:getSize(),
    }

    local main_menu
    if Device:isTouchDevice() or Device:hasDPad() then
        local TouchMenu = require("ui/widget/touchmenu")
        main_menu = TouchMenu:new{
            width = Screen:getWidth(),
            last_index = tab_index,
            tab_item_table = self.tab_item_table,
            show_parent = menu_container,
        }
    else
        local Menu = require("ui/widget/menu")
        main_menu = Menu:new{
            title = _("File manager menu"),
            item_table = Menu.itemTableFromTouchMenu(self.tab_item_table),
            width = Screen:getWidth()-10,
            show_parent = menu_container,
        }
    end

    main_menu.close_callback = function ()
        self:onCloseFileManagerMenu()
    end

    menu_container[1] = main_menu
    -- maintain a reference to menu_container
    self.menu_container = menu_container
    UIManager:show(menu_container)
    return true
end

function FileManagerMenu:onCloseFileManagerMenu()
    local last_tab_index = self.menu_container[1].last_index
    G_reader_settings:saveSetting("filemanagermenu_tab_index", last_tab_index)
    UIManager:close(self.menu_container)
    return true
end

function FileManagerMenu:_getTabIndexFromLocation(ges)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end
    local last_tab_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
    if not ges then
        return last_tab_index
    -- if the start position is far right
    elseif ges.pos.x > 2 * Screen:getWidth() / 3 then
        return BD.mirroredUILayout() and 1 or #self.tab_item_table
    -- if the start position is far left
    elseif ges.pos.x < Screen:getWidth() / 3 then
        return BD.mirroredUILayout() and #self.tab_item_table or 1
    -- if center return the last index
    else
        return last_tab_index
    end
end

function FileManagerMenu:onTapShowMenu(ges)
    if self.activation_menu ~= "swipe" then
        self:onShowMenu(self:_getTabIndexFromLocation(ges))
        return true
    end
end

function FileManagerMenu:onSwipeShowMenu(ges)
    if self.activation_menu ~= "tap" and ges.direction == "south" then
        self:onShowMenu(self:_getTabIndexFromLocation(ges))
        return true
    end
end

function FileManagerMenu:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function FileManagerMenu:registerToMainMenu(widget)
    table.insert(self.registered_widgets, widget)
end

return FileManagerMenu
