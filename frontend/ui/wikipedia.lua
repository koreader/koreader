local socket = require('socket')
local url = require('socket.url')
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local JSON = require("JSON")
local DEBUG = require("dbg")

--[[
-- Query wikipedia using Wikimedia Web API.
-- http://en.wikipedia.org/w/api.php?action=query&prop=extracts&format=json&exintro=&explaintext=&redirects=&titles=hello
--]]

local Wikipedia = {
   wiki_server = "http://%s.wikipedia.org",
   wiki_path = "/w/api.php",
   wiki_params = {
       action = "query",
       prop = "extracts",
       format = "json",
       exintro = "",
       explaintext = "",
       redirects = "",
   },
   default_lang = "en",
}

function Wikipedia:getWikiServer(lang)
    return string.format(self.wiki_server, lang or self.default_lang)
end

--[[
--  return decoded JSON table from Wikipedia
--]]
function Wikipedia:loadPage(text, lang, intro, plain)
    local request, sink = {}, {}
    local query = ""
    self.wiki_params.exintro = intro and "" or nil
    self.wiki_params.explaintext = plain and "" or nil
    for k,v in pairs(self.wiki_params) do
        query = query .. k .. '=' .. v .. '&'
    end
    local parsed = url.parse(self:getWikiServer(lang))
    parsed.path = self.wiki_path
    parsed.query = query .. "titles=" .. url.escape(text)

    -- HTTP request
    request['url'] = url.build(parsed)
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    DEBUG("request", request)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local code, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    local content = table.concat(sink)
    if content ~= "" then
        local ok, result = pcall(JSON.decode, JSON, content)
        if ok and result then
            DEBUG("wiki result", result)
            return result
        else
            DEBUG("error:", result)
        end
    end
end

-- extract intro passage in wiki page
function Wikipedia:wikintro(text, lang)
    local result = self:loadPage(text, lang, true, true)
    if result then
        local query = result.query
        if query then
            return query.pages
        end
    end
end

return Wikipedia
