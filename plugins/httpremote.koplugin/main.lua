local Device =  require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local socket = require("socket")
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

    self.task = function()
        self:httpListen()
    end

    if self.autostart then
        self:start()
    end

    self.ui.menu:registerToMainMenu(self)
end

function HttpRemote:start()
    self.server = socket.bind("*", self.port)
    self.server:settimeout(0.01) -- set timeout (10ms)
    logger.dbg("HttpRemote: Server listening on port " .. self.port)

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    -- start listening
    UIManager:scheduleIn(0.01, self.task)
end

function HttpRemote:stop()
    if self.server then
        logger.dbg("HttpRemote: Server stopped.")
        self.server:close()
        self.server = nil

        -- stop listening
        UIManager:unschedule(self.task)

        -- Plug the hole in the Kindle's firewall
        if Device:isKindle() then
            os.execute(string.format("%s %s %s",
                "iptables -D INPUT -p tcp --dport", self.port,
                "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
            os.execute(string.format("%s %s %s",
                "iptables -D OUTPUT -p tcp --sport", self.port,
                "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
        end
    else
        logger.dbg("HttpRemote: No server running.")
    end
end

function HttpRemote:httpListen()
    if self.server then
        local client = self.server:accept() -- wait for a client to connect
        if client then
            self:onRequest(client) -- handle the request
            client:close() -- close the connection to the client
        end
        UIManager:scheduleIn(0.01, self.task)
    end
end

function HttpRemote:onRequest(client)
    local request = client:receive("*l") -- read the first line of the request

    logger.dbg("HttpRemote: Received request: " .. request)
    local method, path, params, version = request:match("(%u+)%s+(%S+)%?([^%s]+)%s+(%S+)") -- extract method, path, params and version

    local params_arr = {}

    if params then
        for params in string.gmatch(params, "[^&]+") do
            -- Split each parameter string into key and value using string.match
            local key, value = string.match(params, "(.-)=(.*)")
            params_arr[key] = value
        end
    end

    local response = "HTTP/1.1 200 OK" -- start of response header

    if params_arr["action"] == "nextpage" then
        self:turnPage(1)
    elseif params_arr["action"] == "prevpage" then
        self:turnPage(-1)
    else
        response = response .. "\r\nContent-Type: text/html"
    end

    response = response .. "\r\n\r\n" -- end of response header

    -- response body (if available)
    -- if loadpage param is populated, load the html
    if not params or params_arr["loadpage"] then
        response = response .. [[
<html><body>
<h1>KOReader HttpRemote</h1>
<h2>Available actions</h2>
<p>
<a href="/?action=prevpage&loadpage=1">prevpage</a>
<a href="/?action=nextpage&loadpage=1">nextpage</a>
</p>
</body></html>
        ]]
    end

    client:send(response) -- send the response back to the client
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
                    if self.server then
                        return _("Stop server")
                    else
                        return _("Start server")
                    end
                end,
                separator = true,
                callback = function()
                    if not self.server then
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
                                        local port = port_dialog:getInputValue()
                                        if port ~= "" then
                                            local port = tonumber(port)
                                            if not port or port < 1 or port > 65355 then
                                                --default port
                                                 port = 8080
                                            end
                                            self.port = port
                                            G_reader_settings:saveSetting("httpremote_port", port )

                                            --restart the server
                                            self:stop()
                                            self:start()
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
