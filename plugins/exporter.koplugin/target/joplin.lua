local BD = require("ui/bidi")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local T = require("ffi/util").template
local _ = require("gettext")

-- joplin exporter
local JoplinExporter = require("base"):new {
    name = "joplin",
    is_remote = true,
    notebook_name = _("KOReader Notes"),
}

local function makeRequest(url, method, request_body)
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
        return nil, "No response from Joplin Server"
    end

    local response = json.decode(sink[1])

    if not response then
        return nil, "Unknown response from Joplin Server"
    elseif response.error then
        return nil, response.error
    end

    return response
end

local function ping(ip, port)
    local sink = {}
    http.request{
        url =  "http://"..ip..":"..port.."/ping",
        method = "GET",
        sink = ltn12.sink.table(sink)
    }

    if sink[1] == "JoplinClipperServer" then
        return true
    else
        return false
    end
end

local function prepareNote(booknotes)
    local note = ""
    for _, clipping in ipairs(booknotes) do
        local entry = clipping[1]
        if entry.chapter then
            note = note .. "\n\t*" .. entry.chapter .. "*\n\n * * *"
        end

        note = note .. os.date("%Y-%m-%d %H:%M:%S \n", entry.time)
        note = note .. entry.text
        if entry.note then
            note = note .. "\n---\n" .. entry.note
        end
        note = note .. "\n * * *\n"
    end
    return note
end

-- If successful returns id of found note.
function JoplinExporter:findNoteByTitle(title, notebook_id)
    local url_base = string.format("http://%s:%s/notes?token=%s&fields=id,title,parent_id&page=",
        self.settings.ip, self.settings.port, self.settings.token)

    local page = 1
    local url, has_more

    repeat
        url = url_base..page
        local notes, err = makeRequest(url, "GET")
        if not notes then
            logger.warn("Joplin findNoteByTitle error", err)
            return
        end
        has_more = notes.has_more
        for _, note in ipairs(notes.items) do
            if note.title == title and note.parent_id == notebook_id then
                return note.id
            end
        end
        page = page + 1
    until not has_more
    return
end

-- If successful returns id of found notebook (folder).
function JoplinExporter:findNotebookByTitle(title)
    local url_base = string.format("http://%s:%s/folders?token=%s&query=title&page=",
        self.settings.ip, self.settings.port, self.settings.token, title)

    local page = 1
    local url, has_more

    repeat
        url = url_base .. page
        local folders, err = makeRequest(url, "GET")
        if not folders then
            logger.warn("Joplin findNotebookByTitle error", err)
            return
        end
        has_more = folders.has_more
        for _, folder in ipairs(folders.items) do
            if folder.title == title then
                return folder.id
            end
        end
        page = page + 1
    until not has_more
    return
end

-- returns true if the notebook exists
function JoplinExporter:notebookExist(title)
    local url = string.format("http://%s:%s/folders?token=%s",
        self.settings.ip, self.settings.port, self.settings.token)
    local response, err = makeRequest(url, "GET")
    if not response then
        logger.warn("Joplin notebookExist error", err)
    end

    if not response.items or type(response.items) ~= "table" then
        return false
    end

    for i, notebook in ipairs(response.items) do
        if notebook.title == title then return true end
    end
    return false
end

-- If successful returns id of created notebook (folder).
function JoplinExporter:createNotebook(title, created_time)
    local request_body = {
        title = title,
        created_time = created_time
    }
    local url = string.format("http://%s:%s/folders?token=%s",
        self.settings.ip, self.settings.port, self.settings.token)

    local response, err = makeRequest(url, "POST", request_body)
    if not response then
        logger.warn("Joplin createNotebook error", err)
        return
    end
    return response.id
end

-- If successful returns id of created note.
function JoplinExporter:createNote(title, note, parent_id, created_time)
    local request_body = {
        title = title,
        body = note,
        parent_id = parent_id,
        created_time = created_time
    }
    local url = string.format("http://%s:%s/notes?token=%s",
        self.settings.ip, self.settings.port, self.settings.token)

    local response, err = makeRequest(url, "POST", request_body)
    if not response then
        logger.warn("Joplin createNote error", err)
        return
    end
    return response.id
end

-- If successful returns id of updated note.
function JoplinExporter:updateNote(note, note_id)
    local request_body = {
        body = note
    }

    local url = string.format("http://%s:%s/notes/%s?token=%s",
        self.settings.ip, self.settings.port, note_id, self.settings.token)

    local response, err = makeRequest(url, "PUT", request_body)
    if not response then
        logger.warn("Joplin updateNote error", err)
        return
    end
    return response.id
end

function JoplinExporter:isReadyToExport()
    return self.settings.ip and self.settings.port and self.settings.token
end

function JoplinExporter:getMenuTable()
    return {
        text = _("Joplin"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set Joplin IP and Port"),
                keep_menu_open = true,
                callback = function()
                    local MultiInputDialog = require("ui/widget/multiinputdialog")
                    local url_dialog
                    url_dialog = MultiInputDialog:new {
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
                    auth_dialog = InputDialog:new {
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
                text = _("Export to Joplin"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new {
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

function JoplinExporter:export(t)
    if not self:isReadyToExport() then return false end

    if not ping(self.settings.ip, self.settings.port) then
        logger.warn("Cannot reach Joplin server")
        return false
    end

    if not self:notebookExist(self.notebook_name) then
        local notebook = self:createNotebook(self.notebook_name)
        if notebook then
            logger.info("Joplin: created new notebook",
                "name", self.notebook_name, "id", notebook)
            self.settings.notebook_guid = notebook
            self:saveSettings()
        else
            logger.warn("Joplin: unable to create new notebook")
            return false
        end
    end

    local notebook_id = self.settings.notebook_guid
    for _, booknotes in pairs(t) do
        local note = prepareNote(booknotes)
        local note_id = self:findNoteByTitle(booknotes.title, notebook_id)
        local response
        if note_id then
            response = self:updateNote(note, note_id)
        else
            response = self:createNote(booknotes.title, note, notebook_id)
        end
        if not response then
            logger.warn("Cannot export to Joplin")
            return false
        end
    end
    return true
end

return JoplinExporter
