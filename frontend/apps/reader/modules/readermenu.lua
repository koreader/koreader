local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Screen = require("device").screen
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderMenu = InputContainer:new{
    tab_item_table = nil,
    registered_widgets = {},
}

function ReaderMenu:init()
    self.tab_item_table = {
        setting = {
            icon = "resources/icons/appbar.settings.png",
        },
        navi = {
            icon = "resources/icons/appbar.page.corner.bookmark.png",
        },
        info = {
            icon = "resources/icons/appbar.pokeball.png",
        },
        typeset = {
            icon = "resources/icons/appbar.page.text.png",
        },
        plugins = {
            icon = "resources/icons/appbar.tools.png",
        },
        filemanager = {
            icon = "resources/icons/appbar.cabinet.files.png",
            remember = false,
            callback = function()
                self:onTapCloseMenu()
                self.ui:onClose()
                -- screen orientation is independent for docview and filemanager
                -- so we need to restore the screen mode for the filemanager
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:restoreScreenMode()
                if not FileManager.is_running then
                    local lastdir = nil
                    local last_file = G_reader_settings:readSetting("lastfile")
                    if last_file then
                        lastdir = last_file:match("(.*)/")
                    end
                    FileManager:showFiles(lastdir)
                end
            end,
        },
        home = {
            icon = "resources/icons/appbar.home.png",
            remember = false,
            callback = function()
                self:onTapCloseMenu()
                self.ui:onClose()
                UIManager:quit()
            end,
        },
    }
    self.registered_widgets = {}

    if Device:hasKeys() then
        self.key_events = {
            ShowReaderMenu = { { "Menu" }, doc = "show menu" },
            Close = { { "Back" }, doc = "close menu" },
        }
    end
end

function ReaderMenu:initGesListener()
    self.ges_events = {
        TapShowMenu = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_MENU.x,
                    y = Screen:getHeight()*DTAP_ZONE_MENU.y,
                    w = Screen:getWidth()*DTAP_ZONE_MENU.w,
                    h = Screen:getHeight()*DTAP_ZONE_MENU.h
                }
            }
        },
    }
end

function ReaderMenu:setUpdateItemTable()
    for _, widget in pairs(self.registered_widgets) do
        widget:addToMainMenu(self.tab_item_table)
    end

    -- settings tab
    -- insert common settings
    for i, common_setting in ipairs(require("ui/elements/common_settings_menu_table")) do
        table.insert(self.tab_item_table.setting, common_setting)
    end
    -- insert DjVu render mode submenu just before the last entry (show advanced)
    -- this is a bit of a hack
    if self.ui.document.is_djvu then
        table.insert(
            self.tab_item_table.setting,
            #self.tab_item_table.setting,
            self.view:getRenderModeMenuTable())
    end

    -- info tab
    -- insert common info
    for i, common_setting in ipairs(require("ui/elements/common_info_menu_table")) do
        table.insert(self.tab_item_table.info, common_setting)
    end

    if Device:isKobo() and KOBO_SCREEN_SAVER_LAST_BOOK then
        local excluded = function()
            return self.ui.doc_settings:readSetting("exclude_screensaver") or false
        end
        local proportional = function()
            return self.ui.doc_settings:readSetting("proportional_screensaver") or false
        end
        table.insert(self.tab_item_table.typeset, {
            text = _("Screensaver"),
            sub_item_table = {
                {
                    text = _("Use this book's cover as screensaver"),
                    checked_func = function() return not excluded() end,
                    callback = function()
                        self.ui.doc_settings:saveSetting("exclude_screensaver", not excluded())
                        self.ui:saveSettings()
                    end
                },
                {
                    text = _("Display proportional cover image in screensaver"),
                    checked_func = function() return proportional() end,
                    callback = function()
                        self.ui.doc_settings:saveSetting("proportional_screensaver", not proportional())
                        self.ui:saveSettings()
                    end
                }
            }
        })
    end
end

function ReaderMenu:onShowReaderMenu()
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
            last_index = self.last_tab_index,
            tab_item_table = {
                self.tab_item_table.navi,
                self.tab_item_table.typeset,
                self.tab_item_table.setting,
                self.tab_item_table.info,
                self.tab_item_table.plugins,
                self.tab_item_table.filemanager,
                self.tab_item_table.home,
            },
            show_parent = menu_container,
        }
    else
        local Menu = require("ui/widget/menu")
        main_menu = Menu:new{
            title = _("Document menu"),
            item_table = Menu.itemTableFromTouchMenu(self.tab_item_table),
            width = Screen:getWidth() - 100,
            show_parent = menu_container,
        }
    end

    main_menu.close_callback = function ()
        self.ui:handleEvent(Event:new("CloseReaderMenu"))
    end

    main_menu.touch_menu_callback = function ()
        self.ui:handleEvent(Event:new("CloseConfigMenu"))
    end

    menu_container[1] = main_menu
    -- maintain a reference to menu_container
    self.menu_container = menu_container
    UIManager:show(menu_container)

    return true
end

function ReaderMenu:onCloseReaderMenu()
    self.last_tab_index = self.menu_container[1].last_index
    DEBUG("remember menu tab index", self.last_tab_index)
    self:onSaveSettings()
    UIManager:close(self.menu_container)
    return true
end

function ReaderMenu:onTapShowMenu()
    self.ui:handleEvent(Event:new("ShowConfigMenu"))
    self.ui:handleEvent(Event:new("ShowReaderMenu"))
    return true
end

function ReaderMenu:onTapCloseMenu()
    self.ui:handleEvent(Event:new("CloseReaderMenu"))
    self.ui:handleEvent(Event:new("CloseConfigMenu"))
end

function ReaderMenu:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderMenu:onReadSettings(config)
    self.last_tab_index = config:readSetting("readermenu_tab_index") or 1
end

function ReaderMenu:onSaveSettings()
    self.ui.doc_settings:saveSetting("readermenu_tab_index", self.last_tab_index)
end

function ReaderMenu:registerToMainMenu(widget)
    table.insert(self.registered_widgets, widget)
end

return ReaderMenu
