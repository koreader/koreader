local JSON = require("json")
local DEBUG = require("dbg")

--[[
-- Query wikipedia using Wikimedia Web API.
-- https://en.wikipedia.org/w/api.php?format=jsonfm&action=query&generator=search&gsrnamespace=0&gsrsearch=ereader&gsrlimit=10&prop=extracts&exintro&explaintext&exlimit=max
-- https://en.wikipedia.org/w/api.php?action=query&prop=extracts&format=jsonfm&explaintext=&redirects=&titles=E-reader
--]]

local Wikipedia = {
   wiki_server = "https://%s.wikipedia.org",
   wiki_path = "/w/api.php",
   wiki_params = {
       action = "query",
       prop = "extracts",
       format = "json",
       -- exintro = nil, -- get more than only the intro
       explaintext = "",
       redirects = "",
       -- title = nil, -- text to lookup, will be added below
   },
   default_lang = "en",
   -- Search query for better results
   -- see https://www.mediawiki.org/wiki/API:Main_page
   wiki_search_params = {
       action = "query",
       generator = "search",
       gsrnamespace = "0",
       -- gsrsearch = nil, -- text to lookup, will be added below
       gsrlimit = 20, -- max nb of results to get
       exlimit = "max",
       prop = "extracts|info", -- 'extracts' to get text, 'info' to get full page length
       format = "json",
       explaintext = "",
       exintro = "",
       -- We have to use 'exintro=' to get extracts for ALL results
       -- (otherwise, we get the full text for only the first result, and
       -- no text at all for the others
   },
}

function Wikipedia:getWikiServer(lang)
    return string.format(self.wiki_server, lang or self.default_lang)
end

--[[
--  return decoded JSON table from Wikipedia
--]]
function Wikipedia:loadPage(text, lang, intro, plain)
    local socket = require('socket')
    local url = require('socket.url')
    local http = require('socket.http')
    local https = require('ssl.https')
    local ltn12 = require('ltn12')

    local request, sink = {}, {}
    local query = ""

    local parsed = url.parse(self:getWikiServer(lang))
    parsed.path = self.wiki_path
    if intro == true then -- search query
        self.wiki_search_params.explaintext = plain and "" or nil
        for k,v in pairs(self.wiki_search_params) do
            query = query .. k .. '=' .. v .. '&'
        end
        parsed.query = query .. "gsrsearch=" .. url.escape(text)
    else -- full page content
        self.wiki_params.explaintext = plain and "" or nil
        for k,v in pairs(self.wiki_params) do
            query = query .. k .. '=' .. v .. '&'
        end
        parsed.query = query .. "titles=" .. url.escape(text)
    end

    -- HTTP request
    request['url'] = url.build(parsed)
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    DEBUG("request", request)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    if status ~= "HTTP/1.1 200 OK" then
        DEBUG("HTTP status not okay:", status)
        return
    end

    local content = table.concat(sink)
    if content ~= "" and string.sub(content, 1,1) == "{" then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            DEBUG("wiki result", result)
            return result
        else
            DEBUG("error:", result)
        end
    else
        DEBUG("not JSON:", content)
    end
end

-- search wikipedia and get intros for results
function Wikipedia:wikintro(text, lang)
    local result = self:loadPage(text, lang, true, true)
    if result then
        local query = result.query
        if query then
            return query.pages
        end
    end
end

-- get full content of a wiki page
function Wikipedia:wikifull(text, lang)
    local result = self:loadPage(text, lang, false, true)
    if result then
        local query = result.query
        if query then
            return query.pages
        end
    end
end


return Wikipedia
