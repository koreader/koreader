local Version = require("version")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local _ = require("gettext")
local T = ffiutil.template

local EpubDownloadBackend = {
   -- Can be set so HTTP requests will be done under Trapper and
   -- be interruptible
   trap_widget = nil,
   -- For actions done with Trapper:dismissable methods, we may throw
   -- and error() with this code. We make the value of this error
   -- accessible here so that caller can know it's a user dismiss.
   dismissed_error_code = "Interrupted by user",
}
local max_redirects = 5; --prevent infinite redirects

-- filter HTML using CSS selector
local function filter(text, element)
    local htmlparser = require("htmlparser")
    local root = htmlparser.parse(text, 5000)
    local filtered = nil
    local selectors = {
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
    if element and element ~= "" then
        table.insert(selectors, 1, element)
    end
    for _, sel in ipairs(selectors) do
       local elements = root:select(sel)
       if elements then
           for _, e in ipairs(elements) do
               filtered = e:getcontent()
               if filtered then
                   break
               end
           end
           if filtered then
               break
           end
       end
    end
    if not filtered then
        return text
    end
    return "<!DOCTYPE html><html><head></head><body>" .. filtered .. "</body></html>"
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

-- Get URL content
local function getUrlContent(url, cookies, timeout, maxtime, redirectCount)
    logger.dbg("getUrlContent(", url, ",", cookies, ", ", timeout, ",", maxtime, ",", redirectCount, ")")
    if not redirectCount then
        redirectCount = 0
    elseif redirectCount == max_redirects then
        error("EpubDownloadBackend: reached max redirects: ", redirectCount)
    end

    if not timeout then timeout = 10 end
    logger.dbg("timeout:", timeout)

    local sink = {}
    local parsed = socket_url.parse(url)
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
        headers = {
            ["cookie"] = build_cookies(cookies)
        }
    }
    logger.dbg("request:", request)
    local code, headers, status = socket.skip(1, http.request(request))

    socketutil:reset_timeout()
    local content = table.concat(sink) -- empty or content accumulated till now
    logger.dbg("After http.request")
    logger.dbg("type(code):", type(code))
    logger.dbg("code:", code)
    logger.dbg("headers:", headers)
    logger.dbg("status:", status)
    logger.dbg("#content:", #content)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", status or code)
        return false, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", status or code or "network unreachable")
        return false, "Network or remote server unavailable"
    end
    if not code or code < 200 or code > 299 then -- all 200..299 HTTP codes are OK
        if code and code > 299 and code < 400  and headers and headers.location then -- handle 301, 302...
           local redirected_url = headers.location
           local parsed_redirect_location = socket_url.parse(redirected_url)
           if not parsed_redirect_location.host then
             parsed_redirect_location.host = parsed.host
             parsed_redirect_location.scheme = parsed.scheme
             redirected_url = socket_url.build(parsed_redirect_location)
           end
           logger.dbg("getUrlContent: Redirecting to url: ", redirected_url)
           return getUrlContent(redirected_url, timeout, maxtime, redirectCount + 1)
        else
           error("EpubDownloadBackend: Don't know how to handle HTTP response status:", status or code)
        end
        logger.warn("HTTP status not okay:", status or code)
        return false, "Remote server error or unavailable"
    end
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, "Incomplete content received"
        end
    end
    logger.dbg("Returning content ok")
    return true, content
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

    logger.dbg("code:", code)
    logger.dbg("headers:", headers)
    logger.dbg("status:", status)

    local cookies = {}
    local to_parse = headers["set-cookie"]
    split_set_cookie(to_parse, cookies)
    logger.dbg("Cookies: ", cookies)

    return cookies
end

function EpubDownloadBackend:getResponseAsString(url, cookies)
    logger.dbg("EpubDownloadBackend:getResponseAsString(", url, ")")
    local success, content = getUrlContent(url, cookies)
    if (success) then
        return content
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

function EpubDownloadBackend:loadPage(url, cookies)
    local completed, success, content
    if self.trap_widget then -- if previously set with EpubDownloadBackend:setTrapWidget()
        local Trapper = require("ui/trapper")
        local timeout, maxtime = 30, 60
        -- We use dismissableRunInSubprocess with complex return values:
        completed, success, content = Trapper:dismissableRunInSubprocess(function()
            return getUrlContent(url, cookies, timeout, maxtime)
        end, self.trap_widget)
        if not completed then
            error(self.dismissed_error_code) -- "Interrupted by user"
        end
    else
        local timeout, maxtime = 10, 60
        success, content = getUrlContent(url, cookies, timeout, maxtime)
    end
    logger.dbg("success:", success, "type(content):", type(content), "content:", content:sub(1, 500), "...")
    if not success then
        error(content)
    else
        return content
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
-- Create an epub file (with possibly images)
function EpubDownloadBackend:createEpub(epub_path, html, url, include_images, message, filter_enable, filter_element)
    logger.dbg("EpubDownloadBackend:createEpub(", epub_path, ")")
    -- Use Trapper to display progress and ask questions through the UI.
    -- We need to have been Trapper.wrap()'ed for UI to be used, otherwise
    -- Trapper:info() and Trapper:confirm() will just use logger.
    local UI = require("ui/trapper")
    -- We may need to build absolute urls for non-absolute links and images urls
    local base_url = socket_url.parse(url)

    local cancelled = false
    local page_htmltitle = html:match([[<title>(.*)</title>]])
    logger.dbg("page_htmltitle is ", page_htmltitle)
--    local sections = html.sections -- Wikipedia provided TOC
    local bookid = "bookid_placeholder" --string.format("wikipedia_%s_%s_%s", lang, phtml.pageid, phtml.revid)
    -- Not sure if this bookid may ever be used by indexing software/calibre, but if it is,
    -- should it changes if content is updated (as now, including the wikipedia revisionId),
    -- or should it stays the same even if revid changes (content of the same book updated).
    if filter_enable then html = filter(html, filter_element) end
    local images = {}
    local seen_images = {}
    local imagenum = 1
    local cover_imgid = nil -- best candidate for cover among our images
    local processImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            logger.dbg("no src found in ", img_tag)
            return nil
        end
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Wikipedia redirects from http to https, so use https
        elseif src:sub(1,1) == "/" then -- non absolute url
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
            if ext == nil or ext == "" then
                -- we won't know what mimetype to use, ignore it
                logger.dbg("no file extension found in ", src)
                return nil
            end
            ext = ext:lower()
            local imgid = string.format("img%05d", imagenum)
            local imgpath = string.format("images/%s.%s", imgid, ext)
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
    local epub_path_tmp = epub_path .. ".tmp"
    local ZipWriter = require("ffi/zipwriter")
    local epub = ZipWriter:new{}
    if not epub:open(epub_path_tmp) then
        logger.dbg("Failed to open epub_path_tmp")
        return false
    end

    -- We now create and add all the required epub files

    -- ----------------------------------------------------------------
    -- /mimetype : always "application/epub+zip"
    epub:add("mimetype", "application/epub+zip")

    -- ----------------------------------------------------------------
    -- /META-INF/container.xml : always the same content
    epub:add("META-INF/container.xml", [[
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]])
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
    epub:add("OEBPS/content.opf", table.concat(content_opf_parts))
    logger.dbg("Added OEBPS/content.opf")

    -- ----------------------------------------------------------------
    -- OEBPS/stylesheet.css
    --- @todo We told it we'd include a stylesheet.css, so it's probably best
    -- that we do. In theory, we could try to fetch any *.css files linked in
    -- the main html.
    epub:add("OEBPS/stylesheet.css", [[
/* Empty */
]])
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
    epub:add("OEBPS/toc.ncx", table.concat(toc_ncx_parts))
    logger.dbg("Added OEBPS/toc.ncx")

    -- ----------------------------------------------------------------
    -- OEBPS/content.html
    epub:add("OEBPS/content.html", html)
    logger.dbg("Added OEBPS/content.html")

    -- Force a GC to free the memory we used till now (the second call may
    -- help reclaim more memory).
    collectgarbage()
    collectgarbage()

    -- ----------------------------------------------------------------
    -- OEBPS/images/*
    if include_images then
        local nb_images = #images
        for inum, img in ipairs(images) do
            -- Process can be interrupted at this point between each image download
            -- by tapping while the InfoMessage is displayed
            -- We use the fast_refresh option from image #2 for a quicker download
            local go_on = UI:info(T(_("%1\n\nRetrieving image %2 / %3 …"), message, inum, nb_images), inum >= 2)
            if not go_on then
                logger.dbg("cancelled")
                cancelled = true
                break
            end
            local src = img.src
            if use_img_2x and img.src2x then
                src = img.src2x
            end
            logger.dbg("Getting img ", src)
            local success, content = getUrlContent(src, nil)
            -- success, content = getUrlContent(src..".unexistant") -- to simulate failure
            if success then
                logger.dbg("success, size:", #content)
            else
                logger.dbg("failed fetching:", src)
            end
            if success then
                -- Images do not need to be compressed, so spare some cpu cycles
                local no_compression = true
                if img.mimetype == "image/svg+xml" then -- except for SVG images (which are XML text)
                    no_compression = false
                end
                epub:add("OEBPS/"..img.imgpath, content, no_compression)
                logger.dbg("Adding OEBPS/"..img.imgpath)
            else
                go_on = UI:confirm(T(_("Downloading image %1 failed. Continue anyway?"), inum), _("Stop"), _("Continue"))
                if not go_on then
                    cancelled = true
                    break
                end
            end
        end
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
