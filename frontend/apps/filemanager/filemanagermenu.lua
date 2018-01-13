local CenterContainer = require("ui/widget/container/centercontainer")
local CloudStorage = require("apps/cloudstorage/cloudstorage")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local InputContainer = require("ui/widget/container/inputcontainer")
local Search = require("apps/filemanager/filemanagersearch")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local dbg = require("dbg")
local logger = require("logger")
local _ = require("gettext")

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
            overrides = { "rolling_swipe", "paging_swipe", },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
    })
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
    self.menu_items.items_per_page = {
        text = _("Items per page"),
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("items_per_page") or 14
            local items = SpinWidget:new{
                width = Screen:getWidth() * 0.6,
                value = curr_items,
                value_min = 6,
                value_max = 24,
                ok_text = _("Set items"),
                title_text =  _("Items per page"),
                callback = function(spin)
                    G_reader_settings:saveSetting("items_per_page", spin.value)
                    self.ui:onRefresh()
                end
            }
            UIManager:show(items)
        end
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
    for id, common_setting in pairs(require("ui/elements/common_settings_menu_table")) do
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
        }
    }
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

    -- search tab
    self.menu_items.find_book_in_calibre_catalog = {
        text = _("Find a book in calibre catalog"),
        callback = function()
            Search:getCalibre()
            Search:ShowSearch()
        end
    }
    self.menu_items.find_file = {
        text = _("Find a file"),
        callback = function()
            FileSearcher:init(self.ui.file_chooser.path)
        end
    }

    -- main menu tab
    self.menu_items.open_last_document = {
        text = _("Open last document"),
        enabled_func = function()
            return G_reader_settings:readSetting("lastfile") ~= nil
        end,
        callback = function()
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
            self:onCloseFileManagerMenu()
        end
    }
    -- insert common info
    for id, common_setting in pairs(require("ui/elements/common_info_menu_table")) do
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
            self:exitOrRestart(function() UIManager:restartKOReader() end)
        end,
    }

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
    if SetDefaults.settings_changed then
        UIManager:show(ConfirmBox:new{
            text = _("You have unsaved default settings. Save them now?\nTap \"Cancel\" to return to KOReader."),
            ok_text = _("Save"),
            ok_callback = function()
              SetDefaults.settings_changed = false
              SetDefaults:saveSettings()
              self:exitOrRestart(callback)
            end,
            cancel_text = _("Don't save"),
            cancel_callback = function()
                SetDefaults.settings_changed = false
                self:exitOrRestart(callback)
            end,
            other_buttons = {{
              text = _("Cancel"),
            }}
        })
    else
        UIManager:close(self.menu_container)
        self.ui:onClose()
        if callback then
            callback()
        end
    end
end

function FileManagerMenu:onShowMenu()
    local tab_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end

    local menu_container = CenterContainer:new{
        ignore = "height",
        dimen = Screen:getSize(),
    }

    local main_menu
    if Device:isTouchDevice() then
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

function FileManagerMenu:onTapShowMenu(ges)
    if self.activation_menu ~= "swipe" then
        self:onShowMenu()
        return true
    end
end

function FileManagerMenu:onSwipeShowMenu(ges)
    if self.activation_menu ~= "tap" and ges.direction == "south" then
        self:onShowMenu()
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
