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

local autostart_profile = "00_Autostart" -- gets stored as first element
local autostart_done = false

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
--[[    table.insert(self.ui.postReaderCallback, function()
            self:executeAutostart()
    end)]]
    self:executeAutostart()
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
                                if name == autostart_profile then
                                    UIManager:show(InfoMessage:new{
                                        text =  T(_("Reserved name cannot be used: %1"), autostart_profile),
                                    })
                                    return
                                elseif not self:newProfile(name) then
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
        if k ~= autostart_profile then
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
                },
                {
                    text = _("Autostart"),
                    help_text = _("Execute this profile when KOReader is started with 'file browser' or 'last file'."),
                    keep_menu_open = true,
                    checked_func = function()
                        return self:isAutostartProfile(k)
                    end,
                    separator = true,
                    callback = function()
                        if self:isAutostartProfile(k) then
                            self:deleteAutostartProfile(k)
                        else
                            self:setAutostartProfile(k)
                        end
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
    self:deleteAutostartProfile(name)
end

function Profiles:isAutostartProfile(name)
    return self.data[autostart_profile] and self.data[autostart_profile][name] == true
end

function Profiles:setAutostartProfile(name)
    if not self.data[autostart_profile] then
        self.data[autostart_profile] = {}
    end
    self.data[autostart_profile][name] = true
    self.updated = true
end

function Profiles:deleteAutostartProfile(name)
    if self.data[autostart_profile][name] then
        self.data[autostart_profile][name] = nil
        self.updated = true
    end
end

function Profiles:executeAutostart()
    if not autostart_done then
        self:loadProfiles()
        if self.data[autostart_profile] then
            for autostart_profile_name, v in pairs(self.data[autostart_profile]) do
                if v and self.data[autostart_profile_name] then
                    UIManager:nextTick(function()
                        Dispatcher:execute(self.data[autostart_profile_name])
                    end)
                else
                    self.data[autostart_profile] = nil -- remove deleted profile form autostart_profile
                    self.updated = true
                end
            end
        end
        autostart_done = true
    end
end

return Profiles
