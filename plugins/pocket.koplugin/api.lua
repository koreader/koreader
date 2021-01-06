local http = require("socket.http")
local JSON = require("json")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Api = {}

function Api:new(consumer_key, access_token, page_size)
    local self = setmetatable(Api, {})
    self.consumer_key = consumer_key
    self.access_token = access_token
    self.page_size = page_size
    self.server_url = 'https://getpocket.com/v3'
    return self
end

function Api:commonPayload()
    return {
        consumer_key = self.consumer_key,
        access_token = self.access_token
    }
end

function Api:commonHeaders()
    return { ["Content-Type"] = "application/json" }
end

function Api:fetchArticlesPayload(page, tags)
    local payload = self:commonPayload()
    payload.count = self.page_size
    payload.offset = page
    payload.detailType = "complete" --- needed to obtain tags
    return payload
end

function Api:getArticleList(page, tags)
    local payload = self:fetchArticlesPayload(page, tags)
    return self:sendReq('POST', self.server_url .. '/get', self:commonHeaders(), JSON.encode(payload), "", true)
end

function Api:addArticle(url)
    local payload = self:commonPayload()
    payload.url = url
    self:sendReq('POST', self.server_url + '/add', self:commonHeaders(), JSON.encode(payload), '', true)
end

function Api:modifyArticle(id, action)
    local payload = self:commonPayload()
    payload.actions = {
        {
            action=action,
            item_id=id,
        }
    }
    self:sendReq('POST', self.server_url + '/send', self:commonHeaders(), JSON.encode(payload), '', true)
end

function Api:sendReq(method, apiurl, headers, body, filepath, quiet)
    local sink = {}
    -- without Content–Length request is sent chunked, pocket server doesn't support that
    headers["Content-Length"] = tostring(#body)
    local request = {
        url = apiurl,
        method = method,
        headers = headers,
    }

    if filepath ~= "" then
        request.sink = ltn12.sink.file(io.open(filepath, "w"))
    else
        request.sink = ltn12.sink.table(sink)
    end
    if body ~= "" then
        request.source = ltn12.source.string(body)
    end
    logger.dbg("Pocket: URL     ", request.url)
    logger.dbg("Pocket: method  ", method)
    logger.dbg("Pocket: req  ",    request)

    http.TIMEOUT = 30
    local httpRequest = http.request
    local code, resp_headers = socket.skip(1, httpRequest(request))
    -- raise error message when network is unavailable
    if resp_headers == nil then
        logger.dbg("Pocket: Server error: ", code)
        return false
    end
    if code == 200 then
        if filepath ~= "" then
            logger.dbg("Pocket: file downloaded to", filepath)
            return true
        else
            local content = table.concat(sink)
            if content ~= "" and string.sub(content, 1,1) == "{" then
                local ok, result = pcall(JSON.decode, content)
                if ok and result then
                    -- Only enable this log when needed, the output can be large
                    return result
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Server response is not valid."), })
                end
            else
                UIManager:show(InfoMessage:new{
                    text = _("Server response is not valid."), })
            end
        end
    else
        if filepath ~= "" then
            local entry_mode = lfs.attributes(filepath, "mode")
            if entry_mode == "file" then
                os.remove(filepath)
                logger.dbg("Pocket: Removed failed download: ", filepath)
            end
        elseif not quiet then
            UIManager:show(InfoMessage:new{
                text = _("Communication with server failed."), })
        end
        return false
    end
end

return Api