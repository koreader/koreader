local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Device = require("device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local DEBUG = require("dbg")
local _ = require("gettext")
local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local Search = require("apps/filemanager/filemanagersearch")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    registered_widgets = {},
}

function FileManagerMenu:init()
    local filemanager = self.ui
    self.tab_item_table = {
        setting = {
            icon = "resources/icons/appbar.settings.png",
        },
        info = {
            icon = "resources/icons/appbar.pokeball.png",
        },
        tools = {
            icon = "resources/icons/appbar.tools.png",
        },
        search = {
            icon = "resources/icons/appbar.magnify.browse.png",
        },
        home = {
            icon = "resources/icons/appbar.home.png",
            callback = function()
                if settings_changed then
                    settings_changed = false
                    UIManager:show(ConfirmBox:new{
                        text = _("You have unsaved default settings. Save them now?"),
                        ok_callback = function()
                            SetDefaults:SaveSettings()
                        end,
                    })
                else
                    UIManager:close(self.menu_container)
                    self.ui:onClose()
                end
            end,
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
        widget:addToMainMenu(self.tab_item_table)
    end

    -- setting tab
    table.insert(self.tab_item_table.setting, {
        text = _("Show hidden files"),
        checked_func = function() return self.ui.file_chooser.show_hidden end,
        callback = function() self.ui:toggleHiddenFiles() end
    })
    local FileManager = require("apps/filemanager/filemanager")
    table.insert(self.tab_item_table.setting, self.ui:getSortingMenuTable())
    table.insert(self.tab_item_table.setting, {
        text = _("Reverse sorting"),
        checked_func = function() return self.ui.file_chooser.reverse_collate end,
        callback = function() self.ui:toggleReverseCollate() end
    })
    table.insert(self.tab_item_table.setting, {
        text = _("Start with last opened file"),
        checked_func = function() return G_reader_settings:readSetting("open_last") end,
        enabled_func = function() return G_reader_settings:readSetting("lastfile") ~= nil end,
        callback = function()
            local open_last = G_reader_settings:readSetting("open_last") or false
            G_reader_settings:saveSetting("open_last", not open_last)
        end
    })
    -- insert common settings
    for i, common_setting in ipairs(require("ui/elements/common_settings_menu_table")) do
        table.insert(self.tab_item_table.setting, common_setting)
    end

    -- info tab
    -- insert common info
    for i, common_setting in ipairs(require("ui/elements/common_info_menu_table")) do
        table.insert(self.tab_item_table.info, common_setting)
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
            function OPDSCatalog:onExit()
                DEBUG("refresh filemanager")
                filemanager:onRefresh()
            end
            OPDSCatalog:showCatalog()
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

    -- home tab
    table.insert(self.tab_item_table.home, {
        text = _("Exit"),
        callback = function()
            UIManager:close(self.menu_container)
            self.ui:onClose()
        end
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

    local main_menu = nil
    if Device:isTouchDevice() then
        local TouchMenu = require("ui/widget/touchmenu")
        main_menu = TouchMenu:new{
            width = Screen:getWidth(),
            last_index = tab_index,
            tab_item_table = {
                self.tab_item_table.setting,
                self.tab_item_table.info,
                self.tab_item_table.tools,
                self.tab_item_table.search,
                self.tab_item_table.home,
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
    DEBUG("remember menu tab index", last_tab_index)
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
