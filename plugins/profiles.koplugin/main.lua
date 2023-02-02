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
                        dispatcherUnregisterProfile(k)
                        self:updateGestures(self.prefix..k)
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
                            self:updateGestures(self.prefix..k, self.prefix..new_name)
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
                                self:updateGestures(self.prefix..k)
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

    local profile = { settings = { name = new_name, order = document_settings } }
    for _, v in ipairs(document_settings) do
        profile[v] = self.document.configurable[self.ui.rolling and v or v:sub(6)]
    end
    if self.ui.rolling then
        profile["set_font"] = self.ui.font.font_face
        profile["sync_t_b_page_margins"] = self.ui.typeset.sync_t_b_page_margins
        profile["view_mode"] = self.view.view_mode
        profile["embedded_css"] = self.ui.typeset.embedded_css
        profile["embedded_fonts"] = self.ui.typeset.embedded_fonts
        profile["smooth_scaling"] = self.ui.typeset.smooth_scaling
    else
        local trim_page_to_mode = { _("manual"), _("auto"), _("semi-auto"), _("none") }
        local zoom_genus_to_mode = { _("manual"), _("rows"), _("columns"), _("content"), _("page") }
        local zoom_type_to_mode = { _("height"), _("width"), _("full") }
        profile["rotation_mode"] = self.document.configurable.rotation_mode
        profile["kopt_trim_page"] = trim_page_to_mode[profile["kopt_trim_page"]+1]
        profile["kopt_zoom_mode_genus"] = zoom_genus_to_mode[profile["kopt_zoom_mode_genus"]+1]
        profile["kopt_zoom_mode_type"] = zoom_type_to_mode[profile["kopt_zoom_mode_type"]+1]
        profile["kopt_page_scroll"] = self.view.page_scroll
    end
    return profile
end

function Profiles:updateGestures(action_old_name, action_new_name)
    local gestures_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), "gestures.lua")
    local all_gestures = LuaSettings:open(gestures_path) -- in file
    if not all_gestures then return end
    local updated = false
    for section, gestures in pairs(all_gestures.data) do -- custom_multiswipes, fm, reader sections
        for gesture_name, gesture in pairs(gestures) do
            if gesture[action_old_name] then
                local gesture_loaded = self.ui.gestures.gestures[gesture_name] -- in memory
                if gesture.settings and gesture.settings.order then
                    for i, action in ipairs(gesture.settings.order) do
                        if action == action_old_name then
                            if action_new_name then
                                gesture.settings.order[i] = action_new_name
                                gesture_loaded.settings.order[i] = action_new_name
                            else
                                table.remove(gesture.settings.order, i)
                                table.remove(gesture_loaded.settings.order, i)
                                if #gesture.settings.order == 0 then
                                    gesture.settings.order = nil
                                    if #gesture.settings == 0 then
                                        gesture.settings = nil
                                    end
                                end
                            end
                            break
                        end
                    end
                end
                gesture[action_old_name] = nil
                gesture_loaded[action_old_name] = nil
                if action_new_name then
                    gesture[action_new_name] = true
                    gesture_loaded[action_new_name] = true
                else
                    if #gesture == 0 then
                        all_gestures.data[section][gesture_name] = nil
                    end
                end
                updated = true
            end
        end
    end
    if updated then
        all_gestures:flush()
    end
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
