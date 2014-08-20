local socket = require('socket')
local url = require('socket.url')
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local JSON = require("JSON")
local DEBUG = require("dbg")

--[[
-- Translate text using Google Translate.
-- http://translate.google.com/translate_a/t?client=z&ie=UTF-8&oe=UTF-8&hl=en&tl=en&text=hello
--]]

local Translator = {
   trans_servers = {
       "http://translate.google.cn",
       "http://translate.google.com",
   },
   trans_path = "/translate_a/t",
   trans_params = {
       client = "z",  -- client z returns normal JSON result
       ie = "UTF-8",
       oe = "UTF-8",
       hl = "en",
       tl = "en",
       sl = nil, -- we don't specify source languagae to detect language
   },
   default_lang = "en",
}

function Translator:getTransServer()
    return G_reader_settings:readSetting("trans_server") or self.trans_servers[1]
end

--[[
--  return decoded JSON table from translate server
--]]
function Translator:loadPage(target_lang, source_lang, text)
    local request, sink = {}, {}
    local query = ""
    self.trans_params.tl = target_lang
    self.trans_params.sl = source_lang
    for k,v in pairs(self.trans_params) do
        query = query .. k .. '=' .. v .. '&'
    end
    local parsed = url.parse(self:getTransServer())
    parsed.path = self.trans_path
    parsed.query = query .. "text=" .. url.escape(text)

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
            --DEBUG("translate result", result)
            return result
        else
            DEBUG("error:", result)
        end
    end
end

function Translator:detect(text)
    local result = self:loadPage("en", nil, text)
    if result then
        local src_lang = result.src
        DEBUG("detected language:", src_lang)
        return src_lang
    else
        return self.default_lang
    end
end

return Translator
