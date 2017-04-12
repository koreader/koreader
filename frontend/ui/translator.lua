--[[--
This module translates text using Google Translate.

<http://translate.google.com/translate_a/t?client=z&ie=UTF-8&oe=UTF-8&hl=en&tl=en&text=hello>
--]]

local JSON = require("json")
local logger = require("logger")

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

--[[--
Returns decoded JSON table from translate server.

@string target_lang
@string source_lang
@string text
@treturn string result, or nil
--]]
function Translator:loadPage(target_lang, source_lang, text)
    local socket = require('socket')
    local url = require('socket.url')
    local http = require('socket.http')
    local https = require('ssl.https')
    local ltn12 = require('ltn12')

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
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    if status ~= "HTTP/1.1 200 OK" then
        logger.warn("translator HTTP status not okay:", status)
        return
    end

    local content = table.concat(sink)
    if content ~= "" and string.sub(content, 1,1) == "{" then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            return result
        else
            logger.warn("translator error:", result)
        end
    else
        logger.warn("not JSON in translator response:", content)
    end
end

--[[--
Tries to automatically detect language of `text`.

@string text
@treturn string lang (`"en"`, `"fr"`, `…`)
--]]
function Translator:detect(text)
    local result = self:loadPage("en", nil, text)
    if result then
        local src_lang = result.src
        logger.dbg("detected language:", src_lang)
        return src_lang
    else
        return self.default_lang
    end
end

return Translator
