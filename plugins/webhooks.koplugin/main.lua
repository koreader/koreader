local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

local autostart_done

local Webhooks = WidgetContainer:extend{
    name = "webhooks",
    prefix = "webhook_exec_",
    webhooks_file = DataStorage:getSettingsDir() .. "/webhooks.lua",
    webhooks = nil,
    data = nil,
    updated = false,
}

function Webhooks:init()
    Dispatcher:init()
    self.autoexec = G_reader_settings:readSetting("webhooks_autoexec", {})
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:onStart()
end

function Webhooks:loadWebhooks()
    if self.webhooks then
        return
    end
    self.webhooks = LuaSettings:open(self.webhooks_file)
    self.data = self.webhooks.data
    -- ensure webhook name
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

function Webhooks:onFlushSettings()
    if self.webhooks and self.updated then
        self.webhooks:flush()
        self.updated = false
    end
end

local function dispatcherRegisterWebhook(name)
    Dispatcher:registerAction(Webhooks.prefix..name,
        {category="none", event="WebhookExecute", arg=name, title=T(_("Webhook: %1"), name), general=true})
end

local function dispatcherUnregisterWebhook(name)
    Dispatcher:removeAction(Webhooks.prefix..name)
end

function Webhooks:onDispatcherRegisterActions()
    self:loadWebhooks()
    for k, v in pairs(self.data) do
        if v.settings.registered then
            dispatcherRegisterWebhook(k)
        end
    end
end

function Webhooks:addToMainMenu(menu_items)
    menu_items.webhooks = {
        text = _("Webhooks"),
	sorting_hint = "setting",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function Webhooks:getSubMenuItems()
    self:loadWebhooks()
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
                self:editWebhookName(editCallback)
            end,
        },
    }
    for k, v in ffiUtil.orderedPairs(self.data) do
        local sub_items = {
            ignored_by_menu_search = true,
            {
                text = _("Dispatch"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    self:onWebhookExecute(k)
                end,
            },
            {
                text = _("Auto-dispatch"),
                checked_func = function()
                    for _, webhooks in pairs(self.autoexec) do
                        if webhooks[k] then
                            return true
                        end
                    end
                end,
                sub_item_table_func = function()
                    return {
                        {
                            text = _("Ask to dispatch"),
                            checked_func = function()
                                return v.settings.auto_exec_ask
                            end,
                            callback = function()
                                self.data[k].settings.auto_exec_ask = not v.settings.auto_exec_ask and true or nil
                                self.updated = true
                            end,
                        },
                        {
                            text_func = function()
                                local interval = v.settings.auto_exec_time_interval
                                return _("Dispatch within time interval") ..
                                    (interval and ": " .. interval[1] .. " - " .. interval[2] or "")
                            end,
                            checked_func = function()
                                return v.settings.auto_exec_time_interval and true
                            end,
                            sub_item_table_func = function()
                                local sub_sub_item_table = {}
                                local points = { _("start: "), _("end: ") }
                                local titles = { _("Set start time"), _("Set end time") }
                                for i, point in ipairs(points) do
                                    sub_sub_item_table[i] = {
                                        text_func = function()
                                            local interval = v.settings.auto_exec_time_interval
                                            return point .. (interval and interval[i] or "--:--")
                                        end,
                                        keep_menu_open = true,
                                        callback = function(touchmenu_instance)
                                            local interval = v.settings.auto_exec_time_interval
                                            local time_str = interval and interval[i] or os.date("%H:%M")
                                            local h, m = time_str:match("(%d+):(%d+)")
                                            UIManager:show(DateTimeWidget:new{
                                                title_text = titles[i],
                                                info_text = _("Enter time in hours and minutes."),
                                                hour = tonumber(h),
                                                min = tonumber(m),
                                                ok_text = _("Set time"),
                                                callback = function(new_time)
                                                    local str = string.format("%02d:%02d", new_time.hour, new_time.min)
                                                    if interval then
                                                        v.settings.auto_exec_time_interval[i] = str
                                                    else
                                                        v.settings.auto_exec_time_interval = { str, str }
                                                    end
                                                    touchmenu_instance:updateItems()
                                                end,
                                            })
                                        end,
                                    }
                                end
                                return sub_sub_item_table
                            end,
                            hold_callback = function(touchmenu_instance)
                                v.settings.auto_exec_time_interval = nil
                                touchmenu_instance:updateItems()
                            end,
                            separator = true,
                        },
                        self:genAutoExecMenuItem(_("on KOReader start"), "Start", k),
                        self:genAutoExecMenuItem(_("on wake-up"), "Resume", k),
                        self:genAutoExecMenuItem(_("on exiting sleep screen"), "OutOfScreenSaver", k),
                        self:genAutoExecMenuItem(_("on rotation"), "SetRotationMode", k),
                        self:genAutoExecMenuItem(_("on showing folder"), "PathChanged", k, true),
                        -- separator
                        self:genAutoExecMenuItem(_("on book opening"), "ReaderReadyAll", k),
                        self:genAutoExecMenuItem(_("on book closing"), "CloseDocumentAll", k),
                    }
                end,
                hold_callback = function(touchmenu_instance)
                    for event, webhooks in pairs(self.autoexec) do
                        if webhooks[k] then
                            util.tableRemoveValue(self.autoexec, event, k)
                        end
                    end
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text = _("Show notification on dispatching"),
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
                        dispatcherUnregisterWebhook(k)
                        self:updateWebhooks(self.prefix..k)
                        self.data[k].settings.registered = nil
                    else
                        dispatcherRegisterWebhook(k)
                        self.data[k].settings.registered = true
                    end
                    self.updated = true
                end,
            },
	    {
                text = T(_("Edit URL: %1"), self.data[k].settings.url),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local function editCallback(new_url)
			    self.data[k].settings.url = new_url
			    self.updated = true
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                    end
                    self:editWebhookName(editCallback, self.data[k].settings.url)
                end,
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
                            dispatcherUnregisterWebhook(k)
                            dispatcherRegisterWebhook(new_name)
                            self:updateWebhooks(self.prefix..k, self.prefix..new_name)
                        end
                        self.data[k] = nil
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                        table.remove(touchmenu_instance.item_table_stack)
                      end
                    self:editWebhookName(editCallback, k)
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
                            dispatcherRegisterWebhook(new_name)
                        end
                        self.updated = true
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance:updateItems()
                        table.remove(touchmenu_instance.item_table_stack)
                      end
                    self:editWebhookName(editCallback, k)
                end,
            },
            {
                text = _("Delete"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Do you want to delete this webhook?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            self:updateAutoExec(k)
                            if v.settings.registered then
                                dispatcherUnregisterWebhook(k)
                                self:updateWebhooks(self.prefix..k)
                            end
                            self.data[k] = nil
                            self.updated = true
                            touchmenu_instance.item_table = self:getSubMenuItems()
                            touchmenu_instance:updateItems()
                            table.remove(touchmenu_instance.item_table_stack)
                        end,
                    })
                end,
                separator = true,
            },
        }
        table.insert(sub_item_table, {
            text_func = function()
                return (v.settings.show_as_quickmenu and "\u{F0CA} " or "\u{F144} ") .. k
            end,
            hold_keep_menu_open = false,
            sub_item_table = sub_items,
            hold_callback = function()
                self:onWebhookExecute(k)
            end,
        })
    end
    return sub_item_table
end

function Webhooks:onWebhookExecute(name)
    if NetworkMgr:willRerunWhenOnline(function() Webhooks:DispatchWebhook(url) end) then
       return
    end

    if self.data[name].settings.notify == true then
	    Notification:notify(_(string.gsub("Dispatching Webhook: {1}","{1}",name)),Notification.SOURCE_ALWAYS_SHOW)
    end

    
    os.execute(string.gsub("curl {1}", "{1}", self.data[name].settings.url))
end

function Webhooks:editWebhookName(editCallback, old_name)
    local name_input
    name_input = InputDialog:new{
        title =  _("Enter webhook name"),
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
                            text = T(_("Webhook already exists: %1"), new_name),
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

function Webhooks:updateWebhooks(action_old_name, action_new_name)
    for _, webhook in pairs(self.data) do
        if webhook[action_old_name] then
            if webhook.settings and webhook.settings.order then
                for i, action in ipairs(webhook.settings.order) do
                    if action == action_old_name then
                        if action_new_name then
                            webhook.settings.order[i] = action_new_name
                        else
                            table.remove(webhook.settings.order, i)
                            if #webhook.settings.order == 0 then
                                webhook.settings.order = nil
                            end
                        end
                        break
                    end
                end
            end
            webhook[action_old_name] = nil
            if action_new_name then
                webhook[action_new_name] = true
            end
            self.updated = true
        end
    end
    if self.ui.gestures then -- search and update the webhook action in assigned gestures
        self.ui.gestures:updateWebhooks(action_old_name, action_new_name)
    elseif self.ui.hotkeys then -- search and update the webhook action in assigned keyboard shortcuts
        self.ui.hotkeys:updateWebhooks(action_old_name, action_new_name)
    end
end

-- AutoExec

function Webhooks:updateAutoExec(old_name, new_name)
    for event, webhooks in pairs(self.autoexec) do
        local old_value
        for webhook_name in pairs(webhooks) do
            if webhooks_name == old_name then
                old_value = webhooks[old_name]
                webhooks[old_name] = nil
                break
            end
        end
        if old_value then
            if new_name then
                webhooks[new_name] = old_value
            else
                if next(webhooks) == nil then
                    self.autoexec[event] = nil
                end
            end
        end
    end
end

function Webhooks:genAutoExecMenuItem(text, event, webhook_name, separator)
    if event == "SetRotationMode" then
        return self:genAutoExecSetRotationModeMenuItem(text, event, webhook_name, separator)
    elseif event == "PathChanged" then
        return self:genAutoExecPathChangedMenuItem(text, event, webhook_name, separator)
    elseif event == "ReaderReadyAll" or event == "CloseDocumentAll" then
        return self:genAutoExecDocConditionalMenuItem(text, event, webhook_name, separator)
    end
    return {
        text = text,
        enabled_func = function()
            if event == "Resume" then
                local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
                return screensaver_delay == nil or screensaver_delay == "disable"
            end
            return true
        end,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, webhook_name)
        end,
        callback = function()
            if util.tableGetValue(self.autoexec, event, webhook_name) then
                util.tableRemoveValue(self.autoexec, event, webhook_name)
            else
                util.tableSetValue(self.autoexec, true, event, webhook_name)
                if event == "ReaderReady" or event == "CloseDocument" then
                    -- "always" is checked, clear all conditional triggers
                    util.tableRemoveValue(self.autoexec, event .. "All", webhook_name)
                end
            end
        end,
        separator = separator,
    }
end

function Webhooks:genAutoExecSetRotationModeMenuItem(text, event, webhook_name, separator)
    return {
        text = text,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, webhook_name) and true
        end,
        sub_item_table_func = function()
            local sub_item_table = {}
            local optionsutil = require("ui/data/optionsutil")
            for i, mode in ipairs(optionsutil.rotation_modes) do
                sub_item_table[i] = {
                    text = optionsutil.rotation_labels[i],
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, mode)
                    end,
                    callback = function()
                        if util.tableGetValue(self.autoexec, event, webhook_name, mode) then
                            util.tableRemoveValue(self.autoexec, event, webhook_name, mode)
                        else
                            util.tableSetValue(self.autoexec, true, event, webhook_name, mode)
                        end
                    end,
                }
            end
            return sub_item_table
        end,
        hold_callback = function(touchmenu_instance)
            util.tableRemoveValue(self.autoexec, event, webhook_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Webhooks:genAutoExecPathChangedMenuItem(text, event, webhook_name, separator)
    return {
        text = text,
        checked_func = function()
            return util.tableGetValue(self.autoexec, event, webhook_name) and true
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
                        local value = util.tableGetValue(self.autoexec, event, webhook_name, conditions[i][2])
                        return value and txt .. ": " .. value or txt
                    end,
                    no_refresh_on_check = true,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[i][2])
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
                                        util.tableRemoveValue(self.autoexec, event, webhook_name, condition)
                                    else
                                        util.tableSetValue(self.autoexec, txt, event, webhook_name, condition)
                                    end
                                    UIManager:close(dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        })
                        dialog = InputDialog:new{
                            title =  _("Enter text contained in folder path"),
                            input = util.tableGetValue(self.autoexec, event, webhook_name, condition),
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
            util.tableRemoveValue(self.autoexec, event, webhook_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Webhooks:genAutoExecDocConditionalMenuItem(text, event, webhook_name, separator)
    local event_always = event:gsub("All", "")
    return {
        text = text,
        checked_func = function()
            return (util.tableGetValue(self.autoexec, event_always, webhook_name) or util.tableGetValue(self.autoexec, event, webhook_name)) and true
        end,
        sub_item_table_func = function()
            local conditions = {
                { _("if device orientation is"), "orientation" },
                { _("if book metadata contains"), "doc_props" },
                { _("if book file path contains"), "filepath" },
                { _("if book is in collections"), "collections" },
                { _("and if book is new"), "is_new" },
            }
            local sub_item_table = {
                self:genAutoExecMenuItem(_("always"), event_always, webhook_name, true),
                -- separator
                {
                    text = conditions[1][1], -- orientation
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, webhook_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[1][2]) and true
                    end,
                    sub_item_table_func = function()
                        local condition = conditions[1][2]
                        local sub_item_table = {}
                        local optionsutil = require("ui/data/optionsutil")
                        for i, mode in ipairs(optionsutil.rotation_modes) do
                            sub_item_table[i] = {
                                text = optionsutil.rotation_labels[i],
                                checked_func = function()
                                    return util.tableGetValue(self.autoexec, event, webhook_name, condition, mode)
                                end,
                                callback = function()
                                    if util.tableGetValue(self.autoexec, event, webhook_name, condition, mode) then
                                        util.tableRemoveValue(self.autoexec, event, webhook_name, condition, mode)
                                    else
                                        util.tableSetValue(self.autoexec, true, event, webhook_name, condition, mode)
                                    end
                                end,
                            }
                        end
                        return sub_item_table
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, webhook_name, conditions[1][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = conditions[2][1], -- doc_props
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, webhook_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[2][2]) and true
                    end,
                    sub_item_table_func = function()
                        local condition = conditions[2][2]
                        local sub_item_table = {}
                        for i, prop in ipairs(self.ui.bookinfo.props) do
                            sub_item_table[i] = {
                                text_func = function()
                                    local title = self.ui.bookinfo.prop_text[prop]:lower()
                                    local txt = util.tableGetValue(self.autoexec, event, webhook_name, condition, prop)
                                    return txt and title .. " " .. txt or title:sub(1, -2)
                                end,
                                no_refresh_on_check = true,
                                checked_func = function()
                                    return util.tableGetValue(self.autoexec, event, webhook_name, condition, prop) and true
                                end,
                                callback = function(touchmenu_instance)
                                    local dialog
                                    local buttons = self.document == nil and {} or {{
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
                                                    util.tableRemoveValue(self.autoexec, event, webhook_name, condition, prop)
                                                else
                                                    util.tableSetValue(self.autoexec, txt, event, webhook_name, condition, prop)
                                                end
                                                UIManager:close(dialog)
                                                touchmenu_instance:updateItems()
                                            end,
                                        },
                                    })
                                    dialog = InputDialog:new{
                                        title =  _("Enter text contained in:") .. " " .. self.ui.bookinfo.prop_text[prop]:sub(1, -2),
                                        input = util.tableGetValue(self.autoexec, event, webhook_name, condition, prop),
                                        buttons = buttons,
                                    }
                                    UIManager:show(dialog)
                                    dialog:onShowKeyboard()
                                end,
                                hold_callback = function(touchmenu_instance)
                                    util.tableRemoveValue(self.autoexec, event, webhook_name, condition, prop)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                        end
                        return sub_item_table
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, webhook_name, conditions[2][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function() -- filepath
                        local txt = conditions[3][1]
                        local value = util.tableGetValue(self.autoexec, event, webhook_name, conditions[3][2])
                        return value and txt .. ": " .. value or txt
                    end,
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, webhook_name)
                    end,
                    no_refresh_on_check = true,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[3][2]) and true
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[3][2]
                        local dialog
                        local buttons = self.document == nil and {} or {{
                            {
                                text = _("Current book"),
                                callback = function()
                                    dialog:addTextToInput(self.document.file)
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
                                        util.tableRemoveValue(self.autoexec, event, webhook_name, condition)
                                    else
                                        util.tableSetValue(self.autoexec, txt, event, webhook_name, condition)
                                    end
                                    UIManager:close(dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        })
                        dialog = InputDialog:new{
                            title =  _("Enter text contained in file path"),
                            input = util.tableGetValue(self.autoexec, event, webhook_name, condition),
                            buttons = buttons,
                        }
                        UIManager:show(dialog)
                        dialog:onShowKeyboard()
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, webhook_name, conditions[3][2])
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function() -- collections
                        local txt = conditions[4][1]
                        local collections = util.tableGetValue(self.autoexec, event, webhook_name, conditions[4][2])
                        if collections then
                            local collections_nb = util.tableSize(collections)
                            return txt .. ": " ..
                                (collections_nb == 1 and self.ui.collections:getCollectionTitle(next(collections))
                                                      or "(" .. collections_nb .. ")")
                        end
                        return txt
                    end,
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, webhook_name)
                    end,
                    no_refresh_on_check = true,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[4][2]) and true
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[4][2]
                        local collections = util.tableGetValue(self.autoexec, event, webhook_name, condition)
                        local caller_callback = function(selected_collections)
                            if next(selected_collections) == nil then
                                util.tableRemoveValue(self.autoexec, event, webhook_name, condition)
                            else
                                util.tableSetValue(self.autoexec, selected_collections, event, webhook_name, condition)
                            end
                            touchmenu_instance:updateItems()
                        end
                        self.ui.collections:onShowCollList(collections or {}, caller_callback, true)
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, webhook_name, conditions[4][2])
                        touchmenu_instance:updateItems()
                    end,
                    separator = true,
                },
                event == "ReaderReadyAll" and {
                    text = conditions[5][1], -- new
                    enabled_func = function()
                        return not util.tableGetValue(self.autoexec, event_always, webhook_name)
                    end,
                    checked_func = function()
                        return util.tableGetValue(self.autoexec, event, webhook_name, conditions[5][2]) and true
                    end,
                    callback = function(touchmenu_instance)
                        local condition = conditions[5][2]
                        if util.tableGetValue(self.autoexec, event, webhook_name, condition) then
                            util.tableRemoveValue(self.autoexec, event, webhook_name, condition)
                        else
                            util.tableSetValue(self.autoexec, true, event, webhook_name, condition)
                        end
                    end,
                    hold_callback = function(touchmenu_instance)
                        util.tableRemoveValue(self.autoexec, event, webhook_name, conditions[5][2])
                        touchmenu_instance:updateItems()
                    end,
                } or nil,
            }
            return sub_item_table
        end,
        hold_callback = function(touchmenu_instance)
            util.tableRemoveValue(self.autoexec, event_always, webhook_name)
            util.tableRemoveValue(self.autoexec, event, webhook_name)
            touchmenu_instance:updateItems()
        end,
        separator = separator,
    }
end

function Webhooks:onStart() -- local event
    if not autostart_done then
        self:executeAutoExecEvent("Start")
        autostart_done = true
    end
end

function Webhooks:onResume() -- global
    self:executeAutoExecEvent("Resume")
end

function Webhooks:onOutOfScreenSaver() -- global
    self:executeAutoExecEvent("OutOfScreenSaver")
end

function Webhooks:onSetRotationMode(mode) -- global
    local event = "SetRotationMode"
    if self.autoexec[event] == nil then return end
    for webhook_name, modes in pairs(self.autoexec[event]) do
        if modes[mode] then
            if self.ui.config then -- close bottom menu to let Dispatcher dispatch webhook
                self.ui.config:onCloseConfigMenu()
            end
            self:executeAutoExec(webhook_name)
        end
    end
end

function Webhooks:onPathChanged(path) -- global
    local event = "PathChanged"
    if self.autoexec[event] == nil then return end
    local function is_match(txt, pattern)
        for str in util.gsplit(pattern, ",") do -- comma separated patterns are allowed
            if util.stringSearch(txt, util.trim(str)) ~= 0 then
                return true
            end
        end
    end
    for webhook_name, conditions in pairs(self.autoexec[event]) do
        local do_execute
        if conditions.has then
            do_execute = is_match(path, conditions.has)
        end
        if do_execute == nil and conditions.has_not then
            do_execute = not is_match(path, conditions.has_not)
        end
        if do_execute then
            self:executeAutoExec(webhook_name)
        end
    end
end

function Webhooks:onReaderReady() -- global
    if not self.ui.reloading then
        self:executeAutoExecEvent("ReaderReady")
        self:executeAutoExecDocConditional("ReaderReadyAll")
    end
end

function Webhooks:onCloseDocument() -- global
    if not self.ui.reloading then
        self:executeAutoExecEvent("CloseDocument")
        self:executeAutoExecDocConditional("CloseDocumentAll")
    end
end

function Webhooks:executeAutoExecEvent(event)
    if self.autoexec[event] == nil then return end
    for webhook_name in pairs(self.autoexec[event]) do
        self:executeAutoExec(webhook_name, event)
    end
end

function Webhooks:executeAutoExec(webhook_name, event)
    local webhook = self.data[webhook_name]
    if webhook == nil then return end
    if webhook.settings.auto_exec_time_interval then
        local now = os.date("%H:%M")
        local start_time, end_time = unpack(webhook.settings.auto_exec_time_interval)
        local do_execute
        if start_time < end_time then
            do_execute = start_time <= now and now <= end_time
        else
            do_execute = (start_time <= now and now <= "23:59") or ("00:00" <= now and now <= end_time)
        end
        if not do_execute then return end
    end
    if webhook.settings.auto_exec_ask then
        UIManager:show(ConfirmBox:new{
            text = _("Do you want to dispatch webhook?") .. "\n\n" .. webhook_name .. "\n",
            ok_text = _("Execute"),
            ok_callback = function()
                logger.dbg("Webhooks - auto executing:", webhook_name)
                UIManager:nextTick(function()
                    self:onWebhookExecute(webhook_name)
                end)
            end,
        })
    else
        logger.dbg("Webhooks - auto executing:", webhook_name)
        if event == "CloseDocument" or event == "CloseDocumentAll" then
            UIManager:tickAfterNext(function()
                self:onWebhookExecute(webhook_name)
            end)
        else
            UIManager:nextTick(function()
                self:onWebhookExecute(webhook_name)
            end)
        end
    end
end

function Webhooks:executeAutoExecDocConditional(event)
    if self.autoexec[event] == nil then return end
    local function is_match(txt, pattern)
        for str in util.gsplit(pattern, ",") do
            if util.stringSearch(txt, util.trim(str)) ~= 0 then
                return true
            end
        end
    end
    for webhook_name, conditions in pairs(self.autoexec[event]) do
        if self.data[webhook_name] then
            local do_execute
            if not conditions.is_new or self.document.is_new then
                for condition, trigger in pairs(conditions) do
                    if condition == "orientation" then
                        local mode = Screen:getRotationMode()
                        do_execute = trigger[mode]
                    elseif condition == "doc_props" then
                        if self.document then
                            for prop_name, pattern in pairs(trigger) do
                                local prop = self.ui.doc_props[prop_name == "title" and "display_title" or prop_name]
                                do_execute = is_match(prop, pattern)
                                if do_execute then
                                    break -- any prop match is enough
                                end
                            end
                        end
                    elseif condition == "filepath" then
                        if self.document then
                            do_execute = is_match(self.document.file, trigger)
                        end
                    elseif condition == "collections" then
                        if self.document then
                            local ReadCollection = require("readcollection")
                            for collection_name in pairs(trigger) do
                                if ReadCollection:isFileInCollection(self.document.file, collection_name) then
                                    do_execute = true
                                    break -- any collection is enough
                                end
                            end
                        end
                    end
                    if do_execute then
                        break -- dispatch webhook only once
                    end
                end
            end
            if do_execute then
                self:executeAutoExec(webhook_name, event)
            end
        end
    end
end

return Webhooks
