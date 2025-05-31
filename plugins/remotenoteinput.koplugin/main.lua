-- This plugin allows you type notes into KOReader from any browser-enabled device on the same local network
local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local RemoteNoteInput = WidgetContainer:extend {
    name = "remotenoteinput",
}

local should_auto_run = G_reader_settings:isTrue("remotenoteinput_autostart")

function RemoteNoteInput:init()
    self.port = G_reader_settings:readSetting("remotenoteinput_port", "8088")
    if should_auto_run then
        UIManager:nextTick(function()
            self:start()
        end)
    end
    self.ui.menu:registerToMainMenu(self)
end

function RemoteNoteInput:isRunning()
    return self.http_socket ~= nil
end

function RemoteNoteInput:start()
    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    local ServerClass = require("ui/message/simpletcpserver")
    self.http_socket = ServerClass:new {
        host = "*",
        port = self.port,
        receiveCallback = function(data, id)
            return self:onRequest(data, id)
        end,
    }
    self.http_socket:start()
    self.http_messagequeue = UIManager:insertZMQ(self.http_socket)
end

function RemoteNoteInput:stop()
    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    if self.http_socket then
        self.http_socket:stop()
        self.http_socket = nil
    end
    if self.http_messagequeue then
        UIManager:removeZMQ(self.http_messagequeue)
        self.http_messagequeue = nil
    end
end

function RemoteNoteInput:onEnterStandby()
    if self:isRunning() then
        self:stop()
    end
end

function RemoteNoteInput:onSuspend()
    if self:isRunning() then
        self:stop()
    end
end

function RemoteNoteInput:onExit()
    if self:isRunning() then
        self:stop()
    end
end

function RemoteNoteInput:onCloseWidget()
    if self:isRunning() then
        self:stop()
    end
end

function RemoteNoteInput:onLeaveStandby()
    if should_auto_run and not self:isRunning() then
        self:start()
    end
end

function RemoteNoteInput:onResume()
    if should_auto_run and not self:isRunning() then
        self:start()
    end
end

function RemoteNoteInput:parse_http_request(data, request_id)
    local request = {
        request_id = request_id,
        method = nil,
        uri = nil,
        headers = {},
        body = ""
    }

    request.method, request.uri = data:match("^(%u+) ([^%s]+) HTTP/%d%.%d\r?\n")
    if not request.method or not request.uri then
        return nil
    end

    for key, value in data:gmatch("\r?\n([^:]+):%s*([^\r\n]*)") do
        request.headers[key:lower()] = value
    end

    local header_end = data:find("\r\n\r\n", 1, true) or data:find("\n\n", 1, true)
    if header_end then
        request.body = data:sub(header_end + 4)
    end

    return request
end

local HTTP_STATUS_CODES = {
    [200] = 'OK',
    [201] = 'Created',
    [202] = 'Accepted',
    [204] = 'No Content',
    [301] = 'Moved Permanently',
    [302] = 'Found',
    [304] = 'Not Modified',
    [400] = 'Bad Request',
    [401] = 'Unauthorized',
    [403] = 'Forbidden',
    [404] = 'Not Found',
    [405] = 'Method Not Allowed',
    [406] = 'Not Acceptable',
    [408] = 'Request Timeout',
    [410] = 'Gone',
    [500] = 'Internal Server Error',
    [501] = 'Not Implemented',
    [503] = 'Service Unavailable',
}

local CONTENT_TYPES = {
    CSS = "text/css",
    HTML = "text/html",
    JS = "application/javascript",
    JSON = "application/json",
    PNG = "image/png",
    TEXT = "text/plain",
}

function RemoteNoteInput:renderHtml(file_name, ...)
    local html_file_path = self.path .. "/html/" .. file_name
    local f = assert(io.open(html_file_path, "r"), "File not found: " .. file_name)
    local html = f:read("*a")
    f:close()
    return T(html, ...)
end

function RemoteNoteInput:renderRemoteNoteInputHtml()
    return self:renderHtml("remote-note-input.html",
        _("Remote Note Input"),
        _("Write down your thoughts about this highlight..."),
        _("Send to KOReader"),
        _([[Usage tip: After highlighting text in KOReader, tap “Add Note” from the popup menu to open the note
editor. You can then type your note on this webpage and tap “Send” — the text will be automatically appended
to the current note input field in KOReader, making input faster and easier.]]),
        _("Please enter some text"),
        _("Sending..."),
        _("Network error"),
        _("Sent successfully"),
        _("Failed to send"),
        _("Failed to send"),
        _("Send to KOReader")
    )
end

function RemoteNoteInput:render404Html()
    return self:renderHtml("404.html",
        _("The page you're looking for can't be found."),
        _("Return Home")
    )
end

function RemoteNoteInput:onRequest(data, request_id)
    local request = self:parse_http_request(data, request_id)
    local uri = request.uri
    local method = request.method

    if method == "GET" then
        if util.stringStartsWith(uri, "/remote-note-input") then
            local html = self:renderRemoteNoteInputHtml()
            self:sendResponse(request.request_id, 200, CONTENT_TYPES.HTML, html)
        else
            local html = self:render404Html()
            self:sendResponse(request.request_id, 200, CONTENT_TYPES.HTML, html)
        end
    elseif method == "POST" then
        if util.stringStartsWith(uri, "/send-note") then
            local isAdded = self:addTextToNoteInput(request.body)
            local message
            if isAdded then
                message = _("Send Success")
            else
                message = _("Edit note dialog is not open, Please open it to receive text")
            end
            self:sendResponse(request.request_id, 200, CONTENT_TYPES.JSON, T("{\"code\": 0, \"message\": \"%1\"}", message))
        end
    else
        self:sendResponse(request.request_id, 405, CONTENT_TYPES.TEXT, "Method Not Allowed")
    end
end

function RemoteNoteInput:addTextToNoteInput(text)
    local isAdded = false
    for widget in UIManager:topdown_widgets_iter() do
        if widget.title == _("Edit note") then
            widget:addTextToInput(text)
            isAdded = true
            break
        end
    end
    return isAdded
end

function RemoteNoteInput:sendResponse(request_id, status_code, content_type, body)
    if not status_code then
        status_code = 400
    end
    if not body then
        body = ""
    end
    if type(body) ~= "string" then
        body = tostring(body)
    end

    local response = {}
    table.insert(response, T("HTTP/1.0 %1 %2", status_code, HTTP_STATUS_CODES[status_code] or "Unspecified"))

    if content_type then
        local charset = ""
        if util.stringStartsWith(content_type, "text/") then
            charset = "; charset=utf-8"
        end
        table.insert(response, T("Content-Type: %1%2", content_type, charset))
    end

    table.insert(response, T("Content-Length: %1", #body))
    table.insert(response, "Connection: close")
    table.insert(response, "")
    table.insert(response, body)
    response = table.concat(response, "\r\n")
    if self.http_socket then
        logger.dbg("self.http_socket:send(response, request_id)")
        self.http_socket:send(response, request_id)
    end
end

function RemoteNoteInput:isConnected()
    if not Device:hasWifiToggle() then
        return true
    end
end

function RemoteNoteInput:getWebPageUrl()
    if Device.retrieveNetworkInfo then
        local info = Device:retrieveNetworkInfo()
        if not info then
            return nil
        end

        local ip
        for line in info:gmatch("[^\r\n]+") do
            if line:find("IP") then
                ip = line:match("(%d+%.%d+%.%d+%.%d+)")
                if ip then
                    break
                end
            end
        end
        if not ip then
            return nil
        end
        return T("http://%1:%2/remote-note-input", ip, self.port)
    else
        return nil
    end
end

function RemoteNoteInput:getWebPageUrlMenuText()
    if self:isRunning() then
        local url = self:getWebPageUrl()
        if url then
            return T(_("Go to: %1"), url)
        else
            return T(_("No address available"))
        end
    else
        return _("Not Running")
    end
end

function RemoteNoteInput:addToMainMenu(menu_items)
    menu_items.remote_note_input = {
        text = _("Remote Note Input"),
        sorting_hint = ("more_tools"),
        sub_item_table = {
            {
                text_func = function()
                    if self:isRunning() then
                        return _("Stop Server")
                    else
                        return _("Start Server")
                    end
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:isRunning() then
                        self:stop()
                    else
                        self:start()
                    end
                    touchmenu_instance:updateItems()
                end
            },
            {
                text_func = function()
                    return self:getWebPageUrlMenuText()
                end,
                enabled_func = function()
                    return self:isRunning()
                end,
                callback = function()
                    UIManager:show(InfoMessage:new {
                        text = self:getWebPageUrlMenuText(),
                    })
                end,
                separator = true,
            },
            {
                text = _("Auto start server"),
                checked_func = function()
                    return G_reader_settings:isTrue("remotenoteinput_autostart")
                end,
                callback = function(touchmenu_instance)
                    G_reader_settings:flipNilOrFalse("remotenoteinput_autostart")
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text_func = function()
                    return T(_("Port: %1"), self.port)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local port_dialog
                    port_dialog = InputDialog:new {
                        title = _("Set custom port"),
                        input = self.port,
                        input_type = "number",
                        input_hint = _("Port number (default is 8088)"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(port_dialog)
                                    end,
                                },
                                {
                                    text = _("OK"),
                                    -- keep_menu_open = true,
                                    callback = function()
                                        local port = port_dialog:getInputValue()
                                        if port and port >= 1 and port <= 65535 then
                                            self.port = port
                                            G_reader_settings:saveSetting("remotenoteinput_port", port)
                                            if self:isRunning() then
                                                self:stop()
                                                self:start()
                                            end
                                        end
                                        UIManager:close(port_dialog)
                                        touchmenu_instance:updateItems()
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(port_dialog)
                    port_dialog:onShowKeyboard()
                end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(InfoMessage:new {
                        text = _("Remote Note Input lets you type text in a browser on any device over local Wi-Fi and send it directly to KOReader’s note editor. It’s especially useful when using input methods like Pinyin that require word selection. Make sure the “Edit note” dialog is open in KOReader before sending."),
                    })
                    touchmenu_instance:updateItems()
                end,
            }
        },
    }
end

return RemoteNoteInput
