local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local GestureRange = require("ui/gesturerange")
local InputDialog = require("ui/widget/inputdialog")
local Geom = require("ui/geometry")
local Device = require("device")
local Screensaver = require("ui/screensaver")
local Screen = Device.screen
local _ = require("gettext")
local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local Search = require("apps/filemanager/filemanagersearch")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local CloudStorage = require("apps/cloudstorage/cloudstorage")

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    registered_widgets = nil,
}

function FileManagerMenu:init()
    self.tab_item_table = {
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
    -- For backward compatibility, plugins look for plugins tab, which should be tools tab in file
    -- manager.
    self.tab_item_table.plugins = self.tab_item_table.tools
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
        widget:addToMainMenu(self.tab_item_table)
    end

    -- setting tab
    table.insert(self.tab_item_table.setting, {
        text = _("Show hidden files"),
        checked_func = function() return self.ui.file_chooser.show_hidden end,
        callback = function() self.ui:toggleHiddenFiles() end
    })
    table.insert(self.tab_item_table.setting, self.ui:getSortingMenuTable())
    table.insert(self.tab_item_table.setting, {
        text = _("Reverse sorting"),
        checked_func = function() return self.ui.file_chooser.reverse_collate end,
        callback = function() self.ui:toggleReverseCollate() end
    })
    table.insert(self.tab_item_table.setting, {
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
    })
    if Device.isKobo() then
        table.insert(self.tab_item_table.setting, {
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
        })
    end
    -- insert common settings
    for i, common_setting in ipairs(require("ui/elements/common_settings_menu_table")) do
        table.insert(self.tab_item_table.setting, common_setting)
    end

    -- tools tab
    table.insert(self.tab_item_table.tools, {
        text = _("Advanced settings"),
        callback = function()
            SetDefaults:ConfirmEdit()
        end,
        hold_callback = function()
            SetDefaults:ConfirmSave()
        end,
    })
    table.insert(self.tab_item_table.tools, {
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
    })
    table.insert(self.tab_item_table.tools, {
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
    })
    table.insert(self.tab_item_table.tools, {
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
    })

    -- search tab
    table.insert(self.tab_item_table.search, {
        text = _("Find a book in calibre catalog"),
        callback = function()
            Search:getCalibre()
            Search:ShowSearch()
        end
    })
    table.insert(self.tab_item_table.search, {
        text = _("Find a file"),
        callback = function()
            FileSearcher:init(self.ui.file_chooser.path)
        end
    })

    -- main menu tab
    -- insert common info
    table.insert(self.tab_item_table.main, {
        text = _("Open last document"),
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
    })
    for i, common_setting in ipairs(require("ui/elements/common_info_menu_table")) do
        table.insert(self.tab_item_table.main, common_setting)
    end
    table.insert(self.tab_item_table.main, {
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
    })
end

function FileManagerMenu:onShowMenu()
    local tab_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
    if #self.tab_item_table.setting == 0 then
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
            tab_item_table = {
                self.tab_item_table.setting,
                self.tab_item_table.tools,
                self.tab_item_table.search,
                self.tab_item_table.main,
            },
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
