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
local util = require("util")

local autostart_done = false

local Profiles = WidgetContainer:extend{
    name = "profiles",
    profiles_file = DataStorage:getSettingsDir() .. "/profiles.lua",
    profiles = nil,
    data = nil,
    updated = false,
}

function Profiles:init()
    Dispatcher:init()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:executeAutostart()
end

function Profiles:loadProfiles()
    if self.profiles then
        return
    end
    self.profiles = LuaSettings:open(self.profiles_file)
    self.data = self.profiles.data
    -- ensure profile name
    for k, v in pairs(self.data) do
        if not v.settings then
            self.data[k].settings = {}
        end
        if not self.data[k].settings.name then
            self.data[k].settings.name = k
            self.updated = true
        end
    end
    self:onFlushSettings()
end

function Profiles:onFlushSettings()
    if self.profiles and self.updated then
        self.profiles:flush()
        self.updated = false
    end
end

local function dispatcherRegisterProfile(name)
    Dispatcher:registerAction("profile_exec_"..name,
        {category="none", event="ProfileExecute", arg=name, title=T(_("Profile %1"), name), general=true})
end

local function dispatcherRemoveProfile(name)
    Dispatcher:removeAction("profile_exec_"..name)
end

function Profiles:onDispatcherRegisterActions()
    self:loadProfiles()
    for k, v in pairs(self.data) do
        if v.settings.registered then
            dispatcherRegisterProfile(k)
        end
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
                local function editCallback(new_name)
                    self.data[new_name] = {["settings"] = {["name"] = new_name}}
                    self.updated = true
                    touchmenu_instance.item_table = self:getSubMenuItems()
                    touchmenu_instance.page = 1
                    touchmenu_instance:updateItems()
                end
                self:editProfileName(editCallback)
            end,
            separator = true,
        },
    }
    for k, v in FFIUtil.orderedPairs(self.data) do
        local edit_actions_sub_items = {}
        Dispatcher:addSubMenu(self, edit_actions_sub_items, self.data, k)
        local sub_items = {
            {
                text = _("Execute"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    local show_as_quickmenu = v.settings.show_as_quickmenu
                    self.data[k].settings.show_as_quickmenu = nil
                    self:onProfileExecute(k)
                    self.data[k].settings.show_as_quickmenu = show_as_quickmenu
                end,
            },
            {
                text = _("Show as QuickMenu"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    local show_as_quickmenu = v.settings.show_as_quickmenu
                    self.data[k].settings.show_as_quickmenu = true
                    self:onProfileExecute(k)
                    self.data[k].settings.show_as_quickmenu = show_as_quickmenu
                end,
            },
            {
                text = _("Autostart"),
                help_text = _("Execute this profile when KOReader is started with 'file browser' or 'last file'."),
                checked_func = function()
                    return G_reader_settings:getSettingForExt("autostart_profiles", k)
                end,
                callback = function()
                    local new_value = not G_reader_settings:getSettingForExt("autostart_profiles", k) or nil
                    G_reader_settings:saveSettingForExt("autostart_profiles", new_value, k)
                end,
                separator = true,
            },
            {
                text = _("Show in action list"),
                checked_func = function()
                    return v.settings.registered
                end,
                callback = function(touchmenu_instance)
                    if v.settings.registered then
                        dispatcherRemoveProfile(k)
                        self.data[k].settings.registered = nil
                    else
                        dispatcherRegisterProfile(k)
                        self.data[k].settings.registered = true
                    end
                    self.updated = true
                    local actions_sub_menu = {}
                    Dispatcher:addSubMenu(self, actions_sub_menu, self.data, k)
                    touchmenu_instance.item_table[4].sub_item_table = actions_sub_menu -- item index in submenu
                end,
            },
            {
                text_func = function() return T(_("Edit actions: (%1)"), Dispatcher:menuTextFunc(v)) end,
                sub_item_table = edit_actions_sub_items,
                separator = true,
            },
            {
                text = T(_("Rename: %1"), k),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local function editCallback(new_name)
                        if v.settings.registered then
                            dispatcherRemoveProfile(k)
                            dispatcherRegisterProfile(new_name)
                        end
                        self:renameAutostart(k, new_name)
                        self.data[new_name] = util.tableDeepCopy(v)
                        self.data[new_name].settings.name = new_name
                        self.data[k] = nil
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                      end
                    self:editProfileName(editCallback, k)
                end,
            },
            {
                text = _("Duplicate"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local function editCallback(new_name)
                        self.data[new_name] = util.tableDeepCopy(v)
                        self.data[new_name].settings.name = new_name
                        self.data[new_name].settings.registered = nil
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                      end
                    self:editProfileName(editCallback, k)
                end,
            },
            {
                text = _("Delete"),
                keep_menu_open = true,
                separator = true,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Do you want to delete this profile?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            if v.settings.registered then
                                dispatcherRemoveProfile(k)
                            end
                            self:renameAutostart(k)
                            self.data[k] = nil
                            self.updated = true
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
            },
        }
        table.insert(sub_item_table, {
            text_func = function()
                return (v.settings.show_as_quickmenu and "\u{F0CA} " or "\u{F144} ") .. k
            end,
            hold_keep_menu_open = false,
            sub_item_table = sub_items,
            hold_callback = function()
                self:onProfileExecute(k)
            end,
        })
    end
    return sub_item_table
end

function Profiles:onProfileExecute(name)
    Dispatcher:execute(self.data[name])
end

function Profiles:editProfileName(editCallback, old_name)
    local name_input
    name_input = InputDialog:new{
        title =  _("Enter profile name"),
        input = old_name,
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
                    local new_name = name_input:getInputText()
                    if new_name == "" or new_name == old_name then return end
                    UIManager:close(name_input)
                    if self.data[new_name] then
                        UIManager:show(InfoMessage:new{
                            text = T(_("Profile already exists: %1"), new_name),
                        })
                    else
                        editCallback(new_name)
                    end
                end,
            },
        }},
    }
    UIManager:show(name_input)
    name_input:onShowKeyboard()
end

function Profiles:renameAutostart(old_name, new_name)
    if G_reader_settings:getSettingForExt("autostart_profiles", old_name) then
        G_reader_settings:saveSettingForExt("autostart_profiles", nil, old_name)
        if new_name then
            G_reader_settings:saveSettingForExt("autostart_profiles", true, new_name)
        end
    end
end

function Profiles:executeAutostart()
    if autostart_done then return end
    self:loadProfiles()
    local autostart_table = G_reader_settings:readSetting("autostart_profiles") or {}
    for autostart_profile_name, profile_enabled in pairs(autostart_table) do
        if self.data[autostart_profile_name] and profile_enabled then
            UIManager:nextTick(function()
                Dispatcher:execute(self.data[autostart_profile_name])
            end)
        else
            self:renameAutostart(autostart_profile_name) -- remove deleted profile from autostart_profile
        end
    end
    autostart_done = true
end

return Profiles
