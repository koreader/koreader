local Request = require("libs/http/request")
local HttpError = require("libs/http/httperror")
local socket_url = require("socket.url")

local RequestFactory = {

}

function RequestFactory:makeGetRequest(url, config)

    local parsed_url = socket_url.parse(url)

    if not Request.scheme[parsed_url["scheme"]]
    then
        return false, HttpError.REQUEST_UNSUPPORTED_SCHEME
    end

    return Request:new{
        url = url,
        timeout = config.timeout,
        maxtime = config.maxtime,
        method = Request.method.get
    }
end

return RequestFactory
