local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ltn12 = require("ltn12")
local https = require("ssl.https")
local rapidjson = require("rapidjson")
local socket = require("socket")
local _ = require("gettext")
local T = require("ffi/util").template

local Api = {
    base_url = "https://www.googleapis.com/webfonts/v1/webfonts",
    font_variant = {
        ["regular"] = "regular",
        ["italic"] = "italic",
        ["500"] = "medium",
        ["500italic"] = "medium-italic",
        ["700"] = "bold",
        ["700italic"] = "bold-italic",
    },
}

function Api:init(file)
    local fallback_key = "AIzaSyDQZaihK8Lb7jJ3DYyrQrpyyJF7tyvrqAs"
    if not file then
        self.api_key = fallback_key
        return
    end
    local keyfile = io.open(file, "r")
    if keyfile then
        local key = keyfile:read("*a")
        keyfile:close()
        self.api_key = key
        return
    end
    self.api_key = fallback_key
end

function Api:request()
    local request, sink = {}, {}
    request['url'] = self.base_url .. "?key=" .. self.api_key
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    https.TIMEOUT = 10
    local _, headers, status = socket.skip(1, https.request(request))
    if headers == nil then
        return nil, "Network is unreachable"
    elseif status ~= "HTTP/1.1 200 OK" then
        return nil, status
    else
        local json = rapidjson.decode(table.concat(sink))
        if not json then
            return nil, "Can't decode server response"
        end
        return json
    end
end

function Api:getFonts()
    local t, err = self:request()
    if not t or not t.items or type(t.items) ~= "table" then
        return {}, err
    end
    return t.items
end

function Api:downloadFont(t, family)
    for index, font in ipairs(t) do
        if font.family == family then
            for key, value in pairs(self.font_variant) do
                if t[index].files[key] then
                    local font_id = t[index]
                    local font_name = string.format("%s-%s.ttf", family, value)
                    local dummy, code = https.request{
                        url = font_id.files[key],
                        sink = ltn12.sink.file(io.open(font_name, "w")),
                    }
                    UIManager:show(InfoMessage:new{
                        text = T(_("Downloading %1: %2"), font_name,
                            code == 200 and _("Ok") or _("Failed")),
                        timeout = 2,
                    })

                end
            end
        end
    end
end

return Api
