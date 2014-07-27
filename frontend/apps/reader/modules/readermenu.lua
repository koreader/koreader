local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TouchMenu = require("ui/widget/touchmenu")
local GestureRange = require("ui/gesturerange")
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
        home = {
            icon = "resources/icons/appbar.home.png",
            callback = function()
                self.ui:handleEvent(Event:new("RestoreScreenMode",
                    G_reader_settings:readSetting("screen_mode") or "portrait"))
                UIManager:close(self.menu_container)
                self.ui:onClose()
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
    table.insert(self.tab_item_table.setting, {
        text = _("Night mode"),
        checked_func = function() return G_reader_settings:readSetting("night_mode") end,
        callback = function()
            local night_mode = G_reader_settings:readSetting("night_mode") or false
            Screen.bb:invert()
            G_reader_settings:saveSetting("night_mode", not night_mode)
        end
    })
    table.insert(self.tab_item_table.setting, {
        text = _("Font size"),
        sub_item_table = {
            {
                text = _("Auto"),
                checked_func = function()
                    local dpi = G_reader_settings:readSetting("screen_dpi")
                    return dpi == nil
                end,
                callback = function() Screen:setDPI() end
            },
            {
                text = _("Small"),
                checked_func = function()
                    local dpi = G_reader_settings:readSetting("screen_dpi")
                    return dpi and dpi <= 140
                end,
                callback = function() Screen:setDPI(120) end
            },
            {
                text = _("Medium"),
                checked_func = function()
                    local dpi = G_reader_settings:readSetting("screen_dpi")
                    return dpi and dpi > 140 and dpi <= 200
                end,
                callback = function() Screen:setDPI(160) end
            },
            {
                text = _("Large"),
                checked_func = function()
                    local dpi = G_reader_settings:readSetting("screen_dpi")
                    return dpi and dpi > 200
                end,
                callback = function() Screen:setDPI(240) end
            },
        }
    })
    table.insert(self.tab_item_table.setting, self:genRefreshRateMenu())
    table.insert(self.tab_item_table.setting, {
        text = _("Show advanced options"),
        checked_func = function() return G_reader_settings:readSetting("show_advanced") end,
        callback = function()
            local show_advanced = G_reader_settings:readSetting("show_advanced") or false
            G_reader_settings:saveSetting("show_advanced", not show_advanced)
        end
    })
    table.insert(self.tab_item_table.setting, Language:getLangMenuTable())

    -- info tab
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

function ReaderMenu:genRefreshRateMenu()
    local custom_1 = function() return G_reader_settings:readSetting("refresh_rate_1") or 12 end
    local custom_2 = function() return G_reader_settings:readSetting("refresh_rate_2") or 22 end
    local custom_3 = function() return G_reader_settings:readSetting("refresh_rate_3") or 99 end
    return {
        text = _("E-ink full refresh rate"),
        sub_item_table = {
            {
                text = _("Every page"),
                checked_func = function() return UIManager:getRefreshRate() == 1 end,
                callback = function() UIManager:setRefreshRate(1) end,
            },
            {
                text = _("Every 6 pages"),
                checked_func = function() return UIManager:getRefreshRate() == 6 end,
                callback = function() UIManager:setRefreshRate(6) end,
            },
            {
                text_func = function() return _("Custom ") .. "1: " .. custom_1() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_1() end,
                callback = function() UIManager:setRefreshRate(custom_1()) end,
                hold_callback = function() self:makeCustomRateDialog("refresh_rate_1") end,
            },
            {
                text_func = function() return _("Custom ") .. "2: " .. custom_2() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_2() end,
                callback = function() UIManager:setRefreshRate(custom_2()) end,
                hold_callback = function() self:makeCustomRateDialog("refresh_rate_2") end,
            },
            {
                text_func = function() return _("Custom ") .. "3: " .. custom_3() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_3() end,
                callback = function() UIManager:setRefreshRate(custom_3()) end,
                hold_callback = function() self:makeCustomRateDialog("refresh_rate_3") end,
            },
        }
    }
end

function ReaderMenu:makeCustomRate(custom_rate)
    local number = tonumber(self.custom_dialog:getInputText())
    G_reader_settings:saveSetting(custom_rate, number)
end

function ReaderMenu:makeCustomRateDialog(custom_rate)
    self.custom_dialog = InputDialog:new{
        title = _("Input page number for a full refresh"),
        input_hint = "(1 - 99)",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeMakeCustomDialog()
                    end,
                },
                {
                    text = _("OK"),
                    callback = function()
                        self:makeCustomRate(custom_rate)
                        self:closeMakeCustomDialog()
                    end,
                },
            },
        },
        input_type = "number",
        enter_callback = function()
            self:makeCustomRate(custom_rate)
            self:closeMakeCustomDialog()
        end,
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.custom_dialog:onShowKeyboard()
    UIManager:show(self.custom_dialog)
end

function ReaderMenu:closeMakeCustomDialog()
    self.custom_dialog:onClose()
    UIManager:close(self.custom_dialog)
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
