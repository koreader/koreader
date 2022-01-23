local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template

local ActionShortcuts = WidgetContainer:new{
    name = "actionshortcuts",
    actionshortcuts_file = DataStorage:getSettingsDir() .. "/actionshortcuts.lua",
    actionshortcuts = nil,
    data = nil,
    updated = false,
}

function ActionShortcuts:onDispatcherRegisterActions()
    Dispatcher:registerAction("actionshortcuts", {category="none", event="ShowActionShortcuts", title=_("Action Shortcuts"), general=true, separator=true})
end

function ActionShortcuts:init()
    Dispatcher:init()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function ActionShortcuts:loadActionShortcuts()
    if self.actionshortcuts then
        return
    end
    self.actionshortcuts = LuaSettings:open(self.actionshortcuts_file)
    self.data = self.actionshortcuts.data
end

function ActionShortcuts:onFlushSettings()
    if self.actionshortcuts and self.updated then
        self.actionshortcuts:flush()
        self.updated = false
    end
end

function ActionShortcuts:addToMainMenu(menu_items)
    menu_items.actionshortcuts = {
        text = _("ActionShortcuts"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function ActionShortcuts:getSubMenuItems()
    self:loadActionShortcuts()
    local sub_item_table = {
        {
            text = _("New"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local name_input
                name_input = InputDialog:new{
                    title =  _("Enter actionshortcut name"),
                    input = "",
                    buttons = {{
                        {
                            text = _("Cancel"),
                            callback = function()
                                UIManager:close(name_input)
                            end,
                        },
                        {
                            text = _("Save"),
                            callback = function()
                                local name = name_input:getInputText()
                                if not self:newProfile(name) then
                                    UIManager:show(InfoMessage:new{
                                        text =  T(_("There is already a actionshortcut called: %1"), name),
                                    })
                                    return
                                end
                                UIManager:close(name_input)
                                touchmenu_instance.item_table = self:getSubMenuItems()
                                touchmenu_instance.page = 1
                                touchmenu_instance:updateItems()
                            end,
                        },
                    }},
                }
                UIManager:show(name_input)
                name_input:onShowKeyboard()
            end,
            separator = true,
        }
    }
    for k,v in FFIUtil.orderedPairs(self.data) do
        local sub_items = {
            {
                text = _("Delete actionshortcut"),
                keep_menu_open = false,
                separator = true,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Do you want to delete this actionshortcut?"),
                        ok_text = _("Yes"),
                        cancel_text = _("No"),
                        ok_callback = function()
                            self:deleteProfile(k)
                        end,
                    })
                end,
            },
        }
        Dispatcher:addSubMenu(self, sub_items, self.data, k)
        table.insert(sub_item_table, {
            text = k,
            hold_keep_menu_open = false,
            sub_item_table = sub_items,
            hold_callback = function()
                Dispatcher:execute(self.data[k])
            end,
        })
    end
    return sub_item_table
end

function ActionShortcuts:newProfile(name)
    if self.data[name] == nil then
        self.data[name] = {}
        self.updated = true
        return true
    else
        return false
    end
end

function ActionShortcuts:deleteProfile(name)
    self.data[name] = nil
    self.updated = true
end

function ActionShortcuts:onShowActionShortcuts()
    self:loadActionShortcuts()
    if UIManager:getTopWidget() == "actionshortcuts" then return end
    local quickmenu
    local buttons = {}

    for k,v in FFIUtil.orderedPairs(self.data) do
        table.insert(buttons, {{
            text = k,
            callback = function()
                UIManager:close(quickmenu)
                Dispatcher:execute(self.data[k])
            end,
        }})
    end

    quickmenu = ButtonDialogTitle:new{
        name = "actionshortcuts",
        title = _("ActionShortcuts"),
        buttons = buttons,
    }
    UIManager:show(quickmenu)
end

return ActionShortcuts
