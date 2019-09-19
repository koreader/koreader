local json = require("json")
local http = require('socket.http')
local ltn12 = require('ltn12')
local socket = require('socket')
local url = require('socket.url')

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
    local source = {}
    local request_body = json.encode(request_body)
    local source = ltn12.source.string(request_body)
    http.request{
        url = url,
        method = method,
        sink = ltn12.sink.table(sink),
        source = source,
        headers = {["Content-Length"] = #request_body,
            ["Content-Type"] = "application/json"}
    }

    if not sink[1] then
        error("No response from Joplin Server") 
    end

    local response = json.decode(sink[1])

    if response["error"] then
        error(response["error"])
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

--@return if successful returns id of found note
function JoplinClient:findNoteByTitle(title, notebook_id)
    local url =  "http://"..self.server_ip..":"..self.server_port.."/notes?".."token="..self.auth_token.."&fields=id,title,parent_id"

    local notes = self:_makeRequest(url, "GET")

    for _, note in pairs(notes) do
        if note["title"] == title then
            if notebook_id == nil or note["parent_id"] == notebook_id then
                return note["id"]
            end
        end
    end

    return false

end

--@return if successful returns id of found notebook (folder)
function JoplinClient:findNotebookByTitle(title)
    local url =  "http://"..self.server_ip..":"..self.server_port.."/folders?".."token="..self.auth_token.."&".."query="..title

    local folders = self:_makeRequest(url, "GET") 

    for _, folder in pairs(folders) do
        if folder["title"] == title then
            return folder["id"]
        end
    end

    return false
end

--@return if successful returns id of created notebook (folder)
function JoplinClient:createNotebook(title, created_time)
    local request_body = {["title"] = title,
        ["created_time"] = created_time
    }

    local url =  "http://"..self.server_ip..":"..self.server_port.."/folders?".."token="..self.auth_token
    local response = self:_makeRequest(url, "POST", request_body)

    return response["id"]
end


--@return if successful returns id of created note
function JoplinClient:createNote(title, note, parent_id, created_time)
    local request_body = {["title"] = title,
            ["body"] = note, 
            ["parent_id"] = parent_id,
            ["created_time"] = created_time
    }
    local url =  "http://"..self.server_ip..":"..self.server_port.."/notes?".."token="..self.auth_token
    local response = self:_makeRequest(url, "POST", request_body)

    return response["id"]
end

--@return if successful returns true
function JoplinClient:updateNote(note_id, note, title, parent_id)
    local request_body = {
        ["body"] = note
    }
    if title then 
        request_body["title"] = title 
    end

    if parent_id then
        request_body["parent_id"] = parent_id
    end

    local url = "http://"..self.server_ip..":"..self.server_port.."/notes/"..note_id.."?token="..self.auth_token
    local response = self:_makeRequest(url, "PUT", request_body)
    return response["id"]
end

return JoplinClient