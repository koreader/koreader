--[[--
message = {
    text,           patterns supported
    name,           displayed in message list and action list
    enabled,        
    registered,     show in action list
    show_as,        message / notification / textviewer
    timeout,        message/notification close timeout
    file,           attach file content to message text
}
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

local Messages = WidgetContainer:extend{
    name = "messages",
    prefix = "show_message__", -- in Dispatcher
    data_file = DataStorage:getSettingsDir() .. "/messages.lua",
}

function Messages:init()
    self.settings = LuaSettings:open(self.data_file)
    self.messages = self.settings:readSetting("messages", {})
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function Messages.dispatcherRegisterMessage(name)
    Dispatcher:registerAction(Messages.prefix..name,
        {category="none", event="ShowMessage", arg=name, title=T(_("Messages: show '%1'"), name), general=true})
end

function Messages.dispatcherUnregisterMessage(name)
    Dispatcher:removeAction(Messages.prefix..name)
end

function Messages:onDispatcherRegisterActions()
    for name, message in pairs(self.messages) do
        if message.registered then
            Messages.dispatcherRegisterMessage(name)
        end
    end
    Dispatcher:registerAction("show_message_list",
        {category="none", event="ShowMessageList", title=_("Messages: show list"), general=true, separator=true})
end

function Messages:addToMainMenu(menu_items)
    menu_items.messages = {
        text = _("Messages"),
        sorting_hint = "more_tools",
        callback = function()
            self:onShowMessageList()
        end,
    }
end

function Messages:onShowMessage(name, force_show)
    local message = self.messages[name]
    if not (message and (message.enabled or force_show)) then return true end
    local text = self.ui.bookinfo:expandString(message.text)
    if message.file then
        local file_content = util.readFromFile(message.file, "rb")
        if file_content then
            text = text and text .. file_content or file_content
        end
    end
    text = text or ""
    if message.show_as == "message" then
        UIManager:show(InfoMessage:new{
            text = text,
            timeout = message.timeout,
        })
    elseif message.show_as == "notification" then
        UIManager:show(Notification:new{
            text = text,
            timeout = message.timeout,
        })
    elseif message.show_as == "textviewer" then
        UIManager:show(TextViewer:new{
            title = name,
            text = text,
            text_type = message.file and "file_content",
        })
    end
    return true
end

-- message list

function Messages:onShowMessageList()
    self.message_list = Menu:new{
        title = _("Messages"),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "plus",
        onLeftButtonTap = function()
            self:addMessage()
        end,
        onMenuChoice = function(_menu_self, item)
            self:onShowMessage(item.text, true)
        end,
        onMenuHold = function(_menu_self, item)
            self:showMessageDialog(item)
        end,
    }
    self:updateMessageListItemTable()
    UIManager:show(self.message_list)
    return true
end

function Messages:updateMessageListItemTable(item_table)
    if item_table == nil then
        item_table = {}
        for name, message in pairs(self.messages) do
            table.insert(item_table, {
                text = name,
                mandatory = self:getMessageListItemMandatory(message),
                dim = not message.enabled or nil,
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
        end
    end
    self.message_list:switchItemTable(nil, item_table, -1)
end

function Messages:getMessageListItemMandatory(message)
    local t = {}
    if message.timeout then
        table.insert(t, message.timeout)
    end
    if message.file then
        table.insert(t, "\u{F016}")
    end
    if message.registered then
        table.insert(t, "\u{F144}")
    end
    return table.concat(t, " ")
end

function Messages:addMessage()
    local function editCallback(new_name)
        self.messages[new_name] = {
            show_as = "message",
            enabled = true,
            registered = true,
        }
        self.updated = true
        Messages.dispatcherRegisterMessage(new_name)
        self:updateMessageListItemTable()
        self:editMessageText(new_name)
    end
    self:editMessageName(editCallback)
end

function Messages:editMessageName(editCallback, old_name)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Enter message name"),
        input = old_name,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    local new_name = input_dialog:getInputText()
                    if new_name == "" or new_name == old_name then return end
                    UIManager:close(input_dialog)
                    if self.messages[new_name] then
                        UIManager:show(InfoMessage:new{
                            text = T(_("Message already exists: %1"), new_name),
                        })
                    else
                        editCallback(new_name)
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Messages:editMessageText(name)
    local message = self.messages[name]
    local input_dialog
    input_dialog = InputDialog:new{
        title = name,
        input = message.text,
        allow_newline = true,
        use_available_height = true,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Info"),
                callback = self.ui.bookinfo.expandString,
            },
            {
                text = _("Show"),
                callback = function()
                    local old_text = message.text
                    message.text = input_dialog:getInputText()
                    self:onShowMessage(name, true)
                    message.text = old_text
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    message.text = input_dialog:getInputText()
                    self.updated = true
                    UIManager:close(input_dialog)
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Messages:showMessageDialog(item)
    local name = item.text
    local message = self.messages[name]
    local message_dialog

    local function setMessageValue(key, value, update_message_list)
        UIManager:close(message_dialog)
        message[key] = value
        if update_message_list then
            item.mandatory = self:getMessageListItemMandatory(message)
            self.message_list:updateItems(1, true)
        end
        self.updated = true
        self:showMessageDialog(item)
    end

    local widget_type_strings = {
        message      = _("Message"),
        notification = _("Notification"),
        textviewer   = _("Text viewer"),
    }
    local function genShowAsButton(widget_type)
        return {
            text = widget_type_strings[widget_type],
            checked_func = function()
                return message.show_as == widget_type
            end,
            callback = function()
                if message.show_as ~= widget_type then
                    setMessageValue("show_as", widget_type)
                end
            end,
        }
    end

    local buttons = {
        {
            genShowAsButton("message"),
            genShowAsButton("notification"),
            genShowAsButton("textviewer"),
        },
        {
            {
                text = _("Attach file") .. (message.file and "  \u{2713}" or ""),
                callback = function()
                    local caller_callback = function(path)
                        setMessageValue("file", path, true)
                    end
                    local file_filter = function() return true end
                    filemanagerutil.showChooseDialog(_("Attached file:"), caller_callback, message.file, nil, file_filter, true)
                end,
            },
            {
                text = message.timeout and T(_("Timeout: %1 s"), message.timeout) or _("Timeout"),
                callback = function()
                    UIManager:show(SpinWidget:new{
                        title_text = _("Timeout"),
                        value = message.timeout or 5,
                        value_min = 1,
                        value_max = 20,
                        value_step = 1,
                        value_hold_step = 2,
                        unit = C_("Time", "s"),
                        precision = "%1d",
                        ok_always_enabled = true,
                        ok_text = _("Set timeout"),
                        callback = function(spin)
                            setMessageValue("timeout", spin.value, true)
                        end,
                        option_text = _("System default"),
                        option_callback = function()
                            setMessageValue("timeout", nil, true)
                        end,
                    })
                end,
            },
        },
        {
            {
                text = _("Rename"),
                callback = function()
                    UIManager:close(message_dialog)
                    local function editCallback(new_name)
                        if message.registered then
                            Messages.dispatcherUnregisterMessage(name)
                            Messages.dispatcherRegisterMessage(new_name)
                            UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                                { old_name = self.prefix..name, new_name = self.prefix..new_name }))
                        end
                        self.messages[name] = nil
                        self.messages[new_name] = message
                        self:updateMessageListItemTable()
                        self.updated = true
                    end
                    self:editMessageName(editCallback, name)
                end,
            },
            {
                text = _("Edit"),
                callback = function()
                    UIManager:close(message_dialog)
                    self:editMessageText(name)
                end,
            },
        },
        {
            {
                text = message.enabled and _("Disable") or _("Enable"),
                callback = function()
                    UIManager:close(message_dialog)
                    item.dim = message.enabled or nil
                    message.enabled = not message.enabled
                    self.message_list:updateItems(1, true)
                    self.updated = true
                    if message.enabled then
                        self:showMessageDialog(item)
                    end
                end,
            },
            {
                text = _("Show in action list"),
                checked_func = function()
                    return message.registered
                end,
                callback = function()
                    if message.registered then
                        Messages.dispatcherUnregisterMessage(name)
                        UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                            { old_name = self.prefix..name, new_name = nil }))
                        message.registered = false
                    else
                        Messages.dispatcherRegisterMessage(name)
                        message.registered = true
                    end
                    item.mandatory = self:getMessageListItemMandatory(message)
                    self.message_list:updateItems(1, true)
                    self.updated = true
                end,
            },
        },
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete message?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            UIManager:close(message_dialog)
                            if message.registered then
                                Messages.dispatcherUnregisterMessage(name)
                                UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                                    { old_name = self.prefix..name, new_name = nil }))
                            end
                            self.messages[name] = nil
                            table.remove(self.message_list.item_table, item.idx)
                            self.message_list:updateItems(1, true)
                            self.updated = true
                        end,
                    })
                end,
            },
            {
                text = _("Show"),
                callback = function()
                    self:onShowMessage(name, true)
                end,
            },
        },
    }

    message_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(message_dialog)
end

function Messages:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

function Messages:stopPlugin()
    for name, message in pairs(self.messages) do
        if message.registered then
            Messages.dispatcherUnregisterMessage(name)
            UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                { old_name = self.prefix..name, new_name = nil }))
        end
    end
end

return Messages
