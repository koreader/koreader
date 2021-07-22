local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")

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

function JoplinClient:_makeRequest(url, method, request_body)
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

    if response.error then
        error(response.error)
    end

    return response
end

function JoplinClient:ping()
    local sink = {}

    http.request{
        url =  "http://"..self.server_ip..":"..self.server_port.."/ping",
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
    local url_base =  "http://"..self.server_ip..":"..self.server_port.."/notes?".."token="..self.auth_token.."&fields=id,title,parent_id&page="

    local url
    local page = 1
    local has_more

    repeat
        url = url_base..page
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
    local url_base =  "http://"..self.server_ip..":"..self.server_port.."/folders?".."token="..self.auth_token.."&".."query="..title.."&page="


    local url
    local page = 1
    local has_more

    repeat
        url = url_base..page
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

-- If successful returns id of created notebook (folder).
function JoplinClient:createNotebook(title, created_time)
    local request_body = {
        title = title,
        created_time = created_time
    }

    local url =  "http://"..self.server_ip..":"..self.server_port.."/folders?".."token="..self.auth_token
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
    local url =  "http://"..self.server_ip..":"..self.server_port.."/notes?".."token="..self.auth_token
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

    local url = "http://"..self.server_ip..":"..self.server_port.."/notes/"..note_id.."?token="..self.auth_token
    local response = self:_makeRequest(url, "PUT", request_body)
    return response.id
end

return JoplinClient
