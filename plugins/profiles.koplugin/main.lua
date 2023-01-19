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
local lfs = require("libs/libkoreader-lfs")
local rapidjson = require("rapidjson")
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

local function dispatcherUnregisterProfile(name)
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
        },
        {
            text = _("Import"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local function importCallback()
                    self.updated = true
                    touchmenu_instance.item_table = self:getSubMenuItems()
                    touchmenu_instance.page = 1
                    touchmenu_instance:updateItems()
                end
                self:importProfile(importCallback)
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
                            dispatcherUnregisterProfile(k)
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
                text = _("Export"),
                keep_menu_open = true,
                callback = function()
                    self:exportProfile(k)
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
                                dispatcherUnregisterProfile(k)
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

function Profiles:exportProfile(name)
    UIManager:show(ConfirmBox:new{
        text = _("The profile will be saved as:") .. "\n\n".. _("Profile ") .. name .. ".json",
        ok_text = _("Save"),
        ok_callback = function()
            local text
            local path = DataStorage:getDataDir() .. "/clipboard"
            if lfs.attributes(path, "mode") ~= "directory" then
                lfs.mkdir(path)
            end
            local filepath = path .. "/" .. name .. ".json"
            local file = io.open(filepath, "w")
            if file then
                file:write(rapidjson.encode(self.data[name], {pretty = true}))
                file:write("\n")
                file:close()
                text = _("Profile saved")
            else
                text = _("Failed to save profile")
            end
            UIManager:show(require("ui/widget/notification"):new{
                text = text,
            })
        end,
    })
end

function Profiles:importProfile(importCallback)
    local path_chooser = require("ui/widget/pathchooser"):new{
        select_directory = false,
        path = DataStorage:getDataDir() .. "/clipboard",
        onConfirm = function(file_path)
            local file = io.open(file_path, "r")
            if file then
                local contents = file:read("*all")
                file:close()
                local ok, parsed = pcall(rapidjson.decode, contents)
                if ok then
                    local name = parsed and parsed.settings and parsed.settings.name
                    if name then
                        self.data[name] = parsed
                        importCallback()
                    end
                end
            end
        end
    }
    UIManager:show(path_chooser)
end

return Profiles
