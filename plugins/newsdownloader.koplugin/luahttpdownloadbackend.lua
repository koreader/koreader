local logger = require("logger")
local http_request = require "http.request"

-- Currently unused. TODO @mwoz123 ADD LUA-HTTP AS LIBRARY
local LuaHttpDownloadBackend = {}

function LuaHttpDownloadBackend:getResponseAsString(url)
   local _, stream = assert(http_request.new_from_uri(url):go())
   local body = assert(stream:get_body_as_string())
   logger.dbg("Response body:", body)
   return body
end

function LuaHttpDownloadBackend:download(link, path)
   local _, stream = assert(http_request.new_from_uri(link):go())
   stream:save_body_to_file(path)
   stream:shutdown()
end

return LuaHttpDownloadBackend
