local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")

local OPDSClient = {}
OPDSClient.__index = OPDSClient

local redirect_codes = {
    [301] = true,
    [302] = true,
    [303] = true,
    [307] = true,
    [308] = true,
}

local default_ports = {
    http = 80,
    https = 443,
}

local function isIdempotentRequest(method)
    return method == nil or method == "GET" or method == "HEAD"
end

-- Headers describing a request body, dropped when a 303 turns the request into a GET
local body_headers = {
    ["content-type"] = true,
    ["content-length"] = true,
    ["content-encoding"] = true,
    ["transfer-encoding"] = true,
}

-- Headers that must never leave the origin the caller addressed
local credential_headers = {
    authorization = true,
    ["proxy-authorization"] = true,
}

local function isSameOrigin(left, right)
    return left.scheme == right.scheme
        and left.host == right.host
        and (left.port or default_ports[left.scheme]) == (right.port or default_ports[right.scheme])
end

local function isHttpsDowngrade(from_url, to_url)
    return url.parse(from_url).scheme == "https" and url.parse(to_url).scheme == "http"
end

function OPDSClient:new(options)
    return setmetatable(options, self)
end

--[[--
Performs an HTTP request, following redirects manually so cookies and credentials stay scoped.

Requests with a body (`source`) are never replayed: a 303 response is followed as a body-less GET,
any other redirect is returned to the caller unfollowed, so it can report the canonical URL.
Basic auth and Authorization headers are only sent to the origin of the initial URL,
and HTTPS to HTTP downgrades are never followed.
--]]
function OPDSClient:request(request)
    local request_url = request.url
    local original_headers = request.headers or {}
    local original_origin = url.parse(request_url)
    local method = request.method
    local source = request.source
    local drop_body_headers = false

    for _ = 1, 5 do
        local request_origin = url.parse(request_url)
        local same_origin = isSameOrigin(request_origin, original_origin)
        local headers = {}
        for name, value in pairs(original_headers) do
            local lower_name = name:lower()
            if lower_name ~= "cookie"
                and not (drop_body_headers and body_headers[lower_name])
                and not (not same_origin and credential_headers[lower_name]) then
                headers[name] = value
            end
        end
        local cookies = self.cookie_jar:headerFor(request_url)
        if cookies then headers.Cookie = cookies end

        local function makeRequest()
            local http_request = {
                url = request_url,
                method = method,
                headers = headers,
                source = source,
                sink = request.sink,
                user = same_origin and request.username or nil,
                password = same_origin and request.password or nil,
                redirect = false,
                response_headers = function(response_code)
                    return redirect_codes[response_code]
                end,
            }
            -- LuaSec params (e.g., verify/cafile), only meaningful for HTTPS
            if self.tls_params and request_origin.scheme == "https" then
                for name, value in pairs(self.tls_params) do
                    http_request[name] = value
                end
            end
            return socket.skip(1, http.request(http_request))
        end

        local code, response_headers, status = makeRequest()
        if code == socketutil.SSL_HANDSHAKE_CODE and isIdempotentRequest(method) and source == nil then
            code, response_headers, status = makeRequest()
        end
        self.cookie_jar:store(request_url, response_headers)

        if not redirect_codes[code] or not response_headers or not response_headers.location then
            return code, response_headers, status
        end

        local redirected_url = url.absolute(request_url, response_headers.location)
        if request.follow_redirects == false or isHttpsDowngrade(request_url, redirected_url) then
            return code, response_headers, status
        end
        if not isIdempotentRequest(method) or source ~= nil then
            if code ~= 303 then
                return code, response_headers, status
            end
            method = "GET"
            source = nil
            drop_body_headers = true
        end
        request_url = redirected_url
    end

    return nil, nil, "Too many redirects"
end

return OPDSClient
