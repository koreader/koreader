--[[--
This plugin allows for remotely triggering KOReader events via HTTP.

Refer to frontend/dispatcher.lua for the list of events supported.

Usage:
Send a http request with these parameters:
  event: The event to dispatch.
  data: The data to pass to the event.
  datatype: The data type. Default is string, set to 'number' if data is number.

example url (turn to next page)
localhost:8080/?event=GotoViewRel&data=1&datatype=number
--]]--

local Device =  require("device")
local PowerD = Device:getPowerDevice()
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")

local HttpDispatcher = WidgetContainer:extend{
    name = "httpdispatcher",
    --is_doc_only = true,
}

function HttpDispatcher:init()
    self.port = G_reader_settings:readSetting("httpdispatcher_port", "8080")
    self.autostart = G_reader_settings:isTrue("httpdispatcher_autostart")

    if self.autostart then
        self:start()
    end

    self.ui.menu:registerToMainMenu(self)
end

function HttpDispatcher:onEnterStandby()
    logger.dbg("HttpDispatcher: onEnterStandby")
    self:stop()
end

function HttpDispatcher:onSuspend()
    logger.dbg("HttpDispatcher: onSuspend")
    self:stop()
end

function HttpDispatcher:onExit()
    logger.dbg("HttpDispatcher: onExit")
    self:stop()
end

function HttpDispatcher:onCloseWidget()
    logger.dbg("HttpDispatcher: onCloseWidget")
    self:stop()
end

function HttpDispatcher:onLeaveStandby()
    logger.dbg("HttpDispatcher: onLeaveStandby")
    if self.http_socket == nil then
        self:start()
    end
end

function HttpDispatcher:onResume()
    logger.dbg("HttpDispatcher: onResume")
    if self.http_socket == nil then
        self:start()
    end
end

function HttpDispatcher:start()
    logger.dbg("HttpDispatcher: Starting server...")
    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    local StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
    if self.http_socket == nil then
        self.http_socket = StreamMessageQueueServer:new{
            host = "*",
            port = self.port,
            receiveCallback = self:onRequest(),
        }
        self.http_socket:start()
        self.http_messagequeue = UIManager:insertZMQ(self.http_socket)
    end
    logger.dbg("HttpDispatcher: Server listening on port " .. self.port)
end

function HttpDispatcher:stop()
    logger.dbg("HttpDispatcher: Stopping server...")

    if self.http_socket then
        self.http_socket:stop()
        self.http_socket = nil
    end
    if self.http_messagequeue then
        UIManager:removeZMQ(self.http_messagequeue)
        self.http_messagequeue = nil
    end

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    logger.dbg("HttpDispatcher: Server stopped.")
end

function HttpDispatcher:onRequest(host, port)
    -- NOTE: Closure trickery because we need a reference to *this* self *inside* the callback,
    --       which will be called as a function from another object (namely, StreamMessageQueue).
    local this = self
    return function(data, id_frame)
        local request = string.match(data, "[^\n]+") or ""
        logger.dbg("HttpDispatcher: Received request: " .. request)
        local params_string = request:match("%u+%s+%S+%?([^%s]+)%s+%S+") -- extract params
        logger.dbg("HttpDispatcher: Params: ", params_string)

        local params_arr = {}

        if params_string then
            for params in string.gmatch(params_string, "[^&]+") do
                -- Split each parameter string into key and value using string.match
                local key, value = string.match(params, "(.-)=(.*)")
                if key and value then
                    params_arr[key] = value
                end
            end
        end

        local response = "HTTP/1.1 200 OK" -- start of response header

        if params_arr["event"] and params_arr["data"] then
            if params_arr["datatype"] == "number" then
                this:dispatchEvent(params_arr["event"], tonumber(params_arr["data"]))
            else
                this:dispatchEvent(params_arr["event"], params_arr["data"])
            end
        end

        response = response .. "\r\n\r\n" -- end of response header

        logger.dbg("HttpDispatcher: Sending response: " .. response)
        this.http_socket:send(response, id_frame) -- send the response back to the client
    end
end


function HttpDispatcher:dispatchEvent(event, data)
    logger.dbg("HttpDispatcher: Dispatch event " .. event .. " " .. data)
    self.ui:handleEvent(Event:new(event, data))

    if Device:isKindle() then
        PowerD:resetT1Timeout()
    end
end

function HttpDispatcher:addToMainMenu(menu_items)
    menu_items.httpremote = {
        text = _("HTTP event dispatcher"),
        sorting_hint = ("tools"),
        sub_item_table = {
            {
                text_func = function()
                    if self.http_socket then
                        return _("Stop server")
                    else
                        return _("Start server")
                    end
                end,
                separator = true,
                callback = function()
                    if not self.http_socket then
                        self:start()
                    else
                        self:stop()
                    end
                end,
            },
            {
                text = _("Auto start server"),
                checked_func = function()
                    return self.autostart
                end,
                callback = function()
                    G_reader_settings:toggle("httpdispatcher_autostart")
                    self.autostart = G_reader_settings:isTrue("httpdispatcher_autostart")
                end,
            },
            {
                text_func = function()
                    return "Port: " .. self.port
                end,
                callback = function()
                    local InputDialog = require("ui/widget/multiinputdialog")
                    local port_dialog

                    port_dialog = InputDialog:new{
                        title = _("Set custom port"),
                        fields = {
                            {
                                text = self.port,
                                input_type = "number",
                                hint = _("Port"),
                            },
                        },
                        buttons =  {
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
                                    callback = function()
                                        local port_dialog_input = port_dialog:getInputValue()
                                        if port_dialog_input ~= "" then
                                            local input_port = tonumber(port_dialog_input)
                                            if not input_port or input_port < 1 or input_port > 65355 then
                                                --default port
                                                input_port = 8080
                                            end
                                            self.port = input_port
                                            G_reader_settings:saveSetting("httpdispatcher_port", input_port)

                                            --restart the server
                                            if self.http_socket then
                                                self:stop()
                                                self:start()
                                            end
                                        end
                                        UIManager:close(port_dialog)
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(port_dialog)
                    port_dialog:onShowKeyboard()
                end,
            }
        },
    }
end

return HttpDispatcher
