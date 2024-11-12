local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

local autostart_done

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
    self.autoexec = G_reader_settings:readSetting("profiles_autoexec", {})
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:onStart()
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
                    self.data[new_name] = { ["settings"] = { ["name"] = new_name } }
                    self.updated = true
                    touchmenu_instance.item_table = self:getSubMenuItems()
                    touchmenu_instance.page = 1
                    touchmenu_instance:updateItems()
                end
                self:editProfileName(editCallback)
            end,
        },
        {
            text = _("New with current book settings"),
            enabled = self.ui.document ~= nil,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local function editCallback(new_name)
                    self.data[new_name] = self:getProfileFromCurrentBookSettings(new_name)
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
    for k, v in ffiUtil.orderedPairs(self.data) do
        local sub_items = {
            ignored_by_menu_search = true,
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
                text = _("Auto-execute"),
                checked_func = function()
                    for _, profiles in pairs(self.autoexec) do
                        if profiles[k] then
                            return true
                        end
                    end
                end,
                sub_item_table_func = function()
                    return {
                        {
                            text = _("Ask to execute"),
                            checked_func = function()
                                return v.settings.auto_exec_ask
                            end,
                            callback = function()
                                self.data[k].settings.auto_exec_ask = not v.settings.auto_exec_ask and true or nil
                                self.updated = true
                            end,
                            separator = true,
                        },
                        self:genAutoExecMenuItem(_("on KOReader start"), "Start", k),
                        self:genAutoExecMenuItem(_("on wake-up"), "Resume", k),
                        self:genAutoExecMenuItem(_("on rotation"), "SetRotationMode", k),
                        self:genAutoExecMenuItem(_("on showing folder"), "PathChanged", k, true),
                        -- separator
                        self:genAutoExecMenuItem(_("on book opening"), "ReaderReadyAll", k),
                        self:genAutoExecMenuItem(_("on book closing"), "CloseDocumentAll", k),
                    }
                end,
                hold_callback = function(touchmenu_instance)
                    for event, profiles in pairs(self.autoexec) do
                        if profiles[k] then
                            util.tableRemoveValue(self.autoexec, event, k)
                        end
                    end
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text = _("Show notification on executing"),
                checked_func = function()
                    return v.settings.notify
                end,
                callback = function()
                    self.data[k].settings.notify = not v.settings.notify and true or nil
                    self.updated = true
                end,
                separator = true,
            },
            {
                text = _("Show in action list"),
                checked_func = function()
                    return v.settings.registered
                end,
                callback = function()
                    if v.settings.registered then
                        dispatcherUnregisterProfile(k)
                        self:updateProfiles(self.prefix..k)
                        self.data[k].settings.registered = nil
                    else
                        dispatcherRegisterProfile(k)
                        self.data[k].settings.registered = true
                    end
                    self.updated = true
                end,
            },
            {
                text_func = function()
                    return T(_("Edit actions: (%1)"), Dispatcher:menuTextFunc(v))
                end,
                sub_item_table_func = function()
                    local edit_actions_sub_items = {}
                    Dispatcher:addSubMenu(self, edit_actions_sub_items, self.data, k)
                    return edit_actions_sub_items
                end,
                separator = true,
            },
            {
                text = T(_("Rename: %1"), k),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local function editCallback(new_name)
                        self.data[new_name] = util.tableDeepCopy(v)
                        self.data[new_name].settings.name = new_name
                        self:updateAutoExec(k, new_name)
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
                            self:updateAutoExec(k)
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

function Profiles:getProfileFromCurrentBookSettings(new_name)
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

-- AutoExec

function Profiles:updateAutoExec(old_name, new_name)
    for event, profiles in pairs(self.autoexec) do
        local old_value
        for profile_name in pairs(profiles) do
            if profile_name == old_name then
                old_value = profiles[old_name]
                profiles[old_name] = nil
                break
            end
        end
        if old_value then
            if new_name then
                profiles[new_name] = old_value
            else
                if next(profiles) == nil then
                    self.autoexec[event] = nil
                end
            end
        end
    end
end

function Profiles:genAutoExecMenuItem(text, event, profile_name, separator)
    if event == "SetRotationMode" then
        return self:genAutoExecSetRotationModeMenuItem(text, event, profile_name, separator)
    elseif event == "PathChanged" then
        return self:genAutoExecPathChangedMenuItem(text, event, profile_name, separator)
    elseif event == "ReaderReadyAll" or event == "CloseDocumentAll" then
        return self:genAutoExecDocConditionalMenuItem(text, event, profile_name, separator)
    end
    return {
        text = text,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, profile_name)
        end,
        callback = function()
            if util.tableGetValue(self.autoexec, event, profile_name) then
                util.tableRemoveValue(self.autoexec, event, profile_name)
            else
                util.tableSetValue(self.autoexec, true, event, profile_name)
                if event == "ReaderReady" or event == "CloseDocument" then
                    -- "always" is checked, clear all conditional triggers
                    util.tableRemoveValue(self.autoexec, event .. "All", profile_name)
                end
            end
        end,
        separator = separator,
    }
end

function Profiles:genAutoExecSetRotationModeMenuItem(text, event, profile_name, separator)
    return {
        text = text,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, profile_name) and true
        end,
        sub_item_table_func = function()
            local sub_item_table = {}
            local optionsutil = require("ui/data/optionsutil")
            for i, mode in ipairs(optionsutil.rotation_modes) do
                sub_item_table[i] = {
                    text = optionsutil.rotation_labels[i],
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, mode)
                    end,
                    callback = function()
                        if util.tableGetValue(self.autoexec, event, profile_name, mode) then
                            util.tableRemoveValue(self.autoexec, event, profile_name, mode)
                        else
                            util.tableSetValue(self.autoexec, true, event, profile_name, mode)
                        end
                    end,
                }
            end
            return sub_item_table
        end,
        hold_callback = function(touchmenu_instance)
            util.tableRemoveValue(self.autoexec, event, profile_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Profiles:genAutoExecPathChangedMenuItem(text, event, profile_name, separator)
    return {
        text = text,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, profile_name) and true
        end,
        sub_item_table_func = function()
            local conditions = {
                { _("if folder path contains"), "has" },
                { _("if folder path does not contain"), "has_not" },
            }
            local sub_item_table = {}
            for i, mode in ipairs(conditions) do
                sub_item_table[i] = {
                    text_func = function()
                        local txt = conditions[i][1]
                        local value = util.tableGetValue(self.autoexec, event, profile_name, conditions[i][2])
                        return value and txt .. ": " .. value or txt
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, conditions[i][2])
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[i][2]
                        local dialog
                        local buttons = {{
                            {
                                text = _("Current folder"),
                                callback = function()
                                    local curr_path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                                    dialog:addTextToInput(curr_path)
                                end,
                            },
                        }}
                        table.insert(buttons, {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("Save"),
                                callback = function()
                                    local txt = dialog:getInputText()
                                    if txt == "" then
                                        util.tableRemoveValue(self.autoexec, event, profile_name, condition)
                                    else
                                        util.tableSetValue(self.autoexec, txt, event, profile_name, condition)
                                    end
                                    UIManager:close(dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        })
                        dialog = InputDialog:new{
                            title =  _("Enter text contained in folder path"),
                            input = util.tableGetValue(self.autoexec, event, profile_name, condition),
                            buttons = buttons,
                        }
                        UIManager:show(dialog)
                        dialog:onShowKeyboard()
                    end,
                }
            end
            return sub_item_table
        end,
        hold_callback = function(touchmenu_instance)
            util.tableRemoveValue(self.autoexec, event, profile_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Profiles:genAutoExecDocConditionalMenuItem(text, event, profile_name, separator)
    local event_always = event:gsub("All", "")
    return {
        text = text,
        checked_func = function()
            return (util.tableGetValue(self.autoexec, event_always, profile_name) or util.tableGetValue(self.autoexec, event, profile_name)) and true
        end,
        sub_item_table_func = function()
            local conditions = {
                { _("if device orientation is"), "orientation" },
                { _("if book metadata contains"), "doc_props" },
                { _("if book file path contains"), "filepath" },
                { _("if book is in collections"), "collections" },
            }
            local sub_item_table = {
                self:genAutoExecMenuItem(_("always"), event_always, profile_name, true),
                -- separator
                {
                    text = conditions[1][1], -- orientation
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, profile_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, conditions[1][2]) and true
                    end,
                    sub_item_table_func = function()
                        local condition = conditions[1][2]
                        local sub_item_table = {}
                        local optionsutil = require("ui/data/optionsutil")
                        for i, mode in ipairs(optionsutil.rotation_modes) do
                            sub_item_table[i] = {
                                text = optionsutil.rotation_labels[i],
                                checked_func = function()
                                    return util.tableGetValue(self.autoexec, event, profile_name, condition, mode)
                                end,
                                callback = function()
                                    if util.tableGetValue(self.autoexec, event, profile_name, condition, mode) then
                                        util.tableRemoveValue(self.autoexec, event, profile_name, condition, mode)
                                    else
                                        util.tableSetValue(self.autoexec, true, event, profile_name, condition, mode)
                                    end
                                end,
                            }
                        end
                        return sub_item_table
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, profile_name, conditions[1][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = conditions[2][1], -- doc_props
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, profile_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, conditions[2][2]) and true
                    end,
                    sub_item_table_func = function()
                        local condition = conditions[2][2]
                        local sub_item_table = {}
                        for i, prop in ipairs(self.ui.bookinfo.props) do
                            sub_item_table[i] = {
                                text_func = function()
                                    local title = self.ui.bookinfo.prop_text[prop]:lower()
                                    local txt = util.tableGetValue(self.autoexec, event, profile_name, condition, prop)
                                    return txt and title .. " " .. txt or title:sub(1, -2)
                                end,
                                checked_func = function()
                                    return util.tableGetValue(self.autoexec, event, profile_name, condition, prop) and true
                                end,
                                callback = function(touchmenu_instance)
                                    local dialog
                                    local buttons = self.ui.document == nil and {} or {{
                                        {
                                            text = _("Current book"),
                                            enabled_func = function()
                                                return prop == "title" or self.ui.doc_props[prop] ~= nil
                                            end,
                                            callback = function()
                                                local txt = self.ui.doc_props[prop == "title" and "display_title" or prop]
                                                dialog:addTextToInput(txt)
                                            end,
                                        },
                                    }}
                                    table.insert(buttons, {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(dialog)
                                            end,
                                        },
                                        {
                                            text = _("Save"),
                                            callback = function()
                                                local txt = dialog:getInputText()
                                                if txt == "" then
                                                    util.tableRemoveValue(self.autoexec, event, profile_name, condition, prop)
                                                else
                                                    util.tableSetValue(self.autoexec, txt, event, profile_name, condition, prop)
                                                end
                                                UIManager:close(dialog)
                                                touchmenu_instance:updateItems()
                                            end,
                                        },
                                    })
                                    dialog = InputDialog:new{
                                        title =  _("Enter text contained in:") .. " " .. self.ui.bookinfo.prop_text[prop]:sub(1, -2),
                                        input = util.tableGetValue(self.autoexec, event, profile_name, condition, prop),
                                        buttons = buttons,
                                    }
                                    UIManager:show(dialog)
                                    dialog:onShowKeyboard()
                                end,
                                hold_callback = function(touchmenu_instance)
                                    util.tableRemoveValue(self.autoexec, event, profile_name, condition, prop)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                        end
                        return sub_item_table
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, profile_name, conditions[2][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function() -- filepath
                        local txt = conditions[3][1]
                        local value = util.tableGetValue(self.autoexec, event, profile_name, conditions[3][2])
                        return value and txt .. ": " .. value or txt
                    end,
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, profile_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, conditions[3][2]) and true
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[3][2]
                        local dialog
                        local buttons = self.ui.document == nil and {} or {{
                            {
                                text = _("Current book"),
                                callback = function()
                                    dialog:addTextToInput(self.ui.document.file)
                                end,
                            },
                        }}
                        table.insert(buttons, {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("Save"),
                                callback = function()
                                    local txt = dialog:getInputText()
                                    if txt == "" then
                                        util.tableRemoveValue(self.autoexec, event, profile_name, condition)
                                    else
                                        util.tableSetValue(self.autoexec, txt, event, profile_name, condition)
                                    end
                                    UIManager:close(dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        })
                        dialog = InputDialog:new{
                            title =  _("Enter text contained in file path"),
                            input = util.tableGetValue(self.autoexec, event, profile_name, condition),
                            buttons = buttons,
                        }
                        UIManager:show(dialog)
                        dialog:onShowKeyboard()
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, profile_name, conditions[3][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function() -- collections
                        local txt = conditions[4][1]
                        local collections = util.tableGetValue(self.autoexec, event, profile_name, conditions[4][2])
                        if collections then
                            local collections_nb = util.tableSize(collections)
                            return txt .. ": " ..
                                (collections_nb == 1 and self.ui.collections:getCollectionTitle(next(collections))
                                                      or "(" .. collections_nb .. ")")
                        end
                        return txt
                    end,
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, profile_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, profile_name, conditions[4][2]) and true
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[4][2]
                        local collections = util.tableGetValue(self.autoexec, event, profile_name, condition)
                        local caller_callback = function(selected_collections)
                            if next(selected_collections) == nil then
                                util.tableRemoveValue(self.autoexec, event, profile_name, condition)
                            else
                                util.tableSetValue(self.autoexec, selected_collections, event, profile_name, condition)
                            end
                            touchmenu_instance:updateItems()
                        end
                        self.ui.collections:onShowCollList(collections or {}, caller_callback, true)
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, profile_name, conditions[4][2])
                        touchmenu_instance:updateItems()
                    end,
                },
            }
            return sub_item_table
        end,
        hold_callback = function(touchmenu_instance)
            util.tableRemoveValue(self.autoexec, event_always, profile_name)
            util.tableRemoveValue(self.autoexec, event, profile_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Profiles:onStart() -- local event
    if not autostart_done then
        self:executeAutoExecEvent("Start")
        autostart_done = true
    end
end

function Profiles:onResume() -- global
    self:executeAutoExecEvent("Resume")
end

function Profiles:onSetRotationMode(mode) -- global
    local event = "SetRotationMode"
    if self.autoexec[event] == nil then return end
    for profile_name, modes in pairs(self.autoexec[event]) do
        if modes[mode] then
            if self.ui.config then -- close bottom menu to let Dispatcher execute profile
                self.ui.config:onCloseConfigMenu()
            end
            self:executeAutoExec(profile_name)
        end
    end
end

function Profiles:onPathChanged(path) -- global
    local event = "PathChanged"
    if self.autoexec[event] == nil then return end
    local function is_match(txt, pattern)
        for str in util.gsplit(pattern, ",") do -- comma separated patterns are allowed
            if util.stringSearch(txt, str) ~= 0 then
                return true
            end
        end
    end
    for profile_name, conditions in pairs(self.autoexec[event]) do
        local do_execute
        if conditions.has then
            do_execute = is_match(path, conditions.has)
        end
        if do_execute == nil and conditions.has_not then
            do_execute = not is_match(path, conditions.has_not)
        end
        if do_execute then
            self:executeAutoExec(profile_name)
        end
    end
end

function Profiles:onReaderReady() -- global
    if not self.ui.reloading then
        self:executeAutoExecEvent("ReaderReady")
        self:executeAutoExecDocConditional("ReaderReadyAll")
    end
end

function Profiles:onCloseDocument() -- global
    if not self.ui.reloading then
        self:executeAutoExecEvent("CloseDocument")
        self:executeAutoExecDocConditional("CloseDocumentAll")
    end
end

function Profiles:executeAutoExecEvent(event)
    if self.autoexec[event] == nil then return end
    for profile_name in pairs(self.autoexec[event]) do
        self:executeAutoExec(profile_name)
    end
end

function Profiles:executeAutoExec(profile_name)
    local profile = self.data[profile_name]
    if profile == nil then return end
    if profile.settings.auto_exec_ask then
        UIManager:show(ConfirmBox:new{
            text = _("Do you want to execute profile?") .. "\n\n" .. profile_name .. "\n",
            ok_text = _("Execute"),
            ok_callback = function()
                logger.dbg("Profiles - auto executing:", profile_name)
                UIManager:nextTick(function()
                    Dispatcher:execute(self.data[profile_name])
                end)
            end,
        })
    else
        logger.dbg("Profiles - auto executing:", profile_name)
        UIManager:nextTick(function()
            Dispatcher:execute(self.data[profile_name])
        end)
    end
end

function Profiles:executeAutoExecDocConditional(event)
    if self.autoexec[event] == nil then return end
    local function is_match(txt, pattern)
        for str in util.gsplit(pattern, ",") do
            if util.stringSearch(txt, str) ~= 0 then
                return true
            end
        end
    end
    for profile_name, conditions in pairs(self.autoexec[event]) do
        if self.data[profile_name] then
            local do_execute
            for condition, trigger in pairs(conditions) do
                if condition == "orientation" then
                    local mode = Screen:getRotationMode()
                    do_execute = trigger[mode]
                elseif condition == "doc_props" then
                    if self.ui.document then
                        for prop_name, pattern in pairs(trigger) do
                            local prop = self.ui.doc_props[prop_name == "title" and "display_title" or prop_name]
                            do_execute = is_match(prop, pattern)
                            if do_execute then
                                break -- any prop match is enough
                            end
                        end
                    end
                elseif condition == "filepath" then
                    if self.ui.document then
                        do_execute = is_match(self.ui.document.file, trigger)
                    end
                elseif condition == "collections" then
                    if self.ui.document then
                        local ReadCollection = require("readcollection")
                        for collection_name in pairs(trigger) do
                            if ReadCollection:isFileInCollection(self.ui.document.file, collection_name) then
                                do_execute = true
                                break -- any collection is enough
                            end
                        end
                    end
                end
                if do_execute then
                    break -- execute profile only once
                end
            end
            if do_execute then
                self:executeAutoExec(profile_name)
            end
        end
    end
end

return Profiles
