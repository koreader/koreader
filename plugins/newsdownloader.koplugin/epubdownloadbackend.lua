local CacheSQLite = require("cachesqlite")
local DataStorage = require("datastorage")
local Version = require("version")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socket_url = require("socket.url")
local ssl = require("ssl")
local socketutil = require("socketutil")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local function removeSubstring(str, substr)
    local iter = 1
    local i, j
    repeat
        i, j = string.find(str, substr, iter, true)
        if i then
            str = string.sub(str, 1, i-1) .. string.sub(str, j+1, -1)
            iter = i
        end
    until not i
    return str
end

local EpubDownloadBackend = {
   -- Can be set so HTTP requests will be done under Trapper and
   -- be interruptible
   trap_widget = nil,
   -- For actions done with Trapper:dismissable methods, we may throw
   -- and error() with this code. We make the value of this error
   -- accessible here so that caller can know it's a user dismiss.
   dismissed_error_code = "Interrupted by user",
}

local FeedCache = CacheSQLite:new{
    slots = 500,
    db_path = DataStorage:getDataDir() .. "/cache/newsdownloader.sqlite",
    size = 1024 * 1024 * 10, -- 10MB
}

---Returns user specified or default options.
---@param user table
---@param default table
---@return table
local function userOrDefault(user, default)
    if type(user) == "table" and next(user) == nil then
        return default
    else
        return user
    end
end

---Selects the first matching node from the root node.
---@param root_node ElementNode
---@param user_wanted_selectors table
---@return ElementNode
local function selectMatchingNode(root_node, user_wanted_selectors)
    local default_wanted_selectors = {
        "main",
        "article",
        "div#main",
        "#main-article",
        ".main-content",
        "#body",
        "#content",
        ".content",
        "div#article",
        "div.article",
        "div.post",
        "div.post-outer",
        ".l-root",
        ".content-container",
        ".StandardArticleBody_body",
        "div#article-inner",
        "div#newsstorytext",
        "div.general",
    }
    local wanted_selectors = userOrDefault(user_wanted_selectors, default_wanted_selectors)
    logger.dbg("Selecting first matching", wanted_selectors)
    for _, selector in ipairs(wanted_selectors) do
        local nodes = root_node:select(selector)
        if nodes then
            for _, node in ipairs(nodes) do
                if node:getcontent() then
                    logger.dbg("found by selector", selector)
                    return node
                end
            end
        end
    end

    return root_node
end

---Removes unwanted nodes from previously selected node.
---@param wanted_node ElementNode
---@param user_unwanted_selectors table
---@return string
local function removeUnwantedNodes(wanted_node, user_unwanted_selectors)
    local default_unwanted_selectors = {
        "div.article__social",
        "figure.is-type-video",
        "div.fluid-width-video-wrapper",
        "div.youtube-wrap",
    }
    local unwanted_selectors = userOrDefault(user_unwanted_selectors, default_unwanted_selectors)
    logger.dbg("removing by selectors:", unwanted_selectors)
    local node_content = wanted_node:getcontent()
    for _, unwanted_selector in ipairs(unwanted_selectors) do
        local unwanted_nodes = wanted_node:select(unwanted_selector)
        if unwanted_nodes then
            for _,unwanted_node in ipairs(unwanted_nodes) do
                logger.dbg("removing", unwanted_selector)
                local unwanted_text = unwanted_node:gettext()
                node_content = removeSubstring(node_content, unwanted_text)
            end
        end
    end
    return node_content
end

---Reduces the HTML to declutter the output. It uses wanted_elements and
---unwanted_elements to "select" and "cut" parts of the HTML.
---@param input_html string
---@param user_wanted_elements table
---@param user_unwanted_elements table
---@return string
local function reduceHTML(input_html, user_wanted_elements, user_unwanted_elements)
    local htmlparser = require("htmlparser")
    local root = htmlparser.parse(input_html, 5000)

    local wanted_node = selectMatchingNode(root, user_wanted_elements)
    local cleaned_inner_html = removeUnwantedNodes(wanted_node, user_unwanted_elements)
    local output_html = "<!DOCTYPE html><html><head></head><body>" .. cleaned_inner_html .. "</body></html>"

    return output_html
end

-- From https://github.com/lunarmodules/luasocket/blob/1fad1626900a128be724cba9e9c19a6b2fe2bf6b/samples/cookie.lua
local token_class =  '[^%c%s%(%)%<%>%@%,%;%:%\\%"%/%[%]%?%=%{%}]'

local function unquote(t, quoted)
    local n = string.match(t, "%$(%d+)$")
    if n then n = tonumber(n) end
    if quoted[n] then return quoted[n]
    else return t end
end

local function parse_set_cookie(c, quoted, cookie_table)
    c = c .. ";$last=last;"
    local _, _, n, v, i = string.find(c, "(" .. token_class ..
                                      "+)%s*=%s*(.-)%s*;%s*()")
    local cookie = {
        name = n,
        value = unquote(v, quoted),
        attributes = {}
    }
    while 1 do
        _, _, n, v, i = string.find(c, "(" .. token_class ..
                                    "+)%s*=?%s*(.-)%s*;%s*()", i)
        if not n or n == "$last" then break end
        cookie.attributes[#cookie.attributes+1] = {
            name = n,
            value = unquote(v, quoted)
        }
    end
    cookie_table[#cookie_table+1] = cookie
end
local function split_set_cookie(s, cookie_table)
    cookie_table = cookie_table or {}
    -- remove quoted strings from cookie list
    local quoted = {}
    s = string.gsub(s, '"(.-)"', function(q)
        quoted[#quoted+1] = q
        return "$" .. #quoted
    end)
    -- add sentinel
    s = s .. ",$last="
    -- split into individual cookies
    local i = 1
    while 1 do
        local _, _, cookie, next_token
        _, _, cookie, i, next_token = string.find(s, "(.-)%s*%,%s*()(" ..
            token_class .. "+)%s*=", i)
        if not next_token then break end
        parse_set_cookie(cookie, quoted, cookie_table)
        if next_token == "$last" then break end
    end
    return cookie_table
end

local function quote(s)
    if string.find(s, "[ %,%;]") then return '"' .. s .. '"'
    else return s end
end

local _empty = {}
local function build_cookies(cookies)
    local s = ""
    for i,v in ipairs(cookies or _empty) do
        if v.name then
            s = s .. v.name
            if v.value and v.value ~= "" then
                s = s .. '=' .. quote(v.value)
            end
        end
        if i < #cookies then s = s .. "; " end
    end
    return s
end

local function getUrlContent(url, cookies, timeout, maxtime, add_to_cache, extra_headers)
    local parsed_url = socket_url.parse(url)
    local path = parsed_url.path
    if path then
        -- Encode invalid path chars (e.g., spaces) while preserving "/" and "%".
        -- We preserve '%' intentionally to avoid double-encoding existing escapes.
        parsed_url.path = util.urlEncode(path, "/%%")
        url = socket_url.build(parsed_url)
    end

    logger.dbg("getUrlContent(", url, ",", cookies, ", ", timeout, ",", maxtime, ",", add_to_cache, ")")

    if not timeout then timeout = 10 end
    logger.dbg("timeout:", timeout)

    local sink = {}
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
        headers = (function()
            local h = { ["cookie"] = build_cookies(cookies) }
            if extra_headers then
                for k, v in pairs(extra_headers) do
                    h[k] = v
                end
            end
            return h
        end)()
    }
    logger.dbg("request:", request)
    local code, headers, status = socket.skip(1, http.request(request))

    socketutil:reset_timeout()
    local content = table.concat(sink) -- empty or content accumulated till now
    logger.dbg(
        "getUrlContent: after http.request",
        "type(code):", type(code), "code:", code, "headers:", headers,
        "status:", status,
        "#content:", #content
    )

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", status or code)
        return false, nil, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", status or code or "network unreachable")
        return false, nil, "Network or remote server unavailable"
    end
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, nil, "Incomplete content received"
        end
    end
    if code >= 400 and code < 500 then
        logger.warn("HTTP error:", status or code)
        return false, nil, status or code
    end

    if add_to_cache then
        logger.dbg("Adding to cache", url)
        FeedCache:insert(url, {
            headers = headers,
            content = content,
        })
    end

    local content_type = nil
    if headers and headers["content-type"] then
        content_type = headers["content-type"]
    else
        logger.warn("NewsDownloader: Request didn't return a Content-Type header")
    end

    logger.dbg("Returning content ok")
    return true, content_type, content
end

function EpubDownloadBackend:getCache()
    return FeedCache
end

function EpubDownloadBackend:getConnectionCookies(url, credentials)

    local body = ""
    for k, v in pairs(credentials) do
        body = body .. (tostring(k) .. "=" .. tostring(v) .. "&")
    end
    local request = {
        method  = "POST",
        url     = url,
        headers = {
            ["content-type"] = "application/x-www-form-urlencoded",
            ["content-length"] = tostring(#body)
            },
        source = ltn12.source.string(body),
        sink    = nil
    }
    logger.dbg("request:", request, ", body: ", body)
    local code, headers, status = socket.skip(1, http.request(request))

    logger.dbg(
        "getConnectionCookies: after http.request",
        "code:", code,
        "headers:", headers,
        "status:", status
    )

    local cookies = {}
    local to_parse = headers["set-cookie"]
    split_set_cookie(to_parse, cookies)
    logger.dbg("getConnectionCookies: cookies:", cookies)

    return cookies
end

function EpubDownloadBackend:getResponseAsString(url, cookies, add_to_cache, extra_headers)
    logger.dbg("EpubDownloadBackend:getResponseAsString(", url, ")")
    local success, content_type, content = getUrlContent(url, cookies, nil, nil, add_to_cache, extra_headers)
    if (success) then
        return content_type, content
    else
        error("Failed to download content for url:", url)
    end
end

function EpubDownloadBackend:setTrapWidget(trap_widget)
    self.trap_widget = trap_widget
end

function EpubDownloadBackend:resetTrapWidget()
    self.trap_widget = nil
end

function EpubDownloadBackend:loadPage(url, cookies, extra_headers)
    local completed, success, content_type, content
    if self.trap_widget then -- if previously set with EpubDownloadBackend:setTrapWidget()
        local Trapper = require("ui/trapper")
        local timeout, maxtime = 30, 60
        -- We use dismissableRunInSubprocess with complex return values:
        completed, success, content = Trapper:dismissableRunInSubprocess(function()
            return getUrlContent(url, cookies, timeout, maxtime, nil, extra_headers)
        end, self.trap_widget)
        if not completed then
            error(self.dismissed_error_code) -- "Interrupted by user"
        end
    else
        local timeout, maxtime = 10, 60
        success, content_type, content = getUrlContent(url, cookies, timeout, maxtime, nil, extra_headers)
    end
    logger.dbg("success:", success, "type(content):", type(content), "content:", type(content) == "string" and content:sub(1, 500), "...")
    if not success then
        error(content)
    else
        return content_type, content
    end
end

local ext_to_mimetype = {
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    svg = "image/svg+xml",
    html= "application/xhtml+xml",
    xhtml= "application/xhtml+xml",
    ncx = "application/x-dtbncx+xml",
    js = "text/javascript",
    css = "text/css",
    otf = "application/opentype",
    ttf = "application/truetype",
    woff = "application/font-woff",
}

local MAX_CONCURRENT_DOWNLOADS = 10

--- Non-blocking receive; yields (socket, "r"/"w") until data/error/EOF.
-- Partial data returned with "timeout"/"wantread" is already consumed from
-- the socket buffer, so carry it forward via the `receive` prefix argument.
local function async_receive(sock, pattern)
    local acc = ""
    while true do
        local res, err, partial = sock:receive(pattern, acc)
        if err == "timeout" or err == "wantread" then
            acc = partial or acc
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return res, err, partial
        end
    end
end

--- Non-blocking send; yields (socket, "w"/"r") while it would block.
local function async_send(sock, data)
    local i = 1
    local n = #data
    while i <= n do
        local res, err, last = sock:send(data, i)
        if err == "timeout" or err == "wantwrite" then
            coroutine.yield(sock, "w")
            -- LuaSocket reports the index of the last byte sent on error.
            if last then i = last + 1 end
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err then
            return nil, err
        else
            i = res + 1
        end
    end
    return true
end

--- Non-blocking connect; yields (socket, "w") until connected or failed.
local function async_connect(sock, host, port)
    sock:settimeout(0)
    while true do
        local res, err = sock:connect(host, port)
        if res or err == "already connected" then
            return true
        elseif err == "timeout" or err == "Operation already in progress" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

--- Non-blocking TLS handshake; yields (socket, "r"/"w") while it would block.
local function async_handshake(sock)
    while true do
        local res, err = sock:dohandshake()
        if res then
            return true
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

--- Fetch one image over a raw non-blocking socket, yielding while it would
-- block so the caller can interleave many downloads.
local function download_image_async(url, redirect_count)
    redirect_count = redirect_count or 0
    if redirect_count > 5 then return false, "Too many redirects" end

    local parsed = socket_url.parse(url)
    if not parsed then return false, "invalid url" end
    if parsed.path then
        -- Encode invalid path chars (e.g., spaces) while preserving "/" and "%".
        parsed.path = util.urlEncode(parsed.path, "/%%")
        url = socket_url.build(parsed)
    end

    local host = parsed.host
    if not host then return false, "invalid url" end
    local port = parsed.port or (parsed.scheme == "https" and 443 or 80)
    local path = parsed.path or "/"
    if parsed.query then path = path .. "?" .. parsed.query end

    local sock = socket.tcp()
    local ok, err = async_connect(sock, host, port)
    if not ok then
        sock:close()
        return false, "connect error: " .. tostring(err)
    end

    if parsed.scheme == "https" then
        local ssl_params = {
            mode = "client",
            protocol = "any",
            verify = "none",
            options = {"all", "no_sslv2", "no_sslv3"},
        }
        local ssl_sock, wrap_err = ssl.wrap(sock, ssl_params)
        if not ssl_sock then
            sock:close()
            return false, "ssl wrap error: " .. tostring(wrap_err)
        end
        sock = ssl_sock
        sock:settimeout(0)
        if sock.sni then
            sock:sni(host)
        end
        local hok, herr = async_handshake(sock)
        if not hok then
            sock:close()
            return false, "ssl handshake error: " .. tostring(herr)
        end
    end

    local req = string.format(
        "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nConnection: close\r\n\r\n",
        path, host, socketutil.USER_AGENT)
    local sok, serr = async_send(sock, req)
    if not sok then
        sock:close()
        return false, "send error: " .. tostring(serr)
    end

    -- Read status line and headers.
    local headers = {}
    local status_line
    while true do
        local line, lerr = async_receive(sock, "*l")
        if not line then
            sock:close()
            return false, "read error: " .. tostring(lerr)
        end
        if line == "" then break end
        if not status_line then
            status_line = line
        else
            local k, v = line:match("^(.-):%s*(.*)")
            if k and v then headers[k:lower()] = v end
        end
    end

    if not status_line then
        sock:close()
        return false, "no status line received"
    end

    local code = tonumber(status_line:match("HTTP/%d%.%d%s+(%d%d%d)"))

    if code and code >= 300 and code < 400 and headers["location"] then
        sock:close()
        local location = headers["location"]:gsub("\r$", "")
        local new_url = socket_url.absolute(url, location)
        return download_image_async(new_url, redirect_count + 1)
    end

    if code and code >= 400 then
        sock:close()
        return false, "HTTP error " .. tostring(code)
    end

    -- Read the body, handling both chunked and fixed/until-close encodings.
    local body = {}
    local transfer_encoding = headers["transfer-encoding"]
    if transfer_encoding and transfer_encoding:lower():find("chunked", 1, true) then
        while true do
            local chunk_size_str = async_receive(sock, "*l")
            if not chunk_size_str then break end
            local hex = chunk_size_str:match("^%x+")
            if not hex then break end
            local chunk_size = tonumber(hex, 16)
            if not chunk_size or chunk_size == 0 then break end

            local chunk_data = async_receive(sock, chunk_size)
            if chunk_data and #chunk_data > 0 then table.insert(body, chunk_data) end
            async_receive(sock, 2) -- trailing CRLF
        end
    else
        local content_length = tonumber(headers["content-length"])
        if content_length then
            local remaining = content_length
            while remaining > 0 do
                local chunk = async_receive(sock, remaining)
                if not chunk then break end
                table.insert(body, chunk)
                remaining = remaining - #chunk
            end
        else
            while true do
                local chunk, cerr, partial = async_receive(sock, 8192)
                if chunk then
                    table.insert(body, chunk)
                else
                    if partial and #partial > 0 then table.insert(body, partial) end
                    if cerr == "closed" then break end
                    if cerr ~= "timeout" and cerr ~= "wantread" then
                        -- Some other error: stop reading.
                        break
                    end
                end
            end
        end
    end

    sock:close()
    local content = table.concat(body)
    return true, headers["content-type"], content
end

-- Create an epub file (with possibly images)
function EpubDownloadBackend:createEpub(epub_path, html, url, include_images, message, filter_enable, filter_element, block_element)
    logger.dbg("EpubDownloadBackend:createEpub(", epub_path, ")")
    -- Use Trapper to display progress and ask questions through the UI.
    -- We need to have been Trapper.wrap()'ed for UI to be used, otherwise
    -- Trapper:info() and Trapper:confirm() will just use logger.
    local UI = require("ui/trapper")
    -- We may need to build absolute urls for non-absolute links and images urls
    local base_url = socket_url.parse(url)

    local cancelled = false
    local page_htmltitle = html:match([[<title[^>]*>(.-)</title>]])
    logger.dbg("page_htmltitle is ", page_htmltitle)

    -- Rejigger HTML into XHTML to avoid unclosed elements. See <https://github.com/koreader/crengine/pull/370#issuecomment-910156921>.
    local cre = require("libs/libkoreader-cre")
    html = cre.getBalancedHTML(html, 0x0)

--    local sections = html.sections -- Wikipedia provided TOC
    local bookid = "bookid_placeholder" --string.format("wikipedia_%s_%s_%s", lang, phtml.pageid, phtml.revid)
    -- Not sure if this bookid may ever be used by indexing software/calibre, but if it is,
    -- should it changes if content is updated (as now, including the wikipedia revisionId),
    -- or should it stays the same even if revid changes (content of the same book updated).
    if filter_enable then html = reduceHTML(html, filter_element, block_element) end
    local images = {}
    local seen_images = {}
    local imagenum = 1
    local cover_imgid = nil -- best candidate for cover among our images
    local function isRelative(url_string)
        local parsed = socket_url.parse(url_string)
        -- If there is no scheme component, it is a relative URL.
        return parsed and parsed.scheme == nil
    end
    local processImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            logger.dbg("no src found in ", img_tag)
            return nil
        end
        if src:sub(1,5) == "data:" then
            logger.dbg("skipping data URI", src)
            return nil
        end
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Wikipedia redirects from http to https, so use https
        elseif isRelative(src) then -- non absolute url
            src = socket_url.absolute(base_url, src)
        end
        local cur_image
        if seen_images[src] then -- already seen
            cur_image = seen_images[src]
        else
            local src_ext = src
            if src_ext:find("?") then -- "/w/extensions/wikihiero/img/hiero_D22.png?0b8f1"
                src_ext = src_ext:match("(.-)%?") -- remove ?blah
            end
            local ext = src_ext:match(".*%.(%S%S%S?%S?%S?)$") -- extensions are only 2 to 5 chars
            if ext == nil then
                --- @todo Reverse the logic to download the image first so we can get the mimetype from the headers?
                ext = ""
            end
            ext = ext:lower()
            local imgid = string.format("img%05d", imagenum)
            local imgpath = ext ~= "" and string.format("images/%s.%s", imgid, ext) or string.format("images/%s", imgid)
            local mimetype = ext_to_mimetype[ext] or ""
            local width = tonumber(img_tag:match([[width="([^"]*)"]]))
            local height = tonumber(img_tag:match([[height="([^"]*)"]]))
            -- Get higher resolution (2x) image url
            local src2x = nil
            local srcset = img_tag:match([[srcset="([^"]*)"]])
            if srcset then
                srcset = " "..srcset.. ", " -- for next pattern to possibly match 1st or last item
                src2x = srcset:match([[ (%S+) 2x, ]])
                if src2x then
                    if src2x:sub(1,2) == "//" then
                        src2x = "https:" .. src2x
                    elseif src2x:sub(1,1) == "/" then -- non absolute url
                        src2x = socket_url.absolute(base_url, src2x)
                    end
                end
            end
            cur_image = {
                imgid = imgid,
                imgpath = imgpath,
                src = src,
                src2x = src2x,
                mimetype = mimetype,
                width = width,
                height = height,
            }
            table.insert(images, cur_image)
            seen_images[src] = cur_image
            -- Use first image of reasonable size (not an icon) and portrait-like as cover-image
            if not cover_imgid and width and width > 50 and height and height > 50 and height > width then
                logger.dbg("Found a suitable cover image")
                cover_imgid = imgid
            end
            imagenum = imagenum + 1
        end
        -- crengine will NOT use width and height attributes, but it will use
        -- those found in a style attribute.
        -- If we get src2x images, crengine will scale them down to the 1x image size
        -- (less space wasted by images while reading), but the 2x quality will be
        -- there when image is viewed full screen with ImageViewer widget.
        local style_props = {}
        if cur_image.width then
            table.insert(style_props, string.format("width: %spx", cur_image.width))
        end
        if cur_image.height then
            table.insert(style_props, string.format("height: %spx", cur_image.height))
        end
        local style = table.concat(style_props, "; ")
        return string.format([[<img src="%s" style="%s" alt=""/>]], cur_image.imgpath, style)
    end
    html = html:gsub("(<%s*img [^>]*>)", processImg)
    logger.dbg("Images found in html:", images)

    -- See what to do with images
    local use_img_2x = false
    if not include_images then
        -- Remove img tags to avoid little blank squares of missing images
        html = html:gsub("<%s*img [^>]*>", "")
        -- We could remove the whole image container <div class="thumb"...> ,
        -- but it's a lot of nested <div> and not easy to do.
        -- So the user will see the image legends and know a bit about
        -- the images he chose to not get.
    end

    UI:info(T(_("%1\n\nBuilding EPUB…"), message))
    -- Open the zip file (with .tmp for now, as crengine may still
    -- have a handle to the final epub_path, and we don't want to
    -- delete a good one if we fail/cancel later)
    local Archiver = require("ffi/archiver")
    local epub = Archiver.Writer:new{}
    local epub_path_tmp = epub_path .. ".tmp"
    if not epub:open(epub_path_tmp, "epub") then
        logger.dbg("Failed to open epub_path_tmp")
        return false
    end

    -- We now create and add all the required epub files
    local mtime = os.time()

    -- ----------------------------------------------------------------
    -- /mimetype : always "application/epub+zip"
    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", "application/epub+zip", mtime)
    epub:setZipCompression("deflate")

    -- ----------------------------------------------------------------
    -- /META-INF/container.xml : always the same content
    epub:addFileFromMemory("META-INF/container.xml", [[
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]], mtime)
    logger.dbg("Added META-INF/container.xml")

    -- ----------------------------------------------------------------
    -- OEBPS/content.opf : metadata + list of other files (paths relative to OEBPS/ directory)
    -- Other possible items in this file that are of no interest to crengine :
    --   In <manifest> :
    --     <item id="cover" href="title.html" media-type="application/xhtml+xml"/>
    --     <item id="cover-image" href="images/cover.png" media-type="image/png"/>
    -- (crengine only uses <meta name="cover" content="cover-image" /> to get the cover image)
    --   In <spine toc="ncx"> :
    --     <itemref idref="cover" linear="no"/>
    --   And a <guide> section :
    --     <guide>
    --       <reference href="title.html" type="cover" title="Cover"/>
    --       <reference href="toc.html" type="toc" title="Table of Contents" href="toc.html" />
    --     </guide>
    local content_opf_parts = {}
    -- head
    local meta_cover = "<!-- no cover image -->"
    if include_images and cover_imgid then
        meta_cover = string.format([[<meta name="cover" content="%s"/>]], cover_imgid)
    end
    logger.dbg("meta_cover:", meta_cover)
    table.insert(content_opf_parts, string.format([[
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        unique-identifier="bookid" version="2.0">
  <metadata>
    <dc:title>%s</dc:title>
    <dc:publisher>KOReader %s</dc:publisher>
    %s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
    <item id="css" href="stylesheet.css" media-type="text/css"/>
]], page_htmltitle, Version:getCurrentRevision(), meta_cover))
    -- images files
    if include_images then
        for inum, img in ipairs(images) do
            table.insert(content_opf_parts, string.format([[    <item id="%s" href="%s" media-type="%s"/>%s]], img.imgid, img.imgpath, img.mimetype, "\n"))
        end
    end
    -- tail
    table.insert(content_opf_parts, [[
  </manifest>
  <spine toc="ncx">
    <itemref idref="content"/>
  </spine>
</package>
]])
    epub:addFileFromMemory("OEBPS/content.opf", table.concat(content_opf_parts), mtime)
    logger.dbg("Added OEBPS/content.opf")

    -- ----------------------------------------------------------------
    -- OEBPS/stylesheet.css
    --- @todo We told it we'd include a stylesheet.css, so it's probably best
    -- that we do. In theory, we could try to fetch any *.css files linked in
    -- the main html.
    epub:addFileFromMemory("OEBPS/stylesheet.css", [[
/* Empty */
]], mtime)
    logger.dbg("Added OEBPS/stylesheet.css")

    -- ----------------------------------------------------------------
    -- OEBPS/toc.ncx : table of content
    local toc_ncx_parts = {}
    local depth = 0
    local cur_level = 0
    local np_end = [[</navPoint>]]
    local num = 1
    -- Add our own first section for first page, with page name as title
    table.insert(toc_ncx_parts, string.format([[<navPoint id="navpoint-%s" playOrder="%s"><navLabel><text>%s</text></navLabel><content src="content.html"/>]], num, num, page_htmltitle))
    table.insert(toc_ncx_parts, np_end)
    --- @todo Not essential for most articles, but longer articles might benefit
    -- from parsing <h*> tags and constructing a proper TOC
    while cur_level > 0 do
        table.insert(toc_ncx_parts, np_end)
        cur_level = cur_level - 1
    end
    -- Prepend NCX head
    table.insert(toc_ncx_parts, 1, string.format([[
<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="%s"/>
    <meta name="dtb:depth" content="%s"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>%s</text>
  </docTitle>
  <navMap>
]], bookid, depth, page_htmltitle))
    -- Append NCX tail
    table.insert(toc_ncx_parts, [[
  </navMap>
</ncx>
]])
    epub:addFileFromMemory("OEBPS/toc.ncx", table.concat(toc_ncx_parts), mtime)
    logger.dbg("Added OEBPS/toc.ncx")

    -- ----------------------------------------------------------------
    -- OEBPS/content.html
    epub:addFileFromMemory("OEBPS/content.html", html, mtime)
    logger.dbg("Added OEBPS/content.html")

    -- Force a GC to free the memory we used till now (the second call may
    -- help reclaim more memory).
    collectgarbage()
    collectgarbage()

    -- ----------------------------------------------------------------
    -- OEBPS/images/*
    if include_images then
        local nb_images = #images
        local before_images_time = time.now()
        local time_prev = before_images_time

        -- Download images concurrently: each coroutine yields its socket when
        -- it would block, and socket.select tells us which are ready to resume.
        local pending_tasks = {}
        for inum, img in ipairs(images) do
            table.insert(pending_tasks, {inum = inum, img = img})
        end

        local active = {}        -- coroutines currently running
        local co2sock = {}       -- coroutine -> socket it is waiting on
        local co2mode = {}       -- coroutine -> "r" or "w"
        local completed = 0
        local failed_images = {}

        local function refill_pool()
            while #active < MAX_CONCURRENT_DOWNLOADS and #pending_tasks > 0 do
                local task = table.remove(pending_tasks, 1)
                local co = coroutine.create(function()
                    local src = task.img.src
                    if use_img_2x and task.img.src2x then
                        src = task.img.src2x
                    end
                    logger.dbg("Getting img async:", src)
                    local success, err_msg_or_headers, content = download_image_async(src)

                    if not success then
                        logger.warn("async download failed:", err_msg_or_headers, "falling back to getUrlContent")
                        -- Fallback to the synchronous getter for edge cases.
                        success, dummy, content = getUrlContent(src)
                    end

                    coroutine.yield("RESULT", task, success, content)
                end)
                table.insert(active, co)
            end
        end

        refill_pool()

        while #active > 0 do
            -- Gather sockets we're waiting on and select() on them.
            local recvt = {}
            local sendt = {}
            for _, co in ipairs(active) do
                local sock = co2sock[co]
                if sock then
                    if co2mode[co] == "r" then table.insert(recvt, sock) end
                    if co2mode[co] == "w" then table.insert(sendt, sock) end
                end
            end

            local ready
            if #recvt > 0 or #sendt > 0 then
                local r, w = socket.select(recvt, sendt, 0.1)
                ready = {}
                for _, s in ipairs(r or {}) do ready[s] = true end
                for _, s in ipairs(w or {}) do ready[s] = true end
            end

            -- Resume coroutines that are ready (or haven't yielded a socket yet).
            local next_active = {}
            for _, co in ipairs(active) do
                local sock = co2sock[co]
                local is_ready = not sock or (ready and ready[sock])

                if not is_ready then
                    table.insert(next_active, co)
                else
                    if sock then
                        co2sock[co] = nil
                        co2mode[co] = nil
                    end

                    local ok, yield_type, task_or_mode, success, content = coroutine.resume(co)

                    if not ok then
                        logger.warn("image download coroutine error:", yield_type)
                        completed = completed + 1
                    elseif coroutine.status(co) == "dead" then
                        -- Finished without a RESULT yield; treat as done.
                        completed = completed + 1
                    elseif yield_type == "RESULT" then
                        local task = task_or_mode
                        completed = completed + 1
                        if success and content then
                            -- Images do not need to be compressed, so spare some cpu cycles
                            local no_compression = true
                            if task.img.mimetype == "image/svg+xml" then -- except for SVG images (which are XML text)
                                no_compression = false
                            end
                            epub:addFileFromMemory("OEBPS/"..task.img.imgpath, content, no_compression, mtime)
                        else
                            logger.info("failed fetching:", task.img.src)
                            table.insert(failed_images, task.inum)
                        end
                    else
                        -- The coroutine yielded a socket to wait on.
                        co2sock[co] = yield_type
                        co2mode[co] = task_or_mode
                        table.insert(next_active, co)
                    end
                end
            end
            active = next_active

            refill_pool()

            -- Process can be interrupted every second between image downloads
            -- by tapping while the InfoMessage is displayed.
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()
                local go_on = UI:info((message and message ~= "" and message .. "\n\n" or "") .. T(_("Retrieving images… %1 / %2 completed"), completed, nb_images), completed >= 1)
                if not go_on then
                    cancelled = true
                    break
                end
            end
        end

        -- Report any failures once, rather than interrupting on each one.
        if not cancelled and #failed_images > 0 then
            local go_on = UI:confirm(T(_("%1 images failed to download. Continue creating the EPUB?"), #failed_images), _("Stop"), _("Continue"))
            if not go_on then
                cancelled = true
            end
        end

        logger.dbg("Image download time for:", page_htmltitle, time.to_ms(time.since(before_images_time)), "ms")
    end

    -- Done with adding files
    if cancelled then
        if UI:confirm(_("Download did not complete.\nDo you want to create an EPUB with the already downloaded images?"), _("Don't create"), _("Create")) then
            cancelled = false
        end
    end
    if cancelled then
        UI:info(_("Canceled. Cleaning up…"))
    else
        UI:info(T(_("%1\n\nPacking EPUB…"), message))
    end
    epub:close()

    if cancelled then
        -- Build was cancelled, remove half created .epub
        if lfs.attributes(epub_path_tmp, "mode") == "file" then
            os.remove(epub_path_tmp)
        end
        return false
    end

    -- Finally move the .tmp to the final file
    os.rename(epub_path_tmp, epub_path)
    logger.dbg("successfully created:", epub_path)

    -- Force a GC to free the memory we used (the second call may help
    -- reclaim more memory).
    collectgarbage()
    collectgarbage()
    return true
end

return EpubDownloadBackend
