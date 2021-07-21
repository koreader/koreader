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

local Profiles = WidgetContainer:new{
    name = "profiles",
    profiles_file = DataStorage:getSettingsDir() .. "/profiles.lua",
    profiles = nil,
    data = nil,
    updated = false,
}

function Profiles:init()
    Dispatcher:init()
    self.ui.menu:registerToMainMenu(self)
end

function Profiles:loadProfiles()
    if self.profiles then
        return
    end
    self.profiles = LuaSettings:open(self.profiles_file)
    self.data = self.profiles.data
end

function Profiles:onFlushSettings()
    if self.profiles and self.updated then
        self.profiles:flush()
        self.updated = false
    end
end

function Profiles:addToMainMenu(menu_items)
    menu_items.profiles = {
        text = _("Profiles"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function Profiles:getSubMenuItems()
    self:loadProfiles()
    local sub_item_table = {
        {
            text = _("New"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local name_input
                name_input = InputDialog:new{
                    title =  _("Enter profile name"),
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
                                        text =  T(_("There is already a profile called: %1"), name),
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
                text = _("Delete profile"),
                keep_menu_open = false,
                separator = true,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Do you want to delete this profile?"),
                        ok_text = _("Yes"),
                        cancel_text = _("No"),
                        ok_callback = function()
                            self:deleteProfile(k)
                        end,
                    })
                end,
            }
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

function Profiles:newProfile(name)
    if self.data[name] == nil then
        self.data[name] = {}
        self.updated = true
        return true
    else
        return false
    end
end

function Profiles:deleteProfile(name)
    self.data[name] = nil
    self.updated = true
end

return Profiles
