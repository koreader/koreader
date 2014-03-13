local CenterContainer = require("ui/widget/container/centercontainer")
local TouchMenu = require("ui/widget/touchmenu")
local ReaderFrontLight = require("ui/reader/readerfrontlight")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Language = require("ui/language")
local _ = require("gettext")

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    registered_widgets = {},
}

function FileManagerMenu:init()
    self.tab_item_table = {
        main = {
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

    if Device:hasKeyboard() then
        self.key_events = {
            ShowMenu = { { "Menu" }, doc = _("show menu") },
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

    table.insert(self.tab_item_table.main, {
        text = _("Toggle hidden files"),
        callback = function()
            self.ui:toggleHiddenFiles()
        end
    })

    if Device:hasFrontlight() then
        ReaderFrontLight:addToMainMenu(self.tab_item_table)
    end

    table.insert(self.tab_item_table.main, {
        text = _("Help"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Please report bugs to https://github.com/koreader/ koreader/issues, Click at the bottom of the page for more options"),
            })
        end
    })
    table.insert(self.tab_item_table.main, {
        text = _("Version"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = io.open("git-rev", "r"):read(),
            })
        end
    })
    table.insert(self.tab_item_table.main, Language:getLangMenuTable())
end

function FileManagerMenu:onShowMenu()
    if #self.tab_item_table.main == 0 then
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
                self.tab_item_table.main,
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
