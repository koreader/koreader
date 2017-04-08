local CenterContainer = require("ui/widget/container/centercontainer")
local CloudStorage = require("apps/cloudstorage/cloudstorage")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Screensaver = require("ui/screensaver")
local Search = require("apps/filemanager/filemanagersearch")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

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
end

function FileManagerMenu:initGesListener()
    self.ges_events = {
        TapShowMenu = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0,
                    y = 0,
                    w = Screen:getWidth()*3/4,
                    h = Screen:getHeight()/4,
                }
            }
        },
    }
end

function FileManagerMenu:setUpdateItemTable()
    for _, widget in pairs(self.registered_widgets) do
        widget:addToMainMenu(self.menu_items)
    end

    -- setting tab
    self.menu_items.show_hidden_files = {
        text = _("Show hidden files"),
        checked_func = function() return self.ui.file_chooser.show_hidden end,
        callback = function() self.ui:toggleHiddenFiles() end
    }
    self.menu_items.sort_by = self.ui:getSortingMenuTable()
    self.menu_items.reverse_sorting = {
        text = _("Reverse sorting"),
        checked_func = function() return self.ui.file_chooser.reverse_collate end,
        callback = function() self.ui:toggleReverseCollate() end
    }
    self.menu_items.start_with_last_opened_file = {
        text = _("Start with last opened file"),
        checked_func = function() return
            G_reader_settings:readSetting("open_last")
        end,
        enabled_func = function() return
            G_reader_settings:readSetting("lastfile") ~= nil
        end,
        callback = function()
            local open_last = G_reader_settings:readSetting("open_last") or false
            G_reader_settings:saveSetting("open_last", not open_last)
            G_reader_settings:flush()
        end
    }
    if Device.isKobo() or Device.isKindle() then
        self.menu_items.screensaver = {
            text = _("Screensaver"),
            sub_item_table = {
                {
                    text = _("Use last book's cover as screensaver"),
                    checked_func = Screensaver.isUsingBookCover,
                    callback = function()
                        if Screensaver:isUsingBookCover() then
                            G_reader_settings:saveSetting(
                                "use_lastfile_as_screensaver", false)
                        else
                            G_reader_settings:delSetting(
                                "use_lastfile_as_screensaver")
                        end
                        G_reader_settings:flush()
                    end
                },
                {
                    text = _("Screensaver folder"),
                    callback = function()
                        local ss_folder_path_input
                        local function save_folder_path()
                            G_reader_settings:saveSetting(
                                "screensaver_folder", ss_folder_path_input:getInputText())
                            G_reader_settings:flush()
                            UIManager:close(ss_folder_path_input)
                        end
                        local curr_path = G_reader_settings:readSetting("screensaver_folder")
                        ss_folder_path_input = InputDialog:new{
                            title = _("Screensaver folder"),
                            input = curr_path,
                            input_hint = "/mnt/onboard/screensaver",
                            input_type = "text",
                            buttons = {
                                {
                                    {
                                        text = _("Cancel"),
                                        callback = function()
                                            UIManager:close(ss_folder_path_input)
                                        end,
                                    },
                                    {
                                        text = _("Save"),
                                        is_enter_default = true,
                                        callback = save_folder_path,
                                    },
                                }
                            },
                        }
                        ss_folder_path_input:onShowKeyboard()
                        UIManager:show(ss_folder_path_input)
                    end,
                },
            }
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
    self.menu_items.exit = {
        text = _("Exit"),
        callback = function()
            if SetDefaults.settings_changed then
                SetDefaults.settings_changed = false
                UIManager:show(ConfirmBox:new{
                    text = _("You have unsaved default settings. Save them now?"),
                    ok_callback = function()
                        SetDefaults:saveSettings()
                    end,
                })
            else
                UIManager:close(self.menu_container)
                self.ui:onClose()
            end
        end,
    }

    local order = require("ui/elements/filemanager_menu_order")

    local MenuSorter = require("frontend/ui/menusorter")
    self.tab_item_table = MenuSorter:mergeAndSort("filemanager", self.menu_items, order)
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

function FileManagerMenu:onTapShowMenu()
    self:onShowMenu()
    return true
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
