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
    self:onDispatcherRegisterActions()
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

local function dispatcherRegisterProfile(name, unregister)
    if unregister then
        Dispatcher:removeAction("profile_exec_"..name)
        Dispatcher:removeAction("profile_menu_"..name)
    else
        Dispatcher:registerAction("profile_exec_"..name,
            {category="none", event="ProfileExecute", arg=name, title=T(_("Profile execute: %1"), name), general=true})
        Dispatcher:registerAction("profile_menu_"..name,
            {category="none", event="ProfileShowMenu", arg=name, title=T(_("Profile show menu: %1"), name), general=true})
    end
end

function Profiles:onDispatcherRegisterActions()
    self:loadProfiles()
    for name in pairs(self.data) do
        dispatcherRegisterProfile(name)
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
                    self.data[new_name] = {}
                    self.updated = true
                    dispatcherRegisterProfile(new_name)
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
        local sub_items = {
            {
                text = _("Execute"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    self:onProfileExecute(k)
                end,
            },
            {
                text = _("Show as QuickMenu"),
                callback = function()
                    self:onProfileShowMenu(k)
                end,
            },
            {
                text = _("Show as QuickMenu on long-press"),
                checked_func = function()
                    local settings = self.data[k].settings
                    return settings and settings.long_press_show_menu
                end,
                callback = function()
                    local settings = self.data[k].settings
                    if settings then
                        if settings.long_press_show_menu then
                            settings.long_press_show_menu = nil
                            if #settings == 0 then
                                self.data[k].settings = nil
                            end
                        else
                            settings.long_press_show_menu = true
                        end
                    else
                        self.data[k].settings = {["long_press_show_menu"] = true}
                    end
                    self.updated = true
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
            -- "Edit actions"
            {
                text = _("Sort actions"),
                checked_func = function()
                    local settings = self.data[k].settings
                    return settings and settings.actions_order
                end,
                callback = function(touchmenu_instance)
                    self:sortActions(k, touchmenu_instance)
                end,
                hold_callback = function(touchmenu_instance)
                    if self.data[k].settings and self.data[k].settings.actions_order then
                        self.data[k].settings.actions_order = nil
                        if #self.data[k].settings == 0 then
                            self.data[k].settings = nil
                        end
                        self.updated = true
                        touchmenu_instance:updateItems()
                    end
                end,
                separator = true,
            },
            {
                text = T(_("Rename: %1"), k),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local function editCallback(new_name)
                        self.data[new_name] = util.tableDeepCopy(v)
                        self.data[k] = nil
                        self.updated = true
                        self:renameAutostart(k, new_name)
                        dispatcherRegisterProfile(k, true)
                        dispatcherRegisterProfile(new_name)
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
                            self.data[k] = nil
                            self.updated = true
                            self:renameAutostart(k)
                            dispatcherRegisterProfile(k, true)
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
            },
        }
        local edit_actions_sub_items = {}
        Dispatcher:addSubMenu(self, edit_actions_sub_items, self.data, k)
        table.insert(sub_items, 5, { 
            text = _("Edit actions"),
            sub_item_table = edit_actions_sub_items,
        })
        table.insert(sub_item_table, {
            text = k,
            hold_keep_menu_open = false,
            sub_item_table = sub_items,
            hold_callback = function()
                local settings = self.data[k].settings
                if settings and settings.long_press_show_menu then
                    self:onProfileShowMenu(k)
                else
                    self:onProfileExecute(k)
                end
            end,
        })
    end
    return sub_item_table
end

function Profiles:onProfileExecute(name)
    local profile = self.data[name]
    if profile and profile.settings and profile.settings.actions_order then
        self:syncOrder(name)
        for _, action in ipairs(profile.settings.actions_order) do
            Dispatcher:execute({[action] = profile[action]})
        end
    else
        Dispatcher:execute(profile)
    end
end

function Profiles:onProfileShowMenu(name)
    if UIManager:getTopWidget() == name then return end
    local profile = self.data[name]
    local actions_list = self:getActionsList(name)
    local quickmenu
    local buttons = {}
    for i = 1, #actions_list do
        table.insert(buttons, {{
            text = actions_list[i].text,
            align = "left",
            font_face = "smallinfofont",
            font_size = 22,
            font_bold = false,
            callback = function()
                UIManager:close(quickmenu)
                local action = actions_list[i].label
                Dispatcher:execute({[action] = profile[action]})
            end,
        }})
    end
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    quickmenu = ButtonDialogTitle:new{
        name = name,
        title = name,
        title_align = "center",
        width_factor = 0.8,
        use_info_style = false,
        buttons = buttons,
    }
    UIManager:show(quickmenu)
end

function Profiles:sortActions(name, touchmenu_instance)
    local profile = self.data[name]
    local actions_list = self:getActionsList(name)
    local SortWidget = require("ui/widget/sortwidget")
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Sort actions"),
        item_table = actions_list,
        callback = function()
            if profile.settings then
                self.data[name].settings.actions_order = {}
            else
                self.data[name].settings = {["actions_order"] = {}}
            end
            for i = 1, #sort_widget.item_table do
                self.data[name].settings.actions_order[i] = sort_widget.item_table[i].label
            end
            touchmenu_instance:updateItems()
            self.updated = true
        end
    }
    UIManager:show(sort_widget)
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

function Profiles:getActionsList(name)
    local profile = self.data[name]
    local function getActionFullName (profile_name, action_name)
        local location = {} -- make this as expected by Dispatcher:getNameFromItem()
        if type(profile_name[action_name]) ~= "boolean" then
            location[action_name] = {[action_name] = profile_name[action_name]}
        end
        return Dispatcher:getNameFromItem(action_name, location, action_name)
    end
    local actions_list = {}
    if profile and profile.settings and profile.settings.actions_order then
        self:syncOrder(name)
        for _, action in ipairs(profile.settings.actions_order) do
            table.insert(actions_list, {text = getActionFullName(profile, action), label = action})
        end
    else
        for action in pairs(profile) do
            if action ~= "settings" then
                table.insert(actions_list, {text = getActionFullName(profile, action), label = action})
            end
        end
    end
    return actions_list
end

function Profiles:syncOrder(name)
    local profile = self.data[name]
    for i = #profile.settings.actions_order, 1, -1 do
        if not profile[profile.settings.actions_order[i]] then
            table.remove(self.data[name].settings.actions_order, i)
            if not self.updated then
                self.updated = true
            end
        end
    end
    for action in pairs(profile) do
        if action ~= "settings" and not util.arrayContains(profile.settings.actions_order, action) then
            table.insert(self.data[name].settings.actions_order, action)
            if not self.updated then
                self.updated = true
            end
        end
    end
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
