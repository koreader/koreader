-- This plugin allows for inspecting KOReader's internal objects,
-- calling methods, sending events... over HTTP.

local DataStorage = require("datastorage")
local Device =  require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local HttpInspector = WidgetContainer:extend{
    name = "httpinspector",
}

-- A plugin gets instantiated on each document load and reader/FM switch.
-- Ensure autostart only on KOReader startup, and keep the running state
-- across document load and reader/FM switch.
local should_run = G_reader_settings:isTrue("httpinspector_autostart")

function HttpInspector:init()
    self.port = G_reader_settings:readSetting("httpinspector_port", "8080")
    if should_run then
        -- Delay this until after all plugins are loaded
        UIManager:nextTick(function()
            self:start()
        end)
    end
    self.ui.menu:registerToMainMenu(self)
end

function HttpInspector:isRunning()
    return self.http_socket ~= nil
end

function HttpInspector:onEnterStandby()
    logger.dbg("HttpInspector: onEnterStandby")
    if self:isRunning() then
        self:stop()
    end
end

function HttpInspector:onSuspend()
    logger.dbg("HttpInspector: onSuspend")
    if self:isRunning() then
        self:stop()
    end
end

function HttpInspector:onExit()
    logger.dbg("HttpInspector: onExit")
    if self:isRunning() then
        self:stop()
    end
end

function HttpInspector:onCloseWidget()
    logger.dbg("HttpInspector: onCloseWidget")
    if self:isRunning() then
        self:stop()
    end
end

function HttpInspector:onLeaveStandby()
    logger.dbg("HttpInspector: onLeaveStandby")
    if should_run and not self:isRunning() then
        self:start()
    end
end

function HttpInspector:onResume()
    logger.dbg("HttpInspector: onResume")
    if should_run and not self:isRunning() then
        self:start()
    end
end

function HttpInspector:start()
    logger.dbg("HttpInspector: Starting server...")

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    -- Using a simple LuaSocket based TCP server instead of a ZeroMQ based one
    -- seems to solve strange issues with Chrome.
    -- local ServerClass = require("ui/message/streammessagequeueserver")
    local ServerClass = require("ui/message/simpletcpserver")
    self.http_socket = ServerClass:new{
        host = "*",
        port = self.port,
        receiveCallback = function(data, id) return self:onRequest(data, id) end,
    }
    local ok, err = self.http_socket:start()
    if ok then
        self.http_messagequeue = UIManager:insertZMQ(self.http_socket)
        logger.dbg("HttpInspector: Server listening on port " .. self.port)
    else
        logger.err("HttpInspector: Failed to start server:", err)
        self.http_socket = nil
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = T(_("Failed to start HTTP inspector on port %1."), self.port) .. "\n\n" .. err,
        })
    end
end

function HttpInspector:stop()
    logger.dbg("HttpInspector: Stopping server...")

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

    logger.dbg("HttpInspector: Server stopped.")
end

function HttpInspector:addToMainMenu(menu_items)
    menu_items.httpremote = {
        text = _("KOReader HTTP inspector"),
        sorting_hint = ("more_tools"),
        sub_item_table = {
            {
                text_func = function()
                    if self:isRunning() then
                        return _("Stop HTTP server")
                    else
                        return _("Start HTTP server")
                    end
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:isRunning() then
                        should_run = false
                        self:stop()
                    else
                        should_run = true
                        self:start()
                    end
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text_func = function()
                    if self:isRunning() then
                        return T(_("Listening on port %1"), self.port)
                    else
                        return _("Not running")
                    end
                end,
                enabled_func = function()
                    return self:isRunning()
                end,
                separator = true,
            },
            {
                text = _("Auto start HTTP server"),
                checked_func = function()
                    return G_reader_settings:isTrue("httpinspector_autostart")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("httpinspector_autostart")
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
                    port_dialog = InputDialog:new{
                        title = _("Set custom port"),
                        input = self.port,
                        input_type = "number",
                        input_hint = _("Port number (default is 8080)"),
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
                                    -- keep_menu_open = true,
                                    callback = function()
                                        local port = port_dialog:getInputValue()
                                        logger.warn("port", port)
                                        if port and port >= 1 and port <= 65535 then
                                            self.port = port
                                            G_reader_settings:saveSetting("httpinspector_port", port)
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
            }
        },
    }
end

local HTTP_RESPONSE_CODE = {
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

local CTYPE = {
    CSS   = "text/css",
    HTML  = "text/html",
    JS    = "application/javascript",
    JSON  = "application/json",
    PNG   = "image/png",
    TEXT  = "text/plain",
}

function HttpInspector:sendResponse(reqinfo, http_code, content_type, body)
    if not http_code then http_code = 400 end
    if not body then body = "" end
    if type(body) ~= "string" then body = tostring(body) end

    local response = {}
    -- StreamMessageQueueServer:send() closes the connection, so announce
    -- that with HTTP/1.0 and a "Connection: close" header.
    table.insert(response, T("HTTP/1.0 %1 %2", http_code, HTTP_RESPONSE_CODE[http_code] or "Unspecified"))
    -- If no content type provided, let the browser sniff it
    if content_type then
        -- Advertise all our text as being UTF-8
        local charset = ""
        if util.stringStartsWith(content_type, "text/") then
            charset = "; charset=utf-8"
        end
        table.insert(response, T("Content-Type: %1%2", content_type, charset))
    end
    if http_code == 302 then
        table.insert(response, T("Location: %1", body))
        body = ""
    end
    table.insert(response, T("Content-Length: %1", #body))
    table.insert(response, "Connection: close")
    table.insert(response, "")
    table.insert(response, body)
    response = table.concat(response, "\r\n")
    logger.dbg("HttpInspector: Sending response: " .. response:sub(1, 200))
    if self.http_socket then -- in case the plugin is gone...
        self.http_socket:send(response, reqinfo.request_id)
    end
    return Event:new("InputEvent") -- as a key event, reset any standby/suspend timer
end

-- Process a uri, stepping one fragment (consider ? / = as separators)
local stepUriFragment = function(uri)
    local ftype, fragment, remain = uri:match("^([/=?]*)([^/=?]+)(.*)$")
    if ftype then
        return ftype, fragment, remain
    end
    -- it ends with a separator: return it
    return uri, nil, nil
end

-- Parse multiple variables from uri, guessing their Lua type
-- ie with uri: nil/true/false/"true"/-1.2/"/"/abc/""/'d"/ef'/
--   Nb args: 9
--   1: nil: nil
--   2: boolean: true
--   3: boolean: false
--   4: string: true
--   5: number: -1.2
--   6: string: /
--   7: string: abc
--   8: string:
--   9: string: d"/ef
local getVariablesFromUri = function(uri)
    local vars = {}
    local nb_vars = 0
    if not uri then
        return vars, nb_vars
    end
    local stop_char
    local var_start_idx
    local var_end_idx
    local end_idx = #uri
    local quoted
    for i = 1, end_idx do
        local c = uri:sub(i,i)
        local skip = false
        if not stop_char then
            if c == "'" or c == '"' then
                stop_char = c
                var_start_idx = i + 1
                quoted = true
                skip = true
            elseif c == "/" then
                skip = true
            else
                stop_char = "/"
                var_start_idx = i
                quoted = false
            end
        end
        if not skip then
            if c == stop_char or i == end_idx then
                var_end_idx = c == stop_char and i-1 or i
                local text = uri:sub(var_start_idx, var_end_idx)
                    -- (We properly get an empty string if var_end_idx<var_start_idx)
                local var
                if quoted then
                    var = text -- as string
                else
                    if text == "true" then
                        var = true
                    elseif text == "false" then
                        var = false
                    elseif text == "nil" or text == "" then
                        var = nil
                    else
                        var = tonumber(text) or text
                    end
                end
                -- table.insert(vars, var) would not work with nil, so we assign
                -- directly to the index, and will return the nb of args
                nb_vars = nb_vars + 1
                vars[nb_vars] = var
                stop_char = nil
                quoted = false
            end
        end
    end
    return vars, nb_vars
end

-- Return object/table as a json string
-- May fail if recursive references, use with pcall()
local getAsJsonString = function(obj)
    local encoder_options = {}
    encoder_options.preProcess = function(value, isObjectKey)
        local value_type = type(value)
        if value_type == "function" then
            return "function"
        end
        if value_type == "cdata" then
            return "cdata"
        end
        if value_type == "userdata" then
            return "userdata"
        end
    end
    -- May fail with recursive data
    local JSON = require("json")
    return JSON.encode(obj, encoder_options)
end

-- We cache the results of the next function, to avoid opening and reading
-- each source file each time
local _function_info_cache = {}

-- Get info about a function object
local getFunctionInfo = function(func, full_code)
    local info = debug.getinfo( func, "S" )
    local src, firstline, lastline = info.source, info.linedefined, info.lastlinedefined
    if firstline < 0 then
        -- With builtin or C functions, we get: [C] -1 -1
        -- Get something like "function: builtin" or "function: 0x7f5931f03828" instead
        src = string.format("%s", func)
    end
    local hash = src.."#"..firstline.."#"..lastline
    if _function_info_cache[hash] and not full_code then
        return _function_info_cache[hash]
    end
    local path = src:match("^@(.*)$")
    local lines = nil
    if path and info.what == "Lua" then
        local f = io.open(path)
        if f then
            local num = 1
            while true do
                local line = f:read('*line')
                if not line then
                    break
                end
                if num >= firstline then
                    if not lines then
                        lines = {}
                    end
                    table.insert(lines, line)
                end
                if num >= lastline then
                    break
                end
                num = num + 1
            end
            f:close()
        end
    end
    info = {
        source = path,
        firstline = firstline,
        lastline = lastline,
    }
    if lines then
        local signature = util.trim(lines[1])
        info.signature = signature
        -- Try to guess (possibly wrongly) a few info from the signature string
        local dummy, cnt
        dummy, cnt = signature:gsub("%(%)","") -- check for "()", no arg
        if cnt > 0 then
            info.nb_args = 0
        else
            dummy, cnt = signature:gsub(",","") -- check for nb of commas
            info.nb_args = cnt and cnt + 1 or 1
        end
        dummy, cnt = signature:gsub("%.%.%.","") -- check for "...", varargs
        if cnt > 0 then
            info.nb_args = -1
        end
        dummy, cnt = signature:gsub("^[^(]*:","")
        info.is_method = cnt > 0
        info.classname = signature:gsub(".-(%w+):.*","%1")
    else
        -- possibly some Lua builtin function or from some C-module
        lines = {}
        info.source = "builtin or C module"
        info.no_source = true
        info.signature = src
        info.nb_args = -1
        info.is_method = false
        info.classname = ""
    end
    if hash then
        _function_info_cache[hash] = info
    end
    if not full_code then
        return info
    end
    info = util.tableDeepCopy(info)
    info.lines = lines
    return info
end

-- Guess class name of an object
local guessClassName = function(obj)
    -- Look for some common methods we could infer a class from (add more as needed)
    local classic_method_names = {
        "init",
        "new",
        "getSize",
        "paintTo",
        "onReadSettings",
        "onResume",
        "onSuspend",
        "onMenuHold",
        "beforeSuspend",
        "initNetworkManager",
        "free",
        "clear",
    }
    -- For an instance, we won't probably find them in the table itself, so we'll have to look
    -- into its first metatable
    local meta_table = getmetatable(obj)
    local test_method, meta_test_method
    for _, method_name in ipairs(classic_method_names) do
        test_method = rawget(obj, method_name)
        if test_method then
            break
        end
        if meta_table and not meta_test_method then
            meta_test_method = rawget(meta_table, method_name)
        end
    end
    if not test_method then
        test_method = meta_test_method
    end
    if test_method then
        local func_info = getFunctionInfo(test_method)
        return func_info.classname
    end
end

-- Nothing below is made available to translators: we output technical details
-- in HTML, for power users and developers, who should be fine with english.
local HOME_CONTENT = [[
<html>
<head><title>KOReader inspector</title></head>
<body>
<pre wrap>
<big>Welcome to KOReader inspector HTTP server!</big>

This service is aimed at developers, <mark>use at your own risk</mark>.

<big>Browse core objects:</big>
<li><a href="ui/">ui</a>           the current application (ReaderUI or FileManager).
<li><a href="device/">device</a>       the Device object (get a screenshot: <a href="device/screen/bb">device/screen/bb</a>).
<li><a href="UIManager/">UIManager</a>    and its <a href="UIManager/_window_stack/">window stack</a>.
<li><a href="g_settings/">g_settings</a>   your global settings saved as settings.reader.lua.
<li><a href="globals/">globals</a>      the global namespace

<big>Send an event:</big>
<li><a href="event/">list of dispatcher/gestures actions</a>.
<li>(or <a href="broadcast/">broadcast an event</a> if you know what you are doing.)
</pre>
</body>
</html>
]]
-- Other ideas for entry points:
-- - Browse filesystem, koreader and library, allow upload of books
-- - Stream live crash.log

-- Process HTTP request
function HttpInspector:onRequest(data, request_id)
    -- Keep track of request info so nested calls can send the response
    local reqinfo = {
        request_id = request_id,
        fragments = {},
    }
    local method, uri = data:match("^(%u+) ([^\n]*) HTTP/%d%.%d\r?\n.*")
    -- We only need to support GET, with our special simple URI syntax/grammar
    if method ~= "GET" then
        return self:sendResponse(reqinfo, 405, CTYPE.TEXT, "Only GET supported")
    end
    reqinfo.uri = uri
    -- Decode any %-encoded stuff (should be ok to do it that early)
    uri = util.urlDecode(uri)
    logger.dbg("HttpInspector: Received request:", method, uri)

    if not util.stringStartsWith(uri, "/koreader/") then
        -- Anything else is static content.
        -- We allow the user to put anything he'd like to in /koreder/web/ and have
        -- this content served as the main content, which can allow building a web
        -- app with HTML/CSS/JS to interact with the API exposed under /koreader/.
        if uri == "/" then
            uri = "/index.html"
        end
        -- No security/sanity check for now
        local filepath = DataStorage:getDataDir() .. "/web" .. uri
        if uri == "/favicon.ico" then -- hijack this one to return our icon
            filepath = "resources/koreader.png"
        end
        local f = io.open(filepath, "rb")
        if f then
            data = f:read("*all")
            f:close()
            return self:sendResponse(reqinfo, 200, nil, data) -- let content-type be sniffed
        end
        if uri == "/index.html" then
            -- / but no /web/index.html created by the user: redirect to our /koreader/
            return self:sendResponse(reqinfo, 302, nil, "/koreader/")
        end
        return self:sendResponse(reqinfo, 404, CTYPE.TEXT, "Static file not found: koreader/web" .. uri)
    end

    -- Request starts with /koreader/, followed by some predefined entry point
    local ftype, fragment
    ftype, fragment, uri = stepUriFragment(uri) -- skip "/koreader"
    reqinfo.parsed_uri = ftype .. fragment
    table.insert(reqinfo.fragments, 1, fragment)

    ftype, fragment, uri = stepUriFragment(uri)
    if not fragment then
        return self:sendResponse(reqinfo, 200, CTYPE.HTML, HOME_CONTENT)
        -- return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Missing entry point.")
    end
    reqinfo.prev_parsed_uri = reqinfo.parsed_uri
    reqinfo.parsed_uri = reqinfo.parsed_uri .. ftype .. fragment
    table.insert(reqinfo.fragments, 1, fragment)

    -- We allow browsing a few of our core objects
    if fragment == "ui" then
        return self:exposeObject(self.ui, uri, reqinfo)
    elseif fragment == "device" then
        return self:exposeObject(Device, uri, reqinfo)
    elseif fragment == "g_settings" then
        return self:exposeObject(G_reader_settings, uri, reqinfo)
    elseif fragment == "globals" then
        return self:exposeObject(_G, uri, reqinfo)
    elseif fragment == "UIManager" then
        return self:exposeObject(UIManager, uri, reqinfo)
    elseif fragment == "event" then
        return self:exposeEvent(uri, reqinfo)
    elseif fragment == "broadcast" then
        return self:exposeBroadcastEvent(uri, reqinfo)
    end

    return self:sendResponse(reqinfo, 404, CTYPE.TEXT, "Unknown entry point.")
end

-- Navigate object and its children according to uri, reach the
-- final object and act depending on its type and what's requested
function HttpInspector:exposeObject(obj, uri, reqinfo)
    local ftype, fragment
    local parent = obj
    local current_key
    while true do -- process URI
        local obj_type = type(obj)
        if ftype and fragment then
            reqinfo.prev_parsed_uri = reqinfo.parsed_uri
            reqinfo.parsed_uri = reqinfo.parsed_uri .. ftype .. fragment
            table.insert(reqinfo.fragments, 1, fragment)
        end
        ftype, fragment, uri = stepUriFragment(uri)

        if obj_type == "table" then
            if ftype == "/" then
                if not fragment then
                    -- URI ends with 'object/': send a HTML page describing all this object's key/values
                    return self:browseObject(obj, reqinfo)
                else
                    -- URI continues with 'object/key'
                    parent = obj
                    local as_number = tonumber(fragment)
                    fragment = as_number or fragment
                    current_key = fragment
                    obj = obj[fragment]
                    if obj == nil then
                        return self:sendResponse(reqinfo, 404, CTYPE.TEXT, "No such table/object key: "..fragment)
                    end
                    -- continue loop to process this children of our object
                end
            elseif ftype == "" then
                -- URI ends with 'object' (without a trailing /): output it as JSON if possible
                local ok, json = pcall(getAsJsonString, obj)
                if ok then
                    return self:sendResponse(reqinfo, 200, CTYPE.JSON, json)
                else
                    -- Probably nested/recursive data structures (ie. a widget with self.dialog pointing to a parent)
                    return self:sendResponse(reqinfo, 500, CTYPE.TEXT, json)
                end
            else
                return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Invalid request: unexpected token after "..reqinfo.parsed_uri)
            end

        elseif obj_type == "function" then
            if ftype == "?" and not fragment then
                -- URI ends with 'function?' : output some documentation about that function
                return self:showFunctionDetails(obj, reqinfo)
            elseif ftype == "/" or ftype == "?/" then
                -- URI ends or continues with 'function/': call function, output return values as JSON
                -- If 'function?/': do the same but output HTML, helpful for debugging
                if fragment and uri then -- put back first argument into uri
                    uri = fragment .. uri
                end
                return self:callFunction(obj, parent, uri, ftype == "?/", reqinfo)
            else
                -- Nothing else accepted
                return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Invalid request on function: use a trailing / to call, or ? to get details")
            end

        elseif obj_type == "cdata" or obj_type == "userdata" or obj_type == "thread" then
            -- We can't do much on these Lua types.
            -- But try to guess if it's a BlitBuffer, that we can render as PNG !
            local ok, is_bb = pcall(function() return obj.writePNG ~= nil end)
            if ok and is_bb then
                local tmpfile = DataStorage:getDataDir() .. "/cache/tmp_bb.png"
                ok = pcall(obj.writePNG, obj, tmpfile)
                if ok then
                    local f = io.open(tmpfile, "rb")
                    if f then
                        local data = f:read("*all")
                        f:close()
                        os.remove(tmpfile)
                        return self:sendResponse(reqinfo, 200, CTYPE.PNG, data)
                    end
                end
            end
            return self:sendResponse(reqinfo, 403, CTYPE.TEXT, "Can't act on object of type: "..obj_type)

        else
            -- Simple Lua types: string, number, boolean, nil
            if ftype == "" then
                -- Return it as text
                return self:sendResponse(reqinfo, 200, CTYPE.TEXT, tostring(obj))
            elseif (ftype == "=" or ftype == "?=") and fragment and uri then
                -- 'property=value': assign value to property
                -- 'property?=value': same, but output HTML allowing to get back to the parent
                uri = fragment .. uri -- put back first fragment into uri
                local args, nb_args = getVariablesFromUri(uri)
                if nb_args ~= 1 then
                    return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Variable assignment needs a single value")
                end
                local value = args[1]
                parent[current_key] = value -- do what is asked: assign it
                if ftype == "=" then
                    return self:sendResponse(reqinfo, 200, CTYPE.TEXT, T("Variable '%1' assigned with: %2", reqinfo.parsed_uri, tostring(value)))
                else
                    value = tostring(value)
                    local html = {}
                    local add_html = function(h) table.insert(html, h) end
                    local html_quoted_value = value:gsub("&", "&#38;"):gsub(">", "&gt;"):gsub("<", "&lt;")
                    add_html(T("<title>%1.%2=%3</title>", reqinfo.fragments[2], reqinfo.fragments[1], html_quoted_value))
                    add_html(T("<pre wrap>Variable '%1' assigned with: <span style='color: blue;'>%2</span>", reqinfo.parsed_uri, value))
                    add_html("")
                    add_html(T("<a href='%1/'>Browse back</a> to container object.", reqinfo.prev_parsed_uri))
                    html = table.concat(html, "\n")
                    return self:sendResponse(reqinfo, 200, CTYPE.HTML, html)
                end
            elseif ftype == "?" then
                return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "No documentation available on simple types.")
            else
                -- Nothing else accepted
                return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Invalid request on variable")
            end
        end
    end
    return self:sendResponse(reqinfo, 400, CTYPE.TEXT, "Unexpected request") -- luacheck: ignore 511
end

-- Send a HTML page describing all this object's key/values
function HttpInspector:browseObject(obj, reqinfo)
    local html = {}
    local add_html = function(h) table.insert(html, h) end
    -- We want to display keys sorted by value kind
    local KIND_OTHER    = 1 -- string/number/boolean/nil/cdata...
    local KIND_TABLE    = 2 -- table/object
    local KIND_FUNCTION = 3 -- function/method
    local KINDS = { KIND_OTHER, KIND_TABLE, KIND_FUNCTION }
    local html_by_obj_kind
    local reset_html_by_obj_kind = function() html_by_obj_kind = { {}, {}, {} } end
    local add_html_to_obj_kind = function(kind, h) table.insert(html_by_obj_kind[kind], h) end

    local get_html_snippet = function(key, value, uri)
        local href = uri .. key
        local value_type = type(value)
        if value_type == "table" then
            local pad = ""
            local classinfo = guessClassName(value)
            if classinfo then
                pad = (" "):rep(32 - #(tostring(key)))
            end
            return T("<a href='%1' title='get as JSON'>J</a>  <a href='%2/'>%3</a> %4%5", href, href, key, pad, classinfo or ""), KIND_TABLE
        elseif value_type == "function" then
            local pad = (" "):rep(30 - #key)
            local func_info = getFunctionInfo(value)
            local siginfo = (func_info.is_method and "M" or "f") .. " " .. (func_info.nb_args >= 0 and func_info.nb_args or "*")
            return T("   <a href='%1?'>%2</a>() %3%4 <em>%5</em>", href, key, pad, siginfo, func_info.signature), KIND_FUNCTION
        elseif value_type == "string" or value_type == "number" or value_type == "boolean" or value_type == "nil" then
            -- This is not totally fullproof (\n will be eaten by Javascript prompt(), other stuff may fail or get corrupted),
            -- but it should be ok for simple strings.
            local quoted_value
            local html_value
            if value_type == "string" then
                quoted_value = '\\"' .. value:gsub('\\', '\\\\'):gsub('"', '&#x22;'):gsub("'", "&#x27;"):gsub('\n', '\\n'):gsub('<', '&lt;'):gsub('>', '&gt;') .. '\\"'
                html_value = value:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub(">", "&gt;"):gsub("<", "&lt;")
                if html_value:match("\n") then
                    -- Newline in string: make it stand out
                    html_value = T("<span style='display: inline-table; border: 1px dotted blue;'>%1</span>", html_value)
                end
            else
                quoted_value = tostring(value)
                html_value = tostring(value)
            end
            local ondblclick = T([[ondblclick='(function(){
                    var t=prompt("Update value of property: %1", "%2");
                    if (t!=null) {document.location.href="%3?="+t}
                    else {return false;}
                  })(); return false;']], key, quoted_value, href)
            return T("   <b>%1</b>: <span style='color: blue;' title='Double-click to assign new value' %2>%3</span>", key, ondblclick, html_value), KIND_OTHER
        else
            if value_type == "cdata" then
                local ok, is_bb = pcall(function() return value.writePNG ~= nil end)
                if ok and is_bb then
                    return T("   <a href='%1' title='get BB as PNG'>%2</a>  BlitBuffer %3bpp %4x%5", href, key, value.getBpp(), value.w, value.h), KIND_OTHER
                end
            end
            return T("   <b>%1</b>: <em>%2</em>", key, value_type), KIND_OTHER
        end
    end
    -- add_html("<style>a { text-decoration:none }</style>")
    -- A little header may help noticing the page is updated (the browser url bar
    -- just above is usually updates before the page is loaded)
    add_html(T("<title>%1</title>", reqinfo.parsed_uri))
    add_html(T("<pre><big style='background-color: #dddddd;'>%1/</big>", reqinfo.parsed_uri))
    local classinfo = guessClassName(obj)
    if classinfo then
        add_html(T("  <em>%1</em> instance", classinfo))
    end
    -- Keep track of names seen, so we can show these same names
    -- in super classes lighter, as they are then overridden.
    local seen_names = {}
    local seen_prefix = "<span style='opacity: 0.4'>"
    local seen_suffix = "</span>"
    local prelude = ""
    while obj do
        local has_items = false
        reset_html_by_obj_kind()
        for key, value in ffiUtil.orderedPairs(obj) do
            local ignore = key == "__index"
            if not ignore then
                local snippet, kind = get_html_snippet(key, value, reqinfo.uri)
                if seen_names[key] then
                    add_html_to_obj_kind(kind, prelude .. seen_prefix .. snippet .. seen_suffix)
                else
                    add_html_to_obj_kind(kind, prelude .. snippet)
                end
                seen_names[key] = true
                prelude = ""
                has_items = true
            end
        end
        for _, kind in ipairs(KINDS) do
            for _, htm in ipairs(html_by_obj_kind[kind]) do
                add_html(htm)
            end
        end
        if not has_items then
            add_html("(empty table/object)")
        end
        obj = getmetatable(obj)
        if obj then
            prelude = "<hr size=1 noshade/>"
            classinfo = guessClassName(obj)
            if classinfo then
                add_html(prelude .. T("  <em>%1</em>", classinfo))
                prelude = ""
            end
        end
    end
    add_html("</pre>")
    html = table.concat(html, "\n")
    return self:sendResponse(reqinfo, 200, CTYPE.HTML, html)
end

-- Send a HTML page describing a function or method
function HttpInspector:showFunctionDetails(obj, reqinfo)
    local html = {}
    local add_html = function(h) table.insert(html, h) end
    local base_uri = reqinfo.parsed_uri
    local func_info = getFunctionInfo(obj, true)
    add_html(T("<title>%1?</title>", reqinfo.fragments[1]))
    add_html(T("<pre wrap><big style='background-color: #dddddd;'>%1</big>", reqinfo.parsed_uri))
    add_html(T("  <em>%1</em>", func_info.signature))
    add_html("")
    add_html(T("This is a <b>%1</b>, <b>accepting or requiring up to %2 arguments</b>.", (func_info.is_method and "method" or "function"), func_info.nb_args >= 0 and func_info.nb_args or "many"))
    add_html("")
    add_html("We can't tell you more, neither what type of arguments it expects, and what it will do (it may crash or let KOReader in an unusable state).")
    add_html("Only values of simple type (string, number, boolean, nil) can be provided as arguments and returned as results. Functions expecting tables or objects will most probably fail. <mark>Call at your own risk!</mark>")
    add_html("")
    local output_sample_uris = function(token)
        local some_uri = base_uri .. token
        local pad = (" "):rep(#base_uri + 25 - #some_uri)
        add_html(T("<a href='%1'>%2</a> %3 without args", some_uri, some_uri, pad))
        local nb_args = func_info.nb_args >= 0 and func_info.nb_args or 4 -- limit to 4 if varargs
        for i=1, nb_args do
            if i > 1 then
                some_uri = some_uri .. "/"
            end
            some_uri = some_uri .. "arg" .. tostring(i)
            pad = (" "):rep(#base_uri + 25 - #some_uri)
            add_html(T("%1 %2 with %3 args", some_uri, pad, i))
        end
    end
    add_html("It may be called, to get results <b>as HTML</b>, with:")
    output_sample_uris("?/")
    add_html("")
    add_html("It may be called, to get results <b>as JSON</b>, with:")
    output_sample_uris("/")
    add_html("")
    if func_info.no_source then
        add_html(T("Builtin function or from a C module: no source code available."))
    else
        local dummy, git_commit = require("version"):getNormalizedCurrentVersion()
        local github_uri = T("https://github.com/koreader/koreader/blob/%1/%2#L%3", git_commit, func_info.source, func_info.firstline)
        add_html(T("Here's a snippet of the function code (it can be viewed with syntax coloring and line numbers <a href='%1'>on Github</a>):", github_uri))
        add_html("<div style='background-color: lightgray'>")
        for _, line in ipairs(func_info.lines) do
            add_html(line)
        end
        add_html("\n</div>")
    end
    add_html("</pre>")
    html = table.concat(html, "\n")
    return self:sendResponse(reqinfo, 200, CTYPE.HTML, html)
end

-- Call a function or method, send results as JSON or HTML
function HttpInspector:callFunction(func, instance, args_as_uri, output_html, reqinfo)
    local html = {}
    local add_html = function(h) table.insert(html, h) end
    local args, nb_args = getVariablesFromUri(args_as_uri)
    local func_info = getFunctionInfo(func)
    if output_html then
        add_html(T("<title>%1(%2)</title>", reqinfo.fragments[1], args_as_uri or ""))
        add_html(T("<pre><big style='background-color: #dddddd;'>%1</big> <big>(%2)</big>", reqinfo.parsed_uri, args_as_uri or ""))
        add_html(T("  <em>%1</em>", func_info.signature))
        add_html("")
        add_html(T("Nb args: %1", nb_args))
        for i=1, nb_args do
            local arg = args[i]
            add_html(T("  %1: %2: %3", i, type(arg), tostring(arg)))
        end
        add_html("")
    end
    local res, nbr, http_code, json, ok, ok2, err, trace
    if func_info.is_method then
        res = table.pack(xpcall(func, debug.traceback, instance, unpack(args, 1, nb_args)))
    else
        res = table.pack(xpcall(func, debug.traceback, unpack(args, 1, nb_args)))
    end
    ok = res[1]
    if ok then
        http_code = 200
        table.remove(res, 1) -- remove pcall's ok
        -- table.pack and JSON.encode may use this "n" key value to set the nb
        -- of element and guess it is an array. Keep it updated.
        nbr = res["n"]
        if nbr then
            nbr = nbr - 1
            res["n"] = nbr
            if nbr == 0 then
                res = nil
            end
        end
        if res == nil then
            -- getAsJsonString would return "null", let's return an empty array instead
            json = "[]"
        else
            ok2, json = pcall(getAsJsonString, res)
            if not ok2 then
                json = "[ 'can't be reprensented as json' ]"
            end
        end
    else
        http_code = 500
        -- On error, instead of the array on success, let's return an object,
        -- with keys 'error' and "stacktrace"
        if res[2] then
            err, trace = res[2]:match("^(.-)\n(.*)$")
        end
        json = getAsJsonString({["error"] = err, ["stacktrace"] = trace})
    end
    if output_html then
        local bgcolor = ok and "#bbffbb" or "#ffbbbb"
        local status = ok and "Success" or "Failure"
        add_html(T("<big style='background-color: %1'>%2</big>", bgcolor, status))
        if ok then
            add_html(T("Nb returned values: %1", nbr))
            for i=1, nbr do
                local r = res[i]
                add_html(T("  %1: %2: %3", i, type(r), tostring(r)))
            end
            add_html("")
            add_html("Returned values as JSON:")
            add_html(json)
        else
            add_html(err)
            add_html(trace)
        end
        add_html("</pre>")
        html = table.concat(html, "\n")
        return self:sendResponse(reqinfo, http_code, CTYPE.HTML, html)
    else
        return self:sendResponse(reqinfo, http_code, CTYPE.JSON, json)
    end
end

-- Handy function for testing the above, to be called with:
--   /koreader/ui/httpinspector/someFunctionForInteractiveTesting?/
function HttpInspector:someFunctionForInteractiveTesting(...)
    if select(1, ...) then
        HttpInspector.foo.bar = true -- error
    end
    return self and self.name or "no self", #(table.pack(...)), "original args follow", ...
    -- Copy and append this as args to the url, to get an error:
    -- /true/nil/true/false/"true"/-1.2/"/"/abc/'d"/ef'/
    -- and to get a success:
    -- /false/nil/true/false/"true"/-1.2/"/"/abc/'d"/ef'/
end

local _dispatcher_actions

local getOrderedDispatcherActions = function()
    if _dispatcher_actions then
        return _dispatcher_actions
    end
    local Dispatcher = require("dispatcher")
    local settings, order
    local n = 1
    while true do
        local name, value = debug.getupvalue(Dispatcher.init, n)
        if not name then break end
        if name == "settingsList" then
            settings = value
            break
        end
        n = n + 1
    end
    while true do
        local name, value = debug.getupvalue(Dispatcher.registerAction, n)
        if not name then break end
        if name == "dispatcher_menu_order" then
            order = value
            break
        end
        n = n + 1
    end
    -- Copied and pasted from Dispatcher (we can't reach that the same way as above)
    local section_list = {
        {"general", _("General")},
        {"device", _("Device")},
        {"screen", _("Screen and lights")},
        {"filemanager", _("File browser")},
        {"reader", _("Reader")},
        {"rolling", _("Reflowable documents (epub, fb2, txt…)")},
        {"paging", _("Fixed layout documents (pdf, djvu, pics…)")},
    }
    _dispatcher_actions = {}
    for _, section in ipairs(section_list) do
        table.insert(_dispatcher_actions, section[2])
        local section_key = section[1]
        for _, k in ipairs(order) do
            if settings[k][section_key] == true then
                local t = util.tableDeepCopy(settings[k])
                t.dispatcher_id = k
                table.insert(_dispatcher_actions, t)
            end
        end
    end
    -- Add a useful one
    table.insert(_dispatcher_actions, 2, { general=true, separator=true, event="Close", category="none", title="Close top most widget"})
    return _dispatcher_actions
end

function HttpInspector:exposeEvent(uri, reqinfo)
    local ftype, fragment -- luacheck: no unused
    ftype, fragment, uri = stepUriFragment(uri) -- luacheck: no unused
    if fragment then
        -- Event name and args provided.
        -- We may get multiple events, separated by a dummy arg /&/
        local events = {}
        local ev_names = {fragment}
        local cur_ev_args = {fragment}
        local args, nb_args = getVariablesFromUri(uri)
        for i=1, nb_args do
            local arg = args[i]
            if arg ~= "&" then
                if #cur_ev_args == 0 then
                    table.insert(ev_names, arg)
                end
                table.insert(cur_ev_args, arg)
            else
                table.insert(events, Event:new(table.unpack(cur_ev_args)))
                cur_ev_args = {}
            end
        end
        if #cur_ev_args > 0 then
            table.insert(events, Event:new(table.unpack(cur_ev_args)))
        end
        -- As events may switch/reload the document, or exit/restart KOReader,
        -- we delay them a bit so we can send the HTTP response and properly
        -- shutdown the HTTP server
        UIManager:nextTick(function()
            for _, ev in ipairs(events) do
                UIManager:sendEvent(ev)
            end
        end)
        return self:sendResponse(reqinfo, 200, CTYPE.TEXT, T("Event sent: %1", table.concat(ev_names, ", ")))
    end

    -- No event provided.
    -- We want to show the list of actions exposed by Dispatcher (that are all handled as Events).
    local actions = getOrderedDispatcherActions()
    -- if true then return self:sendResponse(reqinfo, 200, CTYPE.JSON, getAsJsonString(actions)) end
    local html = {}
    local add_html = function(h) table.insert(html, h) end
    add_html(T("<title>High-level KOReader events</title>"))
    add_html(T("<pre><big>List of high-level KOReader events</big>\n(all those available as actions for gestures and profiles)</big>"))
    for _, action in ipairs(actions) do
        if type(action) == "string" then
            add_html(T("<hr size='1' noshade ><big style='background-color: #dddddd;'>%1</big>", action))
        elseif action.condition == false then
            -- Some bottom menu are just disabled on all devices,
            -- so just don't show any disabled action
            do end -- luacheck: ignore 541
        else
            local active = false
            if action.general or action.device or action.screen then
                active = true
            elseif action.reader and self.ui.view then
                active = true
            elseif action.rolling and self.ui.rolling then
                active = true
            elseif action.paging and self.ui.paging then
                active = true
            elseif action.filemanager and self.ui.onSwipeFM then
                active = true
            end

            local title = action.title
            if not active then
                title = T("<span style='color: dimgray'>%1</span>    <small>(no effect on current application/document)</small>", title)
            end
            add_html(T("<b>%1</b>", title))

            -- Same messy logic as in Dispatcher:execute() (not everything has been tested).
            local get_base_href = function()
                return reqinfo.parsed_uri .. (action.event and "/"..action.event or "")
            end
            if action.configurable then
                -- Such actions sends a first (possibly single with KOpt settings) event
                -- to update the setting value for the bottom menu
                -- We'll have to insert it in our single URL which may then carry 2 events
                get_base_href = function(v, is_indice, single)
                    return T("%1/%2/%3/%4%5", reqinfo.parsed_uri, "ConfigChange", action.configurable.name, is_indice and action.configurable.values[v] or v, single and "" or (action.event and "/&/"..action.event or ""))
                end
            end

            if action.category == "none" then
                -- Shouldn't have any 'configurable'
                local href
                if action.arg ~= nil then
                    href = T("%1/%2", get_base_href(), tostring(action.arg))
                else
                    href = get_base_href()
                end
                add_html(T("  <a href='%1'>%1</a>", href))
            elseif action.category == "string" then
                -- Multiple values, can have a 'configurable'
                local args, toggle
                if not action.args and action.args_func then
                    args, toggle = action.args_func()
                else
                    args, toggle = action.args, action.toggle
                end
                if type(args[1]) == "table" then
                    add_html(T("  %1/... unsupported (table arguments)", get_base_href("...")))
                else
                    for i=1, #args do
                        local href = T("%1/%2", get_base_href(i, true), tostring(args[i]))
                        local unit = action.unit and " "..action.unit or ""
                        local default = args[i] == action.default and " (default)" or ""
                        add_html(T("  <a href='%1'>%1</a> \t<b>%2%3%4</b>", href, toggle[i], unit, default))
                    end
                end
            elseif action.category == "absolutenumber" then
                local suggestions = {}
                if action.configurable and action.configurable.values then
                    for num, val in ipairs(action.configurable.values) do
                        local unit = action.unit and " "..action.unit or ""
                        local default = val == action.default and " (default)" or ""
                        table.insert(suggestions, { val, T("%1%2%3", val, unit, default) })
                    end
                else
                    local min, max = action.min, action.max
                    if min == -1 and max > 1 then
                        table.insert(suggestions, { min, "off / none" })
                        min = 0
                    end
                    table.insert(suggestions, { min, "min" })
                    -- Add interesting values for specific actions
                    if action.dispatcher_id == "page_jmp" then
                        table.insert(suggestions, { -1, "-1 page" })
                    end
                    table.insert(suggestions, { (min + max)/2, "" })
                    if action.dispatcher_id == "page_jmp" then
                        table.insert(suggestions, { 1, "+1 page" })
                    end
                    table.insert(suggestions, { max, "max" })
                end
                for _, suggestion in ipairs(suggestions) do
                    local href = T("%1/%2", get_base_href(suggestion[1]), tostring(suggestion[1]))
                    add_html(T("  <a href='%1'>%1</a> \t<b>%2</b>", href, suggestion[2]))
                end
            elseif action.category == "incrementalnumber" then
                -- Shouldn't have any 'configurable'
                local suggestions = {}
                local min, max = action.min, action.max
                table.insert(suggestions, { min, "min" })
                if action.step then
                    for i=1, 5 do
                        min = min + action.step
                        table.insert(suggestions, { min, "" })
                    end
                else
                    table.insert(suggestions, { (min + max)/2, "" })
                end
                table.insert(suggestions, { max, "max" })
                for _, suggestion in ipairs(suggestions) do
                    local href = T("%1/%2", get_base_href(suggestion[1]), tostring(suggestion[1]))
                    add_html(T("  <a href='%1'>%1</a> \t<b>%2</b>", href, suggestion[2]))
                end
            elseif action.category == "arg" then
                add_html(T("  %1/... unsupported (gesture arguments)", get_base_href("...")))
            elseif action.category == "configurable" then
                -- No other action event to send
                for i=1, #action.configurable.values do
                    local href = T("%1", get_base_href(i, true))
                    add_html(T("  <a href='%1'>%1</a> \t<b>%2</b>", href, action.toggle[i]))
                end
            else
                -- Should not happen
                add_html(T("  %1/... not implemented", get_base_href("...")))
                add_html(getAsJsonString(action))
            end
            if action.separator then
                add_html("")
            end
        end
    end
    add_html("</pre>")
    html = table.concat(html, "\n")
    return self:sendResponse(reqinfo, 200, CTYPE.HTML, html)
end

function HttpInspector:exposeBroadcastEvent(uri, reqinfo)
    -- Similar to previous one, without any list.
    local ftype, fragment -- luacheck: no unused
    ftype, fragment, uri = stepUriFragment(uri) -- luacheck: no unused
    if fragment then
        -- Event name and args provided.
        -- We may get multiple events, separated by a dummy arg /&/
        local events = {}
        local ev_names = {fragment}
        local cur_ev_args = {fragment}
        local args, nb_args = getVariablesFromUri(uri)
        for i=1, nb_args do
            local arg = args[i]
            if arg ~= "&" then
                if #cur_ev_args == 0 then
                    table.insert(ev_names, arg)
                end
                table.insert(cur_ev_args, arg)
            else
                table.insert(events, Event:new(table.unpack(cur_ev_args)))
                cur_ev_args = {}
            end
        end
        if #cur_ev_args > 0 then
            table.insert(events, Event:new(table.unpack(cur_ev_args)))
        end
        -- As events may switch/reload the document, or exit/restart KOReader,
        -- we delay them a bit so we can send the HTTP response and properly
        -- shutdown the HTTP server
        UIManager:nextTick(function()
            for _, ev in ipairs(events) do
                UIManager:broadcastEvent(ev)
            end
        end)
        return self:sendResponse(reqinfo, 200, CTYPE.TEXT, T("Event broadcasted: %1", table.concat(ev_names, ", ")))
    end

    -- No event provided.
    local html = {}
    local add_html = function(h) table.insert(html, h) end
    add_html(T("<title>Broadcast event</title>"))
    add_html(T("<pre>No suggestion, <mark>use at your own risk</mark>."))
    add_html(T("Usage: <a href='%1'>%1</a>", "/koreader/broadcast/EventName/arg1/arg2"))
    add_html("</pre>")
    html = table.concat(html, "\n")
    return self:sendResponse(reqinfo, 200, CTYPE.HTML, html)
end

return HttpInspector
