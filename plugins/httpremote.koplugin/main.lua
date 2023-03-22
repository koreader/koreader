local Device =  require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")

local HttpRemote = WidgetContainer:extend{
    name = "httpremote",
    is_doc_only = true,
}

function HttpRemote:init()
    self.port = G_reader_settings:readSetting("httpremote_port", "8080")
    self.autostart = G_reader_settings:isTrue("httpremote_autostart")

    if self.autostart then
        self:start()
    end

    self.ui.menu:registerToMainMenu(self)
end

function HttpRemote:initHttpMQ(host, port)
    local StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
    if self.http_socket == nil then
        self.http_socket = StreamMessageQueueServer:new{
            host = host,
            port = port,
            receiveCallback = self:onRequest(),
        }
        self.http_socket:start()
        self.http_messagequeue = UIManager:insertZMQ(self.http_socket)
    end
    logger.info(string.format("connecting to calibre @ %s:%s", host, port))
end

function HttpRemote:onEnterStandby()
    logger.dbg("HttpRemote: onEnterStandby")
    self:stop()
end

function HttpRemote:onSuspend()
    logger.dbg("HttpRemote: onSuspend")
    self:stop()
end

function HttpRemote:onExit()
    logger.dbg("HttpRemote: onExit")
    self:stop()
end

function HttpRemote:onCloseWidget()
    logger.dbg("HttpRemote: onCloseWidget")
    self:stop()
end

function HttpRemote:onLeaveStandby()
    logger.dbg("HttpRemote: onLeaveStandby")
    if self.http_socket == nil then
        self:start()
    end
end

function HttpRemote:onResume()
    logger.dbg("HttpRemote: onResume")
    if self.http_socket == nil then
        self:start()
    end
end

function HttpRemote:start()
    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    self:initHttpMQ("*", self.port)
    logger.dbg("HttpRemote: Server listening on port " .. self.port)
end

function HttpRemote:stop()
    logger.info("HttpRemote: Stopping server...")

    if self.http_socket then
        self.http_socket:stop()
        self.http_socket = nil
    end
    if self.http_messagequeue then
        UIManager:removeZMQ(self.http_messagequeue)
        self.http_messagequeue = nil
    end

    logger.dbg("HttpRemote: Server stopped.")

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
end

function HttpRemote:onRequest(host, port)
    -- NOTE: Closure trickery because we need a reference to *this* self *inside* the callback,
    --       which will be called as a function from another object (namely, StreamMessageQueue).
    local this = self
    return function(data, id_frame)
        local request = string.match(data, "[^\n]+") or ""
        logger.dbg("HttpRemote: Received request: " .. request)
        local params_string = request:match("%u+%s+%S+%?([^%s]+)%s+%S+") -- extract params
        logger.dbg("HttpRemote: Params: ", params_string)

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

        if params_arr["action"] == "nextpage" then
            this:turnPage(1)
        elseif params_arr["action"] == "prevpage" then
            this:turnPage(-1)
        else
            response = response .. "\r\nContent-Type: text/html"
        end

        response = response .. "\r\n\r\n" -- end of response header

        -- response body (if available)
        -- if loadpage param is populated, load the html
        if next(params_arr) == nil or params_arr["loadpage"] then
            response = response .. [[
<html><body>
<h1>KOReader HttpRemote</h1>
<h2>Available actions</h2>
<p>
<a href="/?action=prevpage&loadpage=1">prevpages</a>
<a href="/?action=nextpage&loadpage=1">nextpage</a>
</p>
</body></html>
            ]]
        end
        logger.dbg("HttpRemote: Sending response: " .. response)
        this.http_socket:send(response, id_frame) -- send the response back to the client
    end
end

function HttpRemote:turnPage(pages)
    local top_wg = UIManager:getTopmostVisibleWidget() or {}
    if top_wg.name == "ReaderUI" then
        logger.dbg("HttpRemote: Sent event GotoViewRel " .. pages)
        self.ui:handleEvent(Event:new("GotoViewRel", pages))
    end
end

function HttpRemote:addToMainMenu(menu_items)
    menu_items.httpremote = {
        text = _("HTTP remote page turner"),
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
                    G_reader_settings:toggle("httpremote_autostart")
                    self.autostart = G_reader_settings:isTrue("httpremote_autostart")
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
                                            G_reader_settings:saveSetting("httpremote_port", input_port)

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

return HttpRemote
