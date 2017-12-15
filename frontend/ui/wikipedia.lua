local JSON = require("json")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

--[[
-- Query wikipedia using Wikimedia Web API.
-- https://en.wikipedia.org/w/api.php?format=jsonfm&action=query&generator=search&gsrnamespace=0&gsrsearch=ereader&gsrlimit=10&prop=extracts&exintro&explaintext&exlimit=max
-- https://en.wikipedia.org/w/api.php?action=query&prop=extracts&format=jsonfm&explaintext=&redirects=&titles=E-reader
--
-- To get parsed HTML :
-- https://en.wikipedia.org/w/api.php?action=parse&page=E-book
-- https://en.wikipedia.org/w/api.php?action=parse&page=E-book&prop=text|sections|displaytitle|revid&disablelimitreport=&disableeditsection
-- https://www.mediawiki.org/wiki/API:Parsing_wikitext#parse
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
   wiki_phtml_params = {
       action = "parse",
       format = "json",
       -- we only need the following informations
       prop = "text|sections|displaytitle|revid",
       -- page = nil, -- text to lookup, will be added below
       -- disabletoc = "", -- if we want to remove toc IN html
       disablelimitreport = "",
       disableeditsection = "",
   },
   -- allow for disabling prettifying full page text
   wiki_prettify = G_reader_settings:nilOrTrue("wikipedia_prettify"),
}

function Wikipedia:getWikiServer(lang)
    return string.format(self.wiki_server, lang or self.default_lang)
end

-- Possible values for page_type parameter to loadPage()
local WIKIPEDIA_INTRO = 1
local WIKIPEDIA_FULL = 2
local WIKIPEDIA_PHTML = 3

--[[
--  return decoded JSON table from Wikipedia
--]]
function Wikipedia:loadPage(text, lang, page_type, plain)
    local socket = require('socket')
    local url = require('socket.url')
    local http = require('socket.http')
    local https = require('ssl.https')
    local ltn12 = require('ltn12')

    local request, sink = {}, {}
    local query = ""

    local parsed = url.parse(self:getWikiServer(lang))
    parsed.path = self.wiki_path
    if page_type == WIKIPEDIA_INTRO then -- search query
        self.wiki_search_params.explaintext = plain and "" or nil
        for k,v in pairs(self.wiki_search_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "gsrsearch=" .. url.escape(text)
    elseif page_type == WIKIPEDIA_FULL then -- full page content
        self.wiki_params.explaintext = plain and "" or nil
        for k,v in pairs(self.wiki_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "titles=" .. url.escape(text)
    elseif page_type == WIKIPEDIA_PHTML then -- parsed html page content
        for k,v in pairs(self.wiki_phtml_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "page=" .. url.escape(text)
    else
        return
    end

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
        logger.warn("HTTP status not okay:", status)
        return
    end

    local content = table.concat(sink)
    if content ~= "" and string.sub(content, 1,1) == "{" then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            logger.dbg("wiki result", result)
            return result
        else
            logger.warn("wiki error:", result)
        end
    else
        logger.warn("not JSON from wiki response:", content)
    end
end

-- search wikipedia and get intros for results
function Wikipedia:wikintro(text, lang)
    local result = self:loadPage(text, lang, WIKIPEDIA_INTRO, true)
    if result then
        local query = result.query
        if query then
            return query.pages
        end
    end
end

-- get full content of a wiki page
function Wikipedia:wikifull(text, lang)
    local result = self:loadPage(text, lang, WIKIPEDIA_FULL, true)
    if result then
        local query = result.query
        if query then
            if self.wiki_prettify then
                -- Prettification of the plain text full page
                for pageid, page in pairs(query.pages) do
                    if page.extract then
                        page.extract = self:prettifyText(page.extract)
                    end
                end
            end
            return query.pages
        end
    end
end

-- get parsed html content and other infos of a wiki page
function Wikipedia:wikiphtml(text, lang)
    local result = self:loadPage(text, lang, WIKIPEDIA_PHTML, true)
    if result and result.parse then
        return result.parse
    end
    if result.error and result.error.info then
        error(result.error.info)
    end
end

-- UTF8 of unicode geometrical shapes we can use to replace
-- the "=== title ===" of wkipedia plaintext pages
-- These chosen ones are available in most fonts (prettier symbols
-- exist in unicode, but are available in a few fonts only) and
-- have a quite consistent size/weight in all fonts.
local th1_sym = "\xE2\x96\x88"         -- full block (big black rectangle) (never met, only for web page title?)
local th2_sym = "\xE2\x96\x89"         -- big black square
local th3_sym = "\xC2\xA0\xE2\x97\x86" -- black diamond (indented, nicer)
local th4_sym = "\xE2\x97\xA4"         -- black upper left triangle
local th5_sym = "\xE2\x9C\xBF"         -- black florette
local th6_sym = "\xE2\x9D\x96"         -- black diamond minus white x
-- Others available in most fonts
-- local thX_sym = "\xE2\x9C\x9A"         -- heavy greek cross
-- local thX_sym = "\xE2\x97\xA2"         -- black lower right triangle
-- local thX_sym = "\xE2\x97\x89"         -- fish eye
-- local thX_sym = "\xE2\x96\x97"         -- quadrant lower right

-- For optional prettification of the plain text full page
function Wikipedia:prettifyText(text)
    -- We use \a for an additional leading \n that we don't want shortened later
    text = text:gsub("\n= ",    "\n\a"..th1_sym.." ")  -- 2 empty lines before
    text = text:gsub("\n== ",   "\n\a"..th2_sym.." ")  -- 2 empty lines before
    text = text:gsub("\n=== ",    "\n"..th3_sym.." ")
    text = text:gsub("\n==== ",   "\n"..th4_sym.." ")
    text = text:gsub("\n===== ",  "\n"..th5_sym.." ")
    text = text:gsub("\n====== ", "\n"..th6_sym.." ")
    text = text:gsub("Modifier ==", " ==") -- fr wikipedia fix for some articles modified by clumsy editors
    text = text:gsub("==$", "==\n")        -- for a </hN> at end of text to be matched by next gsub
    text = text:gsub(" ===?\n+", "\n\n")   -- </h2> to </h3> : empty line after
    text = text:gsub(" ====+\n+", "\n")    -- </h4> to </hN> : single \n, no empty line
    text = text:gsub("\n\n+\xE2\x80\x94", "\n\xE2\x80\x94") -- em dash, used for quote author, make it stick to prev text
    text = text:gsub("\n +\n", "\n")  -- trim lines full of only spaces (often seen in math formulas)
    text = text:gsub("^\n*", "")      -- trim new lines at start
    text = text:gsub("\n*$", "")      -- trim new lines at end
    text = text:gsub("\n\n+", "\n\n") -- shorten multiple new lines
    text = text:gsub("\a", "\n")      -- re-add our wished \n
    return text
end


local function getUrlContent(url, timeout)
    local socket = require('socket')
    local ltn12 = require('ltn12')
    local requester
    if url:sub(1,7) == "http://" then
        requester = require('socket.http')
    elseif url:sub(1,8) == "https://" then
        requester = require('ssl.https')
    else
        return false, "Unsupported protocol"
    end
    requester.TIMEOUT = timeout or 10
    local request = {}
    local sink = {}
    request['url'] = url
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, requester.request(request))

    if headers == nil then
        logger.warn("No HTTP headers")
        return false, "Network unavailable"
    end
    if status ~= "HTTP/1.1 200 OK" then
        logger.warn("HTTP status not okay:", status)
        return false, "Network unavailable"
    end

    return true, table.concat(sink)
end

-- UTF8 of unicode geometrical shapes we'll prepend to wikipedia section headers,
-- to help identifying hierarchy (othewise, the small font size differences helps).
-- Best if identical to the ones used above for prettifying full plain text page.
-- These chosen ones are available in most fonts (prettier symbols
-- exist in unicode, but are available in a few fonts only) and
-- have a quite consistent size/weight in all fonts.
local h1_sym = "\xE2\x96\x88"     -- full block (big black rectangle) (never met, only for web page title?)
local h2_sym = "\xE2\x96\x89"     -- big black square
local h3_sym = "\xE2\x97\x86"     -- black diamond
local h4_sym = "\xE2\x97\xA4"     -- black upper left triangle
local h5_sym = "\xE2\x9C\xBF"     -- black florette
local h6_sym = "\xE2\x9D\x96"     -- black diamond minus white x
-- Other available ones in most fonts
-- local hXsym = "\xE2\x9C\x9A"     -- heavy greek cross
-- local hXsym = "\xE2\x97\xA2"     -- black lower right triangle
-- local hXsym = "\xE2\x97\x89"     -- fish eye
-- local hXsym = "\xE2\x96\x97"     -- quadrant lower right

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
function Wikipedia:createEpub(epub_path, page, lang, with_images)
    -- Use Trapper to display progress and ask questions through the UI.
    -- We need to have been Trapper.wrap()'ed for UI to be used, otherwise
    -- Trapper:info() and Trapper:confirm() will just use logger.
    local UI = require("ui/trapper")

    UI:info(_("Fetching Wikipedia page…"))
    local ok, phtml = pcall(self.wikiphtml, self, page, lang)
    if not ok then
        UI:info(phtml) -- display error in InfoMessage
        -- Sleep a bit to make that error seen
        util.sleep(2)
        UI:reset()
        return false
    end

    -- We may need to build absolute urls for non-absolute links and images urls
    local wiki_base_url = self:getWikiServer(lang)

    -- Get infos from wikipedia result
    -- (see example at https://en.wikipedia.org/w/api.php?action=parse&page=E-book&prop=text|sections|displaytitle|revid&disablelimitreport=&disableeditsection)
    local cancelled = false
    local html = phtml.text["*"] -- html content
    local page_cleaned = page:gsub("_", " ") -- page title
    local page_htmltitle = phtml.displaytitle -- page title with possible <sup> tags
    local sections = phtml.sections -- Wikipedia provided TOC
    local bookid = string.format("wikipedia_%s_%s_%s", lang, phtml.pageid, phtml.revid)
    -- Not sure if this bookid may ever be used by indexing software/calibre, but if it is,
    -- should it changes if content is updated (as now, including the wikipedia revisionId),
    -- or should it stays the same even if revid changes (content of the same book updated).

    -- We need to find images in HTML to tell how many when asking user if they should be included
    local images = {}
    local seen_images = {}
    local imagenum = 1
    local cover_imgid = "" -- best candidate for cover among our images
    local processImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            logger.info("no src found in ", img_tag)
            return nil
        end
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Wikipedia redirects from http to https, so use https
        elseif src:sub(1,1) == "/" then -- non absolute url
            src = wiki_base_url .. src
        end
        local cur_image
        if seen_images[src] then -- already seen
            cur_image = seen_images[src]
        else
            local ext = src:match(".*%.(%S+)")
            if ext == nil or ext == "" then -- we won't know what mimetype to use, ignore it
                logger.info("no file extension found in ", src)
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
                        src2x = wiki_base_url .. src2x
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
            if cover_imgid == "" and width and width > 50 and height and height > 50 and height > width then
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
    local include_images = false
    local use_img_2x = false
    if with_images then
        -- If no UI (Trapper:wrap() not called), UI:confirm() will answer true
        if #images > 0 then
            include_images = UI:confirm(T(_("The page contains %1 images.\nWould you like to download and include them in the generated EPUB file?"), #images), _("Don't include"), _("Include"))
            if include_images then
                use_img_2x = UI:confirm(_("Would you like to use slightly higher quality images? This will result in a bigger file size."), _("Standard quality"), _("Higher quality"))
            end
        else
            UI:info(_("The page does not contain any images."))
            util.sleep(1) -- Let the user see that
        end
    end
    if not include_images then
        -- Remove img tags to avoid little blank squares of missing images
        html = html:gsub("<%s*img [^>]*>", "")
        -- We could remove the whole image container <div class="thumb"...> ,
        -- but it's a lot of nested <div> and not easy to do.
        -- So the user will see the image legends and know a bit about
        -- the images he chose to not get.
    end

    UI:info(_("Building EPUB…"))
    -- Open the zip file (with .tmp for now, as crengine may still
    -- have a handle to the final epub_path, and we don't want to
    -- delete a good one if we fail/cancel later)
    local epub_path_tmp = epub_path .. ".tmp"
    local ZipWriter = require("ffi/zipwriter")
    local epub = ZipWriter:new{}
    if not epub:open(epub_path_tmp) then
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
    local koreader_version = "KOReader"
    if lfs.attributes("git-rev", "mode") == "file" then
        koreader_version = "KOReader "..io.open("git-rev", "r"):read()
    end
    local content_opf_parts = {}
    -- head
    table.insert(content_opf_parts, string.format([[
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        unique-identifier="bookid" version="2.0">
  <metadata>
    <dc:title>%s</dc:title>
    <dc:creator>Wikipedia %s</dc:creator>
    <dc:identifier id="bookid">%s</dc:identifier>
    <dc:language>%s</dc:language>
    <dc:publisher>%s</dc:publisher>
    <meta name="cover" content="%s"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
    <item id="css" href="stylesheet.css" media-type="text/css"/>
]], page_cleaned, lang:upper(), bookid, lang, koreader_version, cover_imgid))
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

    -- ----------------------------------------------------------------
    -- OEBPS/stylesheet.css
    -- crengine will use its own data/epub.css, we just add/fix a few styles
    -- to look more alike wikipedia web pages (that the user can ignore
    -- with "Embedded Style" off)
    epub:add("OEBPS/stylesheet.css", [[
/* make section headers looks left aligned and avoid some page breaks */
h1, h2 {
    text-align: left;
}
h3, h4, h5, h6, h7 {
    page-break-before: avoid;
    page-break-after: avoid;
    text-align: left;
}
/* avoid page breaks around our centered titles on first page */
h1.koreaderwikifrontpage, h5.koreaderwikifrontpage {
    page-break-before: avoid;
    page-break-inside: avoid;
    page-break-after: avoid;
    text-align: center;
    margin-top: 0em;
}
p.koreaderwikifrontpage {
    font-style: italic;
    font-size: 90%;
    margin-left: 2em;
    margin-right: 2em;
    margin-top: 1em;
    margin-bottom: 1em;
}
hr.koreaderwikifrontpage {
    margin-left: 20%;
    margin-right: 20%;
    margin-bottom: 1.2em;
}
/* So many links, make them look like normal text except for underline */
a {
    display:inline;
    text-decoration: underline;
    color: black;
    font-weight: normal;
}
/* No underline for links without their href that we removed */
a.newwikinonexistent {
    text-decoration: none;
}
/* show a box around image thumbnails */
div.thumb {
    width: 80%;
    border: dotted 1px black;
    margin-top: 0.5em;
    margin-bottom: 0.5em;
    margin-left: 2.5em;
    margin-right: 2.5em;
    padding-top: ]].. (include_images and "0.5em" or "0.15em") .. [[;
    padding-bottom: 0.2em;
    padding-left: 0.5em;
    padding-right: 0.5em;
    text-align: center;
    font-size: 90%;
}
/* don't waste left margin for notes and list of pages */
ul, ol {
    margin-left: 0em;
}
/* helps crengine to not display them as block elements */
time, abbr, sup {
    display: inline;
}
]])

    -- ----------------------------------------------------------------
    -- OEBPS/toc.ncx : table of content
    local toc_ncx_parts = {}
    local depth = 0
    local cur_level = 0
    local np_end = [[</navPoint>]]
    local num = 1
    -- Add our own first section for first page, with page name as title
    table.insert(toc_ncx_parts, string.format([[<navPoint id="navpoint-%s" playOrder="%s"><navLabel><text>%s</text></navLabel><content src="content.html"/>]], num, num, page_cleaned))
    table.insert(toc_ncx_parts, np_end)
    -- Wikipedia sections items seem to be already sorted by index, so no need to sort
    for isec, s in ipairs(sections) do
        num = num + 1
        local s_anchor = s.anchor
        local s_title = string.format("%s %s", s.number, s.line)
        s_title = (s_title:gsub("(%b<>)", "")) -- titles may include <i> and other html tags
        local s_level = s.toclevel
        if s_level > depth then
            depth = s_level -- max depth required in toc.ncx
        end
        if s_level == cur_level then
            table.insert(toc_ncx_parts, np_end) -- close same-level previous navPoint
        elseif s_level < cur_level then
            table.insert(toc_ncx_parts, np_end) -- close same-level previous navPoint
            while s_level < cur_level do -- close all in-between navPoint
                table.insert(toc_ncx_parts, np_end)
                cur_level = cur_level - 1
            end
        elseif s_level > cur_level + 1 then
            -- a jump from level N to level N+2 or more ... should not happen
            -- per epub spec, but we don't know about wikipedia...
            -- so we create missing intermediate navPoints with same anchor as current section
            while s_level > cur_level + 1 do
                table.insert(toc_ncx_parts, "\n"..(" "):rep(cur_level))
                table.insert(toc_ncx_parts, string.format([[<navPoint id="navpoint-%s" playOrder="%s"><navLabel><text>-</text></navLabel><content src="content.html#%s"/>]], num, num, s_anchor))
                cur_level = cur_level + 1
                num = num + 1
            end
        -- elseif s_level == cur_level + 1 then
        --     sublevel, nothing to close, nothing to add
        end
        cur_level = s_level
        table.insert(toc_ncx_parts, "\n"..(" "):rep(cur_level)) -- indentation, in case a person looks at it
        table.insert(toc_ncx_parts, string.format([[<navPoint id="navpoint-%s" playOrder="%s"><navLabel><text>%s</text></navLabel><content src="content.html#%s"/>]], num, num, s_title, s_anchor))
    end
    -- close nested <navPoint>
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
]], bookid, depth, page_cleaned))
    -- Append NCX tail
    table.insert(toc_ncx_parts, [[
  </navMap>
</ncx>
]])
    epub:add("OEBPS/toc.ncx", table.concat(toc_ncx_parts))

    -- ----------------------------------------------------------------
    -- OEBPS/content.html
    -- Some small fixes to Wikipedia HTML to make crengine and the user happier

    -- Most images are in a link to the image info page, which is a useless
    -- external link for us, so let's remove this link.
    html = html:gsub("<a[^>]*>%s*(<%s*img [^>]*>)%s*</a>", "%1")

    -- For some <div class="thumb tright"> , which include nested divs, although
    -- perfectly balanced, crengine seems to miss some closing </div> and we
    -- end up having our image bordered box including the remaining main wiki text.
    -- It looks like this code is supposed to deal with class= containing multiple
    -- class names :
    --   https://github.com/koreader/crengine/commit/0930ec7230e720c148fd6f231d69558832b4d53a
    -- and that it may stumble on some cases.
    -- It's all perfectly fine if we make all these div with a single class name
    --   html = html:gsub([[<div class="thumb [^"]*">]], [[<div class="thumb">]])
    --
    -- But we may as well make all class= have a single name to avoid other problems
    -- (no real risk with that, as we don't define any style for wikipedia class names,
    -- except div.thumb that always appears first).
    html = html:gsub([[(<[^>]* class="[^ "]+)%s+[^"]*"]], [[%1"]])

    -- crengine seems to consider unknown tag as 'block' elements, so we may
    -- want to remove or replace those that should be considered 'inline' elements
    html = html:gsub("</?time[^>]*>", "")

    -- Fix internal wikipedia links with full server url (including lang) so
    -- ReaderLink can notice them and deal with them with a LookupWikipedia event.
    --   html = html:gsub([[href="/wiki/]], [[href="]]..wiki_base_url..[[/wiki/]])
    --
    -- Also, crengine deals strangely with percent encoded utf8 :
    -- if the link in the html is : <a href="http://fr.wikipedia.org/wiki/Fran%C3%A7oix">
    -- we get from credocument:getLinkFromPosition() : http://fr.wikipedia.org/wiki/Fran____oix
    -- These are bytes "\xc3\x83\xc2\xa7", that is U+C3 and U+A7 encoded as UTF8,
    -- when we should have get "\xc3\xa7" ...
    -- We can avoid that by putting in the url plain unencoded UTF8
    local hex_to_char = function(x) return string.char(tonumber(x, 16)) end
    local fixEncodedWikiPageTitle = function(wiki_page)
        wiki_page = wiki_page:gsub("%%(%x%x)", hex_to_char)
        return string.format([[href="%s/wiki/%s"]], wiki_base_url, wiki_page)
    end
    html = html:gsub([[href="/wiki/([^"]*)"]], fixEncodedWikiPageTitle)

    -- Remove href from links to non existant wiki page so they are not clickable :
    -- <a href="/w/index.php?title=PageTitle&amp;action=edit&amp;redlink=1" class="new" title="PageTitle">PageTitle____on</a>
    -- (removal of the href="" will make them non clickable)
    html = html:gsub([[<a[^>]* class="new"[^>]*>]], [[<a class="newwikinonexistent">]])

    -- Fix some other protocol-less links to wikipedia (href="//fr.wikipedia.org/w/index.php..)
    html = html:gsub([[href="//]], [[href="https://]])

    -- crengine does not return link if multiple class names in <a> (<a class="external text" href="">)
    -- it would be no problem as we can't follow them, but when the user tap
    -- on it, the tap is propagated to other widgets and page change happen...
    --   html = html:gsub([[<a rel="nofollow" class="external text"]], [[<a rel="nofollow" class="externaltext"]])
    --   html = html:gsub([[<a class="external text"]], [[<a class="externaltext"]])
    -- Solved by our multiple class names suppression above

    -- Avoid link being clickable before <a> (if it starts a line) or after </a> (if it
    -- ends a line or a block) by wrapping it with U+200B ZERO WIDTH SPACE which will
    -- make the DOM tree walking code to find a link stop at it.
    --   html = html:gsub("(<[aA])", "\xE2\x80\x8B%1")
    --   html = html:gsub("(</[aA]>)", "%1\xE2\x80\x8B")
    -- Fixed in crengine lvtinydom.

    if self.wiki_prettify then
        -- Prepend some symbols to section titles for a better visual feeling of hierarchy
        html = html:gsub("<h1>", "<h1> "..h1_sym.." ")
        html = html:gsub("<h2>", "<h2> "..h2_sym.." ")
        html = html:gsub("<h3>", "<h3> "..h3_sym.." ")
        html = html:gsub("<h4>", "<h4> "..h4_sym.." ")
        html = html:gsub("<h5>", "<h5> "..h5_sym.." ")
        html = html:gsub("<h6>", "<h6> "..h6_sym.." ")
    end

    -- Note: in all the gsub patterns above, we used lowercase for tags and attributes
    -- because it's how they are in wikipedia HTML and it makes the pattern simple.
    -- If one day this changes, they'll have to be replaced with href => [Hh][Rr][Ee][Ff] ...

    -- We can finally build the final HTML with some header of our own
    local saved_on = T(_("Saved on %1"), os.date("%b %d, %Y %H:%M:%S"))
    local online_version_htmllink = string.format([[<a href="%s/wiki/%s">%s</a>]], wiki_base_url, page:gsub(" ", "_"), _("online version"))
    local see_online_version = T(_("See %1 for up-to-date content"), online_version_htmllink)
    epub:add("OEBPS/content.html", string.format([[
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>%s</title>
  <link type="text/css" rel="stylesheet" href="stylesheet.css"/>
</head>
<body>
<h1 class="koreaderwikifrontpage">%s</h1>
<h5 class="koreaderwikifrontpage">Wikipedia %s</h5>
<p class="koreaderwikifrontpage">%s<br/>%s</p>
<hr class="koreaderwikifrontpage"/>
%s
</body>
</html>
]], page_cleaned, page_htmltitle, lang:upper(), saved_on, see_online_version, html))

    -- ----------------------------------------------------------------
    -- OEBPS/images/*
    if include_images then
        local nb_images = #images
        for inum, img in ipairs(images) do
            -- Process can be interrupted at this point between each image download
            -- by tapping while the InfoMessage is displayed
            local go_on = UI:info(T(_("Fetching image %1 / %2 …"), inum, nb_images))
            if not go_on then
                cancelled = true
                break
            end
            local src = img.src
            if use_img_2x and img.src2x then
                src = img.src2x
            end
            logger.dbg("Getting img ", src)
            local success, content = getUrlContent(src)
            -- success, content = getUrlContent(src..".unexistant") -- to simulate failure
            if success then
                logger.dbg("success, size:", #content)
            else
                logger.info("failed fetching:", src)
            end
            if success then
                epub:add("OEBPS/"..img.imgpath, content)
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
        UI:info(_("Packing EPUB…"))
    end
    epub:close()
    -- This was nearly a no-op, so sleep a bit to make that progress step seen
    util.usleep(300000)
    UI:reset() -- close last InfoMessage

    if cancelled then
        -- Build was cancelled, remove half created .epub
        if lfs.attributes(epub_path_tmp, "mode") == "file" then
            os.remove(epub_path_tmp)
        end
        return false
    end

    -- Finally move the .tmp to the final file
    os.rename(epub_path_tmp, epub_path)
    logger.info("successfully created:", epub_path)
    return true
end


-- Wrap Wikipedia:createEpub() with UI progress info, provided
-- by Trapper module.
function Wikipedia:createEpubWithUI(epub_path, page, lang, result_callback)
    -- To do any UI interaction while building the EPUB, we need
    -- to use a coroutine, so that our code can be suspended while waiting
    -- for user interaction, and resumed by UI widgets callbacks.
    -- All this is hidden and done by Trapper with a simple API.
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        Trapper:setPausedText("Download paused")
        -- If errors in Wikipedia:createEpub(), the coroutine (used by
        -- Trapper) would just abort (no reader crash, no error logged).
        -- So we use pcall to catch any errors, log it, and report
        -- the failure via result_callback.
        local ok, success = pcall(self.createEpub, self, epub_path, page, lang, true)
        if ok and success then
            result_callback(true)
        else
            Trapper:reset() -- close any last widget not cleaned if error
            logger.warn("Wikipedia.createEpub pcall:", ok, success)
            result_callback(false)
        end
    end)
end

return Wikipedia
