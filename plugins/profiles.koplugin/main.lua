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
    prefix = "profile_exec_",
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
    Dispatcher:registerAction(Profiles.prefix..name,
        {category="none", event="ProfileExecute", arg=name, title=T(_("Profile %1"), name), general=true})
end

local function dispatcherUnregisterProfile(name)
    Dispatcher:removeAction(Profiles.prefix..name)
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
        },
        {
            text = _("New with current document settings"),
            enabled = self.ui.file_chooser == nil,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local function editCallback(new_name)
                    self.data[new_name] = self:getProfileFromCurrentDocument(new_name)
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
                    self:onProfileExecute(k, { qm_show = false })
                end,
            },
            {
                text = _("Show as QuickMenu"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    self:onProfileExecute(k, { qm_show = true })
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
                        dispatcherUnregisterProfile(k)
                        self:updateProfiles(self.prefix..k)
                        self.data[k].settings.registered = nil
                    else
                        dispatcherRegisterProfile(k)
                        self.data[k].settings.registered = true
                    end
                    self.updated = true
                    local actions_sub_menu = {}
                    Dispatcher:addSubMenu(self, actions_sub_menu, self.data, k)
                    touchmenu_instance.item_table[5].sub_item_table = actions_sub_menu -- "Edit actions" submenu (item #5)
                    touchmenu_instance.item_table_stack[#touchmenu_instance.item_table_stack] = self:getSubMenuItems()
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
                        self.data[new_name] = util.tableDeepCopy(v)
                        self.data[new_name].settings.name = new_name
                        self:updateAutostart(k, new_name)
                        if v.settings.registered then
                            dispatcherUnregisterProfile(k)
                            dispatcherRegisterProfile(new_name)
                            self:updateProfiles(self.prefix..k, self.prefix..new_name)
                        end
                        self.data[k] = nil
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                        table.remove(touchmenu_instance.item_table_stack)
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
                        if v.settings.registered then
                            dispatcherRegisterProfile(new_name)
                        end
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                        table.remove(touchmenu_instance.item_table_stack)
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
                            self:updateAutostart(k)
                            if v.settings.registered then
                                dispatcherUnregisterProfile(k)
                                self:updateProfiles(self.prefix..k)
                            end
                            self.data[k] = nil
                            self.updated = true
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                            table.remove(touchmenu_instance.item_table_stack)
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

function Profiles:onProfileExecute(name, exec_props)
    Dispatcher:execute(self.data[name], exec_props)
end

function Profiles:editProfileName(editCallback, old_name)
    local name_input
    name_input = InputDialog:new{
        title =  _("Enter profile name"),
        input = old_name,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
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

function Profiles:getProfileFromCurrentDocument(new_name)
    local document_settings
    if self.ui.rolling then
        document_settings = {
            "rotation_mode",
            "set_font",
            "font_size",
            "font_gamma",
            "font_base_weight",
            "font_hinting",
            "font_kerning",
            "word_spacing",
            "word_expansion",
            "visible_pages",
            "h_page_margins",
            "sync_t_b_page_margins",
            "t_page_margin",
            "b_page_margin",
            "view_mode",
            "block_rendering_mode",
            "render_dpi",
            "line_spacing",
            "embedded_css",
            "embedded_fonts",
            "smooth_scaling",
            "nightmode_images",
            "status_line",
        }
    else
        document_settings = {
            "rotation_mode",
            "kopt_text_wrap",
            "kopt_trim_page",
            "kopt_page_margin",
            "kopt_zoom_overlap_h",
            "kopt_zoom_overlap_v",
            "kopt_max_columns",
            "kopt_zoom_mode_genus",
            "kopt_zoom_mode_type",
            "kopt_zoom_factor",
            "kopt_zoom_direction",
            "kopt_page_scroll",
            "kopt_line_spacing",
            "kopt_font_size",
            "kopt_contrast",
            "kopt_quality",
        }
    end
    local setting_needs_arg = {
        ["sync_t_b_page_margins"] = true,
        ["view_mode"]             = true,
        ["embedded_css"]          = true,
        ["embedded_fonts"]        = true,
        ["smooth_scaling"]        = true,
        ["nightmode_images"]      = true,
        ["kopt_trim_page"]        = true,
        ["kopt_zoom_mode_genus"]  = true,
        ["kopt_zoom_mode_type"]   = true,
        ["kopt_page_scroll"]      = true,
    }

    local profile = { settings = { name = new_name, order = document_settings } }
    for _, v in ipairs(document_settings) do
        -- document configurable settings do not have prefixes
        local value = self.document.configurable[v:gsub("^kopt_", "")]
        if setting_needs_arg[v] then
            value = Dispatcher:getArgFromValue(v, value)
        end
        profile[v] = value
    end
    if self.ui.rolling then
        profile["set_font"] = self.ui.font.font_face -- not in configurable settings
    end
    return profile
end

function Profiles:updateProfiles(action_old_name, action_new_name)
    for _, profile in pairs(self.data) do
        if profile[action_old_name] then
            if profile.settings and profile.settings.order then
                for i, action in ipairs(profile.settings.order) do
                    if action == action_old_name then
                        if action_new_name then
                            profile.settings.order[i] = action_new_name
                        else
                            table.remove(profile.settings.order, i)
                            if #profile.settings.order == 0 then
                                profile.settings.order = nil
                            end
                        end
                        break
                    end
                end
            end
            profile[action_old_name] = nil
            if action_new_name then
                profile[action_new_name] = true
            end
            self.updated = true
        end
    end
    if self.ui.gestures then -- search and update the profile action in assigned gestures
        self.ui.gestures:updateProfiles(action_old_name, action_new_name)
    end
end

function Profiles:updateAutostart(old_name, new_name)
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
            self:updateAutostart(autostart_profile_name) -- remove deleted profile from autostart_profile
        end
    end
    autostart_done = true
end

return Profiles
