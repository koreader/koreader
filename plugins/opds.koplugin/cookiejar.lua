local url = require("socket.url")

local CookieJar = {}
CookieJar.__index = CookieJar

local function domainMatches(host, domain)
    return host == domain or host:sub(-#domain - 1) == "." .. domain
end

local function pathMatches(request_path, cookie_path)
    if request_path == cookie_path then return true end
    if request_path:sub(1, #cookie_path) ~= cookie_path then return false end
    return cookie_path:sub(-1) == "/" or request_path:sub(#cookie_path + 1, #cookie_path + 1) == "/"
end

local function defaultPath(request_path)
    if not request_path or request_path:sub(1, 1) ~= "/" then return "/" end
    local last_slash = request_path:match("^.*()/")
    return last_slash and request_path:sub(1, last_slash) or "/"
end

local function splitSetCookie(value)
    local cookies = {}
    if type(value) == "table" then
        for _, header in ipairs(value) do
            for _, cookie in ipairs(splitSetCookie(header)) do
                table.insert(cookies, cookie)
            end
        end
        return cookies
    end

    local start = 1
    while start <= #value do
        local separator = value:find(",%s*[^%c%s%(%)%<%>%@%,%;%:%\"%/%[%]%?%=%{%}]+%s*=", start)
        if not separator then
            table.insert(cookies, value:sub(start))
            break
        end
        table.insert(cookies, value:sub(start, separator - 1))
        start = separator + 1
    end
    return cookies
end

function CookieJar:new()
    return setmetatable({ cookies = {} }, self)
end

function CookieJar:store(response_url, headers)
    local parsed_url = url.parse(response_url)
    local host = parsed_url.host and parsed_url.host:lower()
    if not host then return end

    for header_name, value in pairs(headers or {}) do
        if header_name:lower() == "set-cookie" then
            for _, set_cookie in ipairs(splitSetCookie(value)) do
                local name, cookie_value = set_cookie:match("^%s*([^=;%s]+)=([^;]*)")
                if name then
                    local cookie = {
                        name = name,
                        value = cookie_value,
                        domain = host,
                        host_only = true,
                        path = defaultPath(parsed_url.path),
                    }
                    local max_age
                    for attribute in set_cookie:gmatch(";([^;]+)") do
                        local attribute_name, attribute_value = attribute:match("^%s*([^=;%s]+)%s*=?%s*(.-)%s*$")
                        attribute_name = attribute_name and attribute_name:lower()
                        if attribute_name == "domain" and attribute_value ~= "" then
                            local domain = attribute_value:lower():gsub("^%.", "")
                            if domainMatches(host, domain) then
                                cookie.domain = domain
                                cookie.host_only = false
                            end
                        elseif attribute_name == "path" and attribute_value:sub(1, 1) == "/" then
                            cookie.path = attribute_value
                        elseif attribute_name == "secure" then
                            cookie.secure = true
                        elseif attribute_name == "max-age" then
                            max_age = tonumber(attribute_value)
                        end
                    end
                    if max_age then cookie.expires_at = os.time() + max_age end

                    for index = #self.cookies, 1, -1 do
                        local existing = self.cookies[index]
                        if existing.name == cookie.name and existing.domain == cookie.domain and existing.path == cookie.path then
                            table.remove(self.cookies, index)
                        end
                    end
                    if not cookie.expires_at or cookie.expires_at > os.time() then
                        table.insert(self.cookies, cookie)
                    end
                end
            end
        end
    end
end

function CookieJar:headerFor(request_url)
    local parsed_url = url.parse(request_url)
    local host = parsed_url.host and parsed_url.host:lower()
    if not host then return nil end

    local request_path = parsed_url.path or "/"
    local matched = {}
    for index = #self.cookies, 1, -1 do
        local cookie = self.cookies[index]
        if cookie.expires_at and cookie.expires_at <= os.time() then
            table.remove(self.cookies, index)
        elseif (cookie.host_only and host == cookie.domain or not cookie.host_only and domainMatches(host, cookie.domain))
            and pathMatches(request_path, cookie.path)
            and (not cookie.secure or parsed_url.scheme == "https") then
            table.insert(matched, cookie)
        end
    end
    table.sort(matched, function(left, right)
        return #left.path > #right.path
    end)
    local values = {}
    for _, cookie in ipairs(matched) do
        table.insert(values, cookie.name .. "=" .. cookie.value)
    end
    return #values > 0 and table.concat(values, "; ") or nil
end

return CookieJar