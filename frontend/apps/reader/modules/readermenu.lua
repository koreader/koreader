local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local TouchMenu = require("ui/widget/touchmenu")
local GestureRange = require("ui/gesturerange")
local OTAManager = require("ui/otamanager")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Screen = require("ui/screen")
local Menu = require("ui/widget/menu")
local Language = require("ui/language")
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
            callback = function()
                self.ui:handleEvent(Event:new("RestoreScreenMode",
                    G_reader_settings:readSetting("screen_mode") or "portrait"))
                self.ui:onClose()
                UIManager:quit()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showFiles()
            end,
        },
        home = {
            icon = "resources/icons/appbar.home.png",
            callback = function()
                self.ui:handleEvent(Event:new("RestoreScreenMode",
                    G_reader_settings:readSetting("screen_mode") or "portrait"))
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

    -- setting tab
    -- FIXME: it's curious that if this 'Screen' menu is placed after the Language
    -- menu submenu in 'Screen' won't be shown. Probably a bug in the touchmenu module.
    table.insert(self.tab_item_table.setting, {
        text = _("Screen settings"),
        sub_item_table = {
            Screen:getDPIMenuTable(),
            UIManager:getRefreshMenuTable(),
        },
    })
    table.insert(self.tab_item_table.setting, {
        text = _("Night mode"),
        checked_func = function() return G_reader_settings:readSetting("night_mode") end,
        callback = function()
            local night_mode = G_reader_settings:readSetting("night_mode") or false
            Screen.bb:invert()
            G_reader_settings:saveSetting("night_mode", not night_mode)
        end
    })
    table.insert(self.tab_item_table.setting, Language:getLangMenuTable())
    table.insert(self.tab_item_table.setting, {
        text = _("Show advanced options"),
        checked_func = function() return G_reader_settings:readSetting("show_advanced") end,
        callback = function()
            local show_advanced = G_reader_settings:readSetting("show_advanced") or false
            G_reader_settings:saveSetting("show_advanced", not show_advanced)
        end
    })

    -- info tab
    if Device:isKindle() or Device:isKobo() then
        table.insert(self.tab_item_table.info, OTAManager:getOTAMenuTable())
    end
    table.insert(self.tab_item_table.info, {
        text = _("Version"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = io.open("git-rev", "r"):read(),
            })
        end
    })
    table.insert(self.tab_item_table.info, {
        text = _("Help"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Please report bugs to \nhttps://github.com/koreader/koreader/issues"),
            })
        end
    })
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
        main_menu = TouchMenu:new{
            width = Screen:getWidth(),
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
        main_menu = Menu:new{
            title = _("Document menu"),
            item_table = {},
            width = Screen:getWidth() - 100,
        }

        for _,item_table in pairs(self.tab_item_table) do
            for k,v in ipairs(item_table) do
                table.insert(main_menu.item_table, v)
            end
        end
    end

    main_menu.close_callback = function ()
        UIManager:close(menu_container)
    end

    menu_container[1] = main_menu
    -- maintain a reference to menu_container
    self.menu_container = menu_container
    UIManager:show(menu_container)

    return true
end

function ReaderMenu:onCloseReaderMenu()
    UIManager:close(self.menu_container)
    return true
end

function ReaderMenu:onTapShowMenu()
    self.ui:handleEvent(Event:new("ShowConfigMenu"))
    self.ui:handleEvent(Event:new("ShowReaderMenu"))
    return true
end

function ReaderMenu:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderMenu:onSaveSettings()
end

function ReaderMenu:registerToMainMenu(widget)
    table.insert(self.registered_widgets, widget)
end

return ReaderMenu
