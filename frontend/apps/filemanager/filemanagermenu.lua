local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local TouchMenu = require("ui/widget/touchmenu")
local InfoMessage = require("ui/widget/infomessage")
local OTAManager = require("ui/otamanager")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Language = require("ui/language")
local _ = require("gettext")
local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    registered_widgets = {},
}

function FileManagerMenu:init()
    self.tab_item_table = {
        setting = {
            icon = "resources/icons/appbar.settings.png",
        },
        info = {
            icon = "resources/icons/appbar.pokeball.png",
        },
        home = {
            icon = "resources/icons/appbar.home.png",
            callback = function()
                UIManager:close(self.menu_container)
                self.ui:onClose()
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
        callback = function()
            self.ui:toggleHiddenFiles()
        end
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

    if Device:hasFrontlight() then
        ReaderFrontLight:addToMainMenu(self.tab_item_table)
    end

    table.insert(self.tab_item_table.setting, {
        text = _("Night mode"),
        checked_func = function() return G_reader_settings:readSetting("night_mode") end,
        callback = function()
            local night_mode = G_reader_settings:readSetting("night_mode") or false
            Screen.bb:invert()
            G_reader_settings:saveSetting("night_mode", not night_mode)
        end
    })

    table.insert(self.tab_item_table.setting, Screen:getDPIMenuTable())
    table.insert(self.tab_item_table.setting, UIManager:getRefreshMenuTable())
    table.insert(self.tab_item_table.setting, Language:getLangMenuTable())

    -- info tab
    table.insert(self.tab_item_table.info, OTAManager:getOTAMenuTable())
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

function FileManagerMenu:onShowMenu()
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
                self.tab_item_table.setting,
                self.tab_item_table.info,
                self.tab_item_table.home,
            },
            show_parent = menu_container,
        }
    else
        main_menu = Menu:new{
            title = _("File manager menu"),
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
