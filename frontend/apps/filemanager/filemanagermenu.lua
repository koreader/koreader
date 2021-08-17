local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloudStorage = require("apps/cloudstorage/cloudstorage")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginLoader = require("pluginloader")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local dbg = require("dbg")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = FFIUtil.template

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
            icon = "appbar.filebrowser",
        },
        setting = {
            icon = "appbar.settings",
        },
        tools = {
            icon = "appbar.tools",
        },
        search = {
            icon = "appbar.search",
        },
        main = {
            icon = "appbar.menu",
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
            id = "filemanager_ext_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "filemanager_tap",
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
        {
            id = "filemanager_ext_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "filemanager_swipe",
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

    -- Only close menu if we were called from the menu
    if self.menu_container then
        -- Mimic's FileManager's onShowingReader refresh optimizations
        self.ui.tearing_down = true
        self.ui.dithered = nil
        self:onCloseFileManagerMenu()
    end

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)
end

function FileManagerMenu:setUpdateItemTable()

    -- setting tab
    self.menu_items.filebrowser_settings = {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Show hidden files"),
                checked_func = function() return self.ui.file_chooser.show_hidden end,
                callback = function() self.ui:toggleHiddenFiles() end,
            },
            {
                text = _("Show unsupported files"),
                checked_func = function() return self.ui.file_chooser.show_unsupported end,
                callback = function() self.ui:toggleUnsupportedFiles() end,
                separator = true,
            },
            {
                text = _("Classic mode settings"),
                sub_item_table = {
                    {
                        text = _("Items per page"),
                        help_text = _([[This sets the number of items per page in:
- File browser, history and favorites in 'classic' display mode
- Search results and folder shortcuts
- File and folder selection
- Calibre and OPDS browsers/search results]]),
                        callback = function()
                            local SpinWidget = require("ui/widget/spinwidget")
                            local Menu = require("ui/widget/menu")
                            local default_perpage = Menu.items_per_page_default
                            local curr_perpage = G_reader_settings:readSetting("items_per_page") or default_perpage
                            local items = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = curr_perpage,
                                value_min = 6,
                                value_max = 24,
                                default_value = default_perpage,
                                title_text =  _("Items per page"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    G_reader_settings:saveSetting("items_per_page", spin.value)
                                    self.ui:onRefresh()
                                end
                            }
                            UIManager:show(items)
                        end,
                    },
                    {
                        text = _("Item font size"),
                        callback = function()
                            local SpinWidget = require("ui/widget/spinwidget")
                            local Menu = require("ui/widget/menu")
                            local curr_perpage = G_reader_settings:readSetting("items_per_page") or Menu.items_per_page_default
                            local default_font_size = Menu.getItemFontSize(curr_perpage)
                            local curr_font_size = G_reader_settings:readSetting("items_font_size") or default_font_size
                            local items_font = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = curr_font_size,
                                value_min = 10,
                                value_max = 72,
                                default_value = default_font_size,
                                keep_shown_on_apply = true,
                                title_text =  _("Item font size"),
                                callback = function(spin)
                                    if spin.value == default_font_size then
                                        -- We can't know if the user has set a size or hit "Use default", but
                                        -- assume that if it is the default font size, he will prefer to have
                                        -- our default font size if he later updates per-page
                                        G_reader_settings:delSetting("items_font_size")
                                    else
                                        G_reader_settings:saveSetting("items_font_size", spin.value)
                                    end
                                    self.ui:onRefresh()
                                end
                            }
                            UIManager:show(items_font)
                        end,
                    },
                    {
                        text = _("Shrink item font size to fit more text"),
                        checked_func = function()
                            return G_reader_settings:isTrue("items_multilines_show_more_text")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("items_multilines_show_more_text")
                            self.ui:onRefresh()
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show opened files in bold"),
                        checked_func = function()
                            return G_reader_settings:readSetting("show_file_in_bold") == "opened"
                        end,
                        callback = function()
                            if G_reader_settings:readSetting("show_file_in_bold") == "opened" then
                                G_reader_settings:saveSetting("show_file_in_bold", false)
                            else
                                G_reader_settings:saveSetting("show_file_in_bold", "opened")
                            end
                            self.ui:onRefresh()
                        end,
                    },
                    {
                        text = _("Show new (not yet opened) files in bold"),
                        checked_func = function()
                            return G_reader_settings:hasNot("show_file_in_bold")
                        end,
                        callback = function()
                            if G_reader_settings:hasNot("show_file_in_bold") then
                                G_reader_settings:saveSetting("show_file_in_bold", false)
                            else
                                G_reader_settings:delSetting("show_file_in_bold")
                            end
                            self.ui:onRefresh()
                        end,
                    },
                },
            },
            {
                text = _("History settings"),
                sub_item_table = {
                    {
                        text = _("Clear history of deleted files"),
                        callback = function()
                            UIManager:show(ConfirmBox:new{
                                text = _("Clear history of deleted files?"),
                                ok_text = _("Clear"),
                                ok_callback = function()
                                    require("readhistory"):clearMissing()
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Auto-remove deleted or purged items from history"),
                        checked_func = function()
                            return G_reader_settings:isTrue("autoremove_deleted_items_from_history")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("autoremove_deleted_items_from_history")
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show filename in Open last/previous menu items"),
                        checked_func = function()
                            return G_reader_settings:isTrue("open_last_menu_show_filename")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("open_last_menu_show_filename")
                        end,
                    },
                },
            },
            {
                text = _("Home folder settings"),
                sub_item_table = {
                    {
                        text = _("Set home folder"),
                        callback = function()
                            local text
                            local home_dir = G_reader_settings:readSetting("home_dir")
                            if home_dir then
                                text = T(_("Home folder is set to:\n%1"), home_dir)
                            else
                                text = _("Home folder is not set.")
                                home_dir = Device.home_dir
                            end
                            UIManager:show(ConfirmBox:new{
                                text = text .. "\nChoose new folder to set as home?",
                                ok_text = _("Choose folder"),
                                ok_callback = function()
                                    local path_chooser = require("ui/widget/pathchooser"):new{
                                        select_file = false,
                                        show_files = false,
                                        path = home_dir,
                                        onConfirm = function(new_path)
                                            G_reader_settings:saveSetting("home_dir", new_path)
                                        end
                                    }
                                    UIManager:show(path_chooser)
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Shorten home folder"),
                        checked_func = function()
                            return G_reader_settings:nilOrTrue("shorten_home_dir")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrTrue("shorten_home_dir")
                            local FileManager = require("apps/filemanager/filemanager")
                            if FileManager.instance then FileManager.instance:reinit() end
                        end,
                        help_text = _([[
"Shorten home folder" will display the home folder itself as "Home" instead of its full path.

Assuming the home folder is:
`/mnt/onboard/.books`
A subfolder will be shortened from:
`/mnt/onboard/.books/Manga/Cells at Work`
To:
`Manga/Cells at Work`.]]),
                    },
                    {
                        text = _("Lock home folder"),
                        enabled_func = function()
                            return G_reader_settings:has("home_dir")
                        end,
                        checked_func = function()
                            return G_reader_settings:isTrue("lock_home_folder")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("lock_home_folder")
                            self.ui:onRefresh()
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Info lists items per page"),
                help_text = _([[This sets the number of items per page in:
- Book information
- Dictionary and Wikipedia lookup history
- Reading statistics details
- A few other plugins]]),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local KeyValuePage = require("ui/widget/keyvaluepage")
                    local default_perpage = KeyValuePage:getDefaultKeyValuesPerPage()
                    local curr_perpage = G_reader_settings:readSetting("keyvalues_per_page") or default_perpage
                    local items = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = curr_perpage,
                        value_min = 10,
                        value_max = 24,
                        default_value = default_perpage,
                        title_text =  _("Info lists items per page"),
                        callback = function(spin)
                            if spin.value == default_perpage then
                                -- We can't know if the user has set a value or hit "Use default", but
                                -- assume that if it is the default, he will prefer to stay with our
                                -- default if he later changes screen DPI
                                G_reader_settings:delSetting("keyvalues_per_page")
                            else
                                G_reader_settings:saveSetting("keyvalues_per_page", spin.value)
                            end
                        end
                    }
                    UIManager:show(items)
                end,
            },
        }
    }

    for _, widget in pairs(self.registered_widgets) do
        local ok, err = pcall(widget.addToMainMenu, widget, self.menu_items)
        if not ok then
            logger.err("failed to register widget", widget.name, err)
        end
    end

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

    self.menu_items.developer_options = {
        text = _("Developer options"),
        sub_item_table = {
            {
                text = _("Clear caches"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear the cache folder?"),
                        ok_callback = function()
                            local DataStorage = require("datastorage")
                            local cachedir = DataStorage:getDataDir() .. "/cache"
                            if lfs.attributes(cachedir, "mode") == "directory" then
                                FFIUtil.purgeDir(cachedir)
                            end
                            lfs.mkdir(cachedir)
                            -- Also remove from the Cache objet references to the cache files we've just deleted
                            local Cache = require("cache")
                            Cache.cached = {}
                            local InfoMessage = require("ui/widget/infomessage")
                            UIManager:show(InfoMessage:new{
                                text = _("Caches cleared. Please restart KOReader."),
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
                        G_reader_settings:makeFalse("debug_verbose")
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
    if Device:isKobo() and not Device:isSunxi() then
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
    --- @note Currently, only Kobo, rM & PB have a fancy crash display (#5328)
    if Device:isKobo() or Device:isRemarkable() or Device:isPocketBook() then
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
        local Blitbuffer = require("ffi/blitbuffer")
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable C blitter"),
            enabled_func = function()
                return Blitbuffer.has_cblitbuffer
            end,
            checked_func = function()
                return G_reader_settings:isTrue("dev_no_c_blitter")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_no_c_blitter")
                Blitbuffer:enableCBB(G_reader_settings:nilOrFalse("dev_no_c_blitter"))
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
                Device.screen:toggleHWDithering()
                G_reader_settings:saveSetting("dev_no_hw_dither", not Device.screen.hw_dithering)
                -- Make sure SW dithering gets disabled when we enable HW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    G_reader_settings:makeTrue("dev_no_sw_dither")
                    Device.screen:toggleSWDithering(false)
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
                Device.screen:toggleSWDithering()
                G_reader_settings:saveSetting("dev_no_sw_dither", not Device.screen.sw_dithering)
                -- Make sure HW dithering gets disabled when we enable SW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    G_reader_settings:makeTrue("dev_no_hw_dither")
                    Device.screen:toggleHWDithering(false)
                end
                UIManager:setDirty("all", "full")
            end,
        })
    end
    --- @note: Currently, only Kobo implements this quirk
    if Device:hasEinkScreen() and Device:isKobo() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- @translators Highly technical (ioctl is a Linux API call, the uppercase stuff is a constant). What's translatable is essentially only the action ("bypass") and the article.
            text = _("Bypass the WAIT_FOR ioctls"),
            checked_func = function()
                local mxcfb_bypass_wait_for
                if G_reader_settings:has("mxcfb_bypass_wait_for") then
                    mxcfb_bypass_wait_for = G_reader_settings:isTrue("mxcfb_bypass_wait_for")
                else
                    mxcfb_bypass_wait_for = not Device:hasReliableMxcWaitFor()
                end
                return mxcfb_bypass_wait_for
            end,
            callback = function()
                local mxcfb_bypass_wait_for
                if G_reader_settings:has("mxcfb_bypass_wait_for") then
                    mxcfb_bypass_wait_for = G_reader_settings:isTrue("mxcfb_bypass_wait_for")
                else
                    mxcfb_bypass_wait_for = not Device:hasReliableMxcWaitFor()
                end
                G_reader_settings:saveSetting("mxcfb_bypass_wait_for", not mxcfb_bypass_wait_for)
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        })
    end
    --- @note: Intended to debug/investigate B288 quirks on PocketBook devices
    if Device:hasEinkScreen() and Device:isPocketBook() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- @translators B288 is the codename of the CPU/chipset (SoC stands for 'System on Chip').
            text = _("Ignore feature bans on B288 SoCs"),
            enabled_func = function()
                return Device:isB288SoC()
            end,
            checked_func = function()
                return G_reader_settings:isTrue("pb_ignore_b288_quirks")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("pb_ignore_b288_quirks")
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
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
        text = _("UI layout mirroring and text direction"),
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
        text = _("File search"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self.ui:handleEvent(Event:new("ShowFileSearch"))
        end
    }

    -- main menu tab
    self.menu_items.open_last_document = {
        text_func = function()
            if not G_reader_settings:isTrue("open_last_menu_show_filename") or G_reader_settings:hasNot("lastfile") then
                return _("Open last document")
            end
            local last_file = G_reader_settings:readSetting("lastfile")
            local path, file_name = util.splitFilePathName(last_file) -- luacheck: no unused
            return T(_("Last: %1"), BD.filename(file_name))
        end,
        enabled_func = function()
            return G_reader_settings:has("lastfile")
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
        -- add a shortcut on non touch-device
        -- because this menu is not accessible otherwise
        self.menu_items.plus_menu = {
            icon = "plus",
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

function FileManagerMenu:exitOrRestart(callback, force)
    UIManager:close(self.menu_container)

    -- Only restart sets a callback, which suits us just fine for this check ;)
    if callback and not force and not Device:isStartupScriptUpToDate() then
        UIManager:show(ConfirmBox:new{
            text = _("KOReader's startup script has been updated. You'll need to completely exit KOReader to finalize the update."),
            ok_text = _("Restart anyway"),
            ok_callback = function()
                self:exitOrRestart(callback, true)
            end,
        })
        return
    end

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
            width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
            show_parent = menu_container,
        }
    end

    main_menu.close_callback = function()
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
