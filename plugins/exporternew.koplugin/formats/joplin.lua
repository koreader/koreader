local BD = require("ui/bidi")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local logger = require("logger")

local JoplinClient =  {
    server_ip = "localhost",
    server_port = 41184,
    auth_token = ""
}

function JoplinClient:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function JoplinClient:getBaseURL()
    return "http://" .. self.server_ip .. ":" .. self.server_port
end

function JoplinClient:buildParameters(params)
    local params_str = ""
    for k, v in pairs(params) do
        params_str = params_str .. "&" .. k .. "=" .. v
    end
    if params_str ~= "" then
        params_str = "?" .. string.sub(params_str, 2)
    end
    return params_str
end

function JoplinClient:_makeRequest(url, method, request_body, ignore_error)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    http.request{
        url     = url,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Length"] = #request_body_json,
            ["Content-Type"] = "application/json"
        },
    }
    socketutil:reset_timeout()

    if not sink[1] then
        error("No response from Joplin Server")
    end

    local response = json.decode(sink[1])

    if not ignore_error and response.error then
        error(response.error)
    end

    return response
end

function JoplinClient:ping()
    local sink = {}

    http.request{
        url =  self:getBaseURL().."/ping",
        method = "GET",
        sink = ltn12.sink.table(sink)
    }

    if sink[1] == "JoplinClipperServer" then
        return true
    else
        return false
    end
end

-- If successful returns id of found note.
function JoplinClient:findNoteByTitle(title, notebook_id)
    local url_base =  self:getBaseURL().."/notes"
    local params = {
        fields = "id,title,parent_id",
        token = self.auth_token,
        page = ""
    }

    local url
    local page = 1
    local has_more

    repeat
        params.page = page
        url = url_base..self:buildParameters(params)
        local notes = self:_makeRequest(url, "GET")
        has_more = notes.has_more
        for _, note in ipairs(notes.items) do
            if note.title == title then
                if notebook_id == nil or note.parent_id == notebook_id then
                    return note.id
                end
            end
        end
        page = page + 1
    until not has_more
    return false

end

-- If successful returns id of found notebook (folder).
function JoplinClient:findNotebookByTitle(title)
    local url_base =  self:getBaseURL() .. "/folders"
    local parameters = {
        token = self.auth_token,
        fields = "id,title",
        page = ""
    }


    local url
    local page = 1
    local has_more

    repeat
        parameters.page = page
        url = url_base..self:buildParameters(parameters)
        local folders = self:_makeRequest(url, "GET")
        has_more = folders.has_more
        for _, folder in ipairs(folders.items) do
            if folder.title == title then
                return folder.id
            end
        end
        page = page + 1
    until not has_more
    return false
end

function JoplinClient:findNotebookByID(id)
    local parameters = {
        token = self.auth_token,
    }
    local url =  self:getBaseURL() .. "/folders/"..id..self:buildParameters(parameters)
    local notebook = self:_makeRequest(url, "GET", nil, true)
    return notebook
end

-- If successful returns id of created notebook (folder).
function JoplinClient:createNotebook(title, created_time)
    local request_body = {
        title = title,
        created_time = created_time
    }

    local url =  self:getBaseURL().."/folders"..self:buildParameters({token = self.auth_token})
    local response = self:_makeRequest(url, "POST", request_body)

    return response.id
end


-- If successful returns id of created note.
function JoplinClient:createNote(title, note, parent_id, created_time)
    local request_body = {
        title = title,
        body = note,
        parent_id = parent_id,
        created_time = created_time
    }
    local url =  self:getBaseURL().."/notes"..self:buildParameters({token = self.auth_token})
    local response = self:_makeRequest(url, "POST", request_body)

    return response.id
end

-- If successful returns id of updated note.
function JoplinClient:updateNote(note_id, note, title, parent_id)
    local request_body = {
        body = note,
        title = title,
        parent_id = parent_id
    }

    local url = self:getBaseURL().."/notes/"..note_id.."?token="..self.auth_token
    local response = self:_makeRequest(url, "PUT", request_body)
    return response.id
end

local JoplinExporter = require("formats/base"):new{
    name = "joplin",
    is_remote = true,
    version = "joplin/1.0.0"
}

function JoplinExporter:isEnabled()
    return self.settings.enabled and self.settings.ip and self.settings.port and self.settings.token
end

function JoplinExporter:loadSettings()
    local plugin_settings = G_reader_settings:readSetting(self.id) or {}
    self.settings = plugin_settings[self.name] or {}
    -- logger.dbg("Joplin settings:", self.settings)
end

function JoplinExporter:toggleEnabled()
    if not self.settings.ip or not self.settings.port or not self.settings.token then return end
    self.settings.enabled = not self.settings.enabled
    self:saveSettings()
end

function JoplinExporter:getMenuTable()
    return {
        text = _("Joplin") ,
        checked_func = function() return self:isEnabled() end,
        sub_item_table ={
            {
                text = _("Set Joplin IP and Port"),
                keep_menu_open = true,
                callback = function()
                    local MultiInputDialog = require("ui/widget/multiinputdialog")
                    local url_dialog
                    url_dialog = MultiInputDialog:new{
                        title = _("Set Joplin IP and port number"),
                        fields = {
                            {
                                text = self.settings.ip,
                                input_type = "string"
                            },
                            {
                                text = self.settings.port,
                                input_type = "number"
                            }
                        },
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(url_dialog)
                                    end
                                },
                                {
                                    text = _("OK"),
                                    callback = function()
                                        local fields = url_dialog:getFields()
                                        local ip = fields[1]
                                        local port = tonumber(fields[2])
                                        if ip ~= "" then
                                            if port and port < 65355 then
                                                self.settings.ip = ip
                                                self.settings.port = port
                                                self:saveSettings()
                                            end
                                        end
                                        UIManager:close(url_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(url_dialog)
                    url_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Set authorization token"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new{
                        title = _("Set authorization token for Joplin"),
                        input = self.settings.token,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(auth_dialog)
                                    end
                                },
                                {
                                    text = _("Set token"),
                                    callback = function()
                                        self.settings.token = auth_dialog:getInputText()
                                        self:saveSettings()
                                        UIManager:close(auth_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(auth_dialog)
                    auth_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Set Notebook Name"),
                keep_menu_open = true,
                callback = function()
                    local notebook_dialog
                    notebook_dialog = InputDialog:new{
                        title = _("Set notebook name for Joplin"),
                        input = self.settings.notebook_name,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(notebook_dialog)
                                    end
                                },
                                {
                                    text = _("Set token"),
                                    callback = function()
                                        self.settings.notebook_name = notebook_dialog:getInputText()
                                        self:saveSettings()
                                        UIManager:close(notebook_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(notebook_dialog)
                    notebook_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Export to Joplin"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[You can enter your auth token on your computer by saving an empty token. Then quit KOReader, edit the exporter.joplin_token field in %1/settings.reader.lua after creating a backup, and restart KOReader once you're done.

To export to Joplin, you must forward the IP and port used by this plugin to the localhost:port on which Joplin is listening. This can be done with socat or a similar program. For example:

For Windows: netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=41185 connectaddress=localhost connectport=41184

For Linux: $socat tcp-listen:41185,reuseaddr,fork tcp:localhost:41184

For more information, please visit https://github.com/koreader/koreader/wiki/Highlight-export.]])
                            , BD.dirpath("example"))
                            })
                end
            }
        }
    }
end

function JoplinExporter:getClient()
    -- logger.dbg("settings", self.settings)
    local client = JoplinClient:new{
            server_ip = self.settings.ip,
            server_port = self.settings.port,
            auth_token = self.settings.token
        }
    ---@todo Check if user deleted our notebook, in that case note
    -- will end up in random folder in Joplin.
    if not self.settings.notebook_name then
        self.settings.notebook_name = _("KOReader Notes")
        self:saveSettings()
    end
    if not self.settings.joplin_notebook_guid then
        self.settings.joplin_notebook_guid = client:createNotebook(self.settings.notebook_name)
        self:saveSettings()
    else
        local notebook = client:findNotebookByTitle(self.settings.notebook_name)
        -- logger.dbg("err", self.settings.joplin_notebook_guid, notebook)
        if not notebook then
            self.settings.joplin_notebook_guid = client:createNotebook(self.settings.notebook_name)
            self:saveSettings()
        end
    end

    if not client:ping() then
        error("Cannot reach Joplin server")
    end
    return client
end

function JoplinExporter:prepareNote(booknotes)
    -- logger.dbg("booknotes", booknotes)
    local note = ""
    for _, clipping in ipairs(booknotes.entries) do
        if clipping.chapter then
            note = note .. "\n\t*" .. clipping.chapter .. "*\n\n * * *"
        end

        note = note .. os.date("%Y-%m-%d %H:%M:%S \n", clipping.time)
        note = note .. clipping.text
        if clipping.note then
            note = note .. "\n---\n" .. clipping.note
        end
        note = note .. "\n * * *\n"        
    end
    return note
end

function JoplinExporter:exportOne(t, timestamp)
    local client = self:getClient()
    local note_guid = client:findNoteByTitle(t.title, self.settings.joplin_notebook_guid)
    local note = self:prepareNote(t)
    if note_guid then
        client:updateNote(note_guid, note)
    else
        client:createNote(t.title, note, note_guid)
    end
end

function JoplinExporter:exportAll(t, timestamp)
    local client = self:getClient()
    for _, booknotes in pairs(t) do
        local note_guid = client:findNoteByTitle(booknotes.title, self.settings.joplin_notebook_guid)
        local note = self:prepareNote(booknotes)
        if note_guid then
            client:updateNote(note_guid, note)
        else
            client:createNote(booknotes.title, note, note_guid)
        end
    end
end


return JoplinExporter

