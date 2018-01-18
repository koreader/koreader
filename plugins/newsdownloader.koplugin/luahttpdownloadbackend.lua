local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")

local LuaHttpDownloadBackend = {}


--function LuaHttpDownloadBackend:processFeedSource(url, limit, unsupported_feeds_urls, download_full_article)
function LuaHttpDownloadBackend:getResponseAsString(url)
   local http_request = require "http.request"
   local headers, stream = assert(http_request.new_from_uri(url):go())
   local body = assert(stream:get_body_as_string())
   if headers:get ":status" ~= "200" then
       error(body)
   end
   print(body)
   return body
end



--function LuaHttpDownloadBackend:downloadFeed(feed, feed_output_dir)
function LuaHttpDownloadBackend:download(link, path)
   local http_request = require "http.request"
   local headers, stream = assert(http_request.new_from_uri(link):go())
   stream:save_body_to_file(path)
   stream:shutdown()
end



return LuaHttpDownloadBackend
