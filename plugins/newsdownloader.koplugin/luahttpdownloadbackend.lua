local logger = require("logger")
local http_request = require "http.request"


local LuaHttpDownloadBackend = {}


function LuaHttpDownloadBackend:getResponseAsString(url)
   local headers, stream = assert(http_request.new_from_uri(url):go())
   local body = assert(stream:get_body_as_string())
   return body
end



function LuaHttpDownloadBackend:download(link, path)
   local headers, stream = assert(http_request.new_from_uri(link):go())
   stream:save_body_to_file(path)
   stream:shutdown()
end



return LuaHttpDownloadBackend
