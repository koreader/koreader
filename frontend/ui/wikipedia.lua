local JSON = require("json")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

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
   default_lang = "en",
   -- See https://www.mediawiki.org/wiki/API:Main_page for details.
   -- Search query, returns introductory texts (+ main thumbnail image)
   wiki_search_params = {
       action = "query",
       generator = "search",
       gsrnamespace = "0",
       -- gsrsearch = nil, -- text to lookup, will be added below
       gsrlimit = 30, -- max nb of results to get
       exlimit = "max",
       prop = "extracts|info|pageimages", -- 'extracts' to get text, 'info' to get full page length
       format = "json",
       explaintext = "",
       exintro = "",
       -- We have to use 'exintro=' to get extracts for ALL results
       -- (otherwise, we get the full text for only the first result, and
       -- no text at all for the others
   },
   -- Full article, parsed to output text (+ main thumbnail image)
   wiki_full_params = {
       action = "query",
       prop = "extracts|pageimages",
       format = "json",
       -- exintro = nil, -- get more than only the intro
       explaintext = "",
       redirects = "",
       -- title = nil, -- text to lookup, will be added below
   },
   -- Full article, parsed to output HTML, for Save as EPUB
   wiki_phtml_params = {
       action = "parse",
       format = "json",
       -- we only need the following pieces of information
       prop = "text|sections|displaytitle|revid",
       -- page = nil, -- text to lookup, will be added below
       -- disabletoc = "", -- if we want to remove toc IN html
            -- 20230722: there is no longer the TOC in the html no matter this param
       disablelimitreport = "",
       disableeditsection = "",
   },
   -- Full article, parsed to output HTML, for images extraction
   -- (used with full article as text, if "show more images" enabled)
   wiki_images_params = { -- same as previous one, with just text html
       action = "parse",
       format = "json",
       -- we only need the following pieces of information
       prop = "text",
       -- page = nil, -- text to lookup, will be added below
       redirects = "",
       disabletoc = "", -- remove toc in html
       disablelimitreport = "",
       disableeditsection = "",
   },
   -- There is an alternative for obtaining page's images:
   -- prop=imageinfo&action=query&iiprop=url|dimensions|mime|extmetadata&generator=images&pageids=49448&iiurlwidth=100&iiextmetadatafilter=ImageDescription
   -- but it gives all images (including wikipedia icons) in any order, without
   -- any score or information that would help considering if they matter or not
   --

   -- Allow for disabling prettifying full page text
   wiki_prettify = G_reader_settings:nilOrTrue("wikipedia_prettify"),

   -- Can be set so HTTP requests will be done under Trapper and
   -- be interruptible
   trap_widget = nil,
   -- For actions done with Trapper:dismissable methods, we may throw
   -- and error() with this code. We make the value of this error
   -- accessible here so that caller can know it's a user dismiss.
   dismissed_error_code = "Interrupted by user",
}

function Wikipedia:getWikiServer(lang)
    return string.format(self.wiki_server, lang or self.default_lang)
end

-- Get URL content
local function getUrlContent(url, timeout, maxtime)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local socket_url = require("socket.url")

    local parsed = socket_url.parse(url)
    if parsed.scheme ~= "http" and parsed.scheme ~= "https" then
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 10 end

    local sink = {}
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
    }

    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local content = table.concat(sink) -- empty or content accumulated till now
    -- logger.dbg("code:", code)
    -- logger.dbg("headers:", headers)
    -- logger.dbg("status:", status)
    -- logger.dbg("#content:", #content)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", code)
        return false, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", status or code or "network unreachable")
        return false, "Network or remote server unavailable"
    end
    if not code or code < 200 or code > 299 then -- all 200..299 HTTP codes are OK
        logger.warn("HTTP status not okay:", status or code or "network unreachable")
        logger.dbg("Response headers:", headers)
        return false, "Remote server error or unavailable"
    end
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, "Incomplete content received"
        end
    end
    return true, content
end

function Wikipedia:setTrapWidget(trap_widget)
    self.trap_widget = trap_widget
end

function Wikipedia:resetTrapWidget()
    self.trap_widget = nil
end

-- Possible values for page_type parameter to loadPage()
local WIKIPEDIA_INTRO = 1
local WIKIPEDIA_FULL = 2
local WIKIPEDIA_PHTML = 3
local WIKIPEDIA_IMAGES = 4

--[[
--  return decoded JSON table from Wikipedia
--]]
function Wikipedia:loadPage(text, lang, page_type, plain)
    local url = require("socket.url")
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
        self.wiki_full_params.explaintext = plain and "" or nil
        for k,v in pairs(self.wiki_full_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "titles=" .. url.escape(text)
    elseif page_type == WIKIPEDIA_PHTML then -- parsed html page content
        for k,v in pairs(self.wiki_phtml_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "page=" .. url.escape(text)
    elseif page_type == WIKIPEDIA_IMAGES then -- images found in page html
        for k,v in pairs(self.wiki_images_params) do
            query = string.format("%s%s=%s&", query, k, v)
        end
        parsed.query = query .. "page=" .. url.escape(text)
    else
        return
    end

    local built_url = url.build(parsed)
    local completed, success, content
    if self.trap_widget then -- if previously set with Wikipedia:setTrapWidget()
        local Trapper = require("ui/trapper")
        local timeout, maxtime = 30, 60
        -- We use dismissableRunInSubprocess with complex return values:
        completed, success, content = Trapper:dismissableRunInSubprocess(function()
            return getUrlContent(built_url, timeout, maxtime)
        end, self.trap_widget)
        if not completed then
            error(self.dismissed_error_code) -- "Interrupted by user"
        end
    else
        -- Smaller timeout than when we have a trap_widget because we are
        -- blocking without one (but 20s may be needed to fetch the main HTML
        -- page of big articles when making an EPUB).
        local timeout, maxtime = 20, 60
        success, content = getUrlContent(built_url, timeout, maxtime)
    end
    if not success then
        error(content)
    end

    if content ~= "" and string.sub(content, 1, 1) == "{" then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            logger.dbg("wiki result json:", result)
            return result
        else
            logger.warn("wiki result json decoding error:", result)
            error("Failed decoding JSON")
        end
    else
        logger.warn("wiki response is not json:", content)
        error("Response is not JSON")
    end
end

-- search wikipedia and get intros for results
function Wikipedia:searchAndGetIntros(text, lang)
    local result = self:loadPage(text, lang, WIKIPEDIA_INTRO, true)
    if result then
        local query = result.query
        if query then
            local show_image = G_reader_settings:nilOrTrue("wikipedia_show_image")
            -- Scale wikipedia normalized (we hope) thumbnail by 2 (adjusted
            -- to screen size/dpi) for intros (and x8 more for highres image)
            local image_size_factor = Screen:scaleBySize(200)/100.0
            if show_image then
                for pageid, page in pairs(query.pages) do
                    self:addImages(page, lang, false, image_size_factor, 8)
                end
            end
            return query.pages
        end
    end
end

-- get full content of a wiki page
function Wikipedia:getFullPage(wiki_title, lang)
    local result = self:loadPage(wiki_title, lang, WIKIPEDIA_FULL, true)
    if result then
        local query = result.query
        if query then
            local show_image = G_reader_settings:nilOrTrue("wikipedia_show_image")
            local show_more_images = G_reader_settings:nilOrTrue("wikipedia_show_more_images")
            -- Scale wikipedia normalized (we hope) thumbnails by 4 (adjusted
            -- to screen size/dpi) for full page (and this *4 for highres image)
            local image_size_factor = Screen:scaleBySize(400)/100.0
            if self.wiki_prettify or show_image then
                for pageid, page in pairs(query.pages) do
                    if self.wiki_prettify and page.extract then
                        -- Prettification of the plain text full page
                        page.extract = self:prettifyText(page.extract)
                    end
                    if show_image then
                        self:addImages(page, lang, show_more_images, image_size_factor, 4)
                    end
                end
            end
            return query.pages
        end
    end
end

-- get parsed html content and other infos of a wiki page
function Wikipedia:getFullPageHtml(wiki_title, lang)
    local result = self:loadPage(wiki_title, lang, WIKIPEDIA_PHTML, true)
    if result and result.parse then
        return result.parse
    end
    if result.error and result.error.info then
        error(result.error.info)
    end
end

-- get images extracted from parsed html
function Wikipedia:getFullPageImages(wiki_title, lang)
    local images = {} -- will be returned, each in a format similar to page.thumbnail
    local result = self:loadPage(wiki_title, lang, WIKIPEDIA_IMAGES, true)
    if result and result.parse and result.parse.text and result.parse.text["*"] then
        local html = result.parse.text["*"] -- html content
        local url = require('socket.url')
        local wiki_base_url = self:getWikiServer(lang)

        local thumbs = {} -- bits of HTML containing an image
        -- We first try to catch images in <figure>, which should exclude
        -- wikipedia icons, flags...
        -- (We want to match both typeof="mw:File/Thumb" and typeof="mw:File/Frame", so this [TF][hr][ua]m[be]...
        for thtml in html:gmatch([[<figure [^>]*typeof="mw:File/[TF][hr][ua]m[be]"[^>]*>.-</figure>]]) do
            table.insert(thumbs, thtml)
        end
        -- We then also try to catch images in galleries (which often are less
        -- interesting than those in thumbinner) as a 2nd set.
        for thtml in html:gmatch([[<li class="gallerybox".-<div class="thumb".-</div>%s*<div class="gallerytext">.-</div>]]) do
            table.insert(thumbs, thtml)
        end
        -- We may miss some interesting images in the page's top right table, but
        -- there's no easy way to distinguish them from icons/flags in this table...

        for _, thtml in ipairs(thumbs) do
            -- We get <a href="/wiki/File:real_file_name.jpg (or /wiki/Fichier:real_file_name.jpg
            -- depending on Wikipedia lang)
            local filename = thtml:match([[<a href="/wiki/[^:]*:([^"]*)" class="mw.file.description"]])
            if filename then
                filename = url.unescape(filename)
            end
            logger.dbg("found image with filename:", filename)
            -- logger.dbg(thtml)
            local timg, tremain = thtml:match([[(<img .->)(.*)]])
            if timg and tremain then
                -- (Should we discard those without caption ?)
                local caption = tremain and util.htmlToPlainText(tremain)
                if caption == "" then caption = nil end
                logger.dbg("  caption:", caption)
                -- logger.dbg(timg)
                local src = timg:match([[src="([^"]*)"]])
                if src and src ~= "" then
                    if src:sub(1,2) == "//" then
                        src = "https:" .. src
                    elseif src:sub(1,1) == "/" then -- non absolute url
                        src = wiki_base_url .. src
                    end
                    local width = tonumber(timg:match([[width="([^"]*)"]]))
                    local height = tonumber(timg:match([[height="([^"]*)"]]))
                    -- Ignore img without width and height, which should exclude
                    -- javascript maps and other unsupported stuff
                    if width and height then
                        -- Images in the html we got seem to be x4.5 the size of
                        -- the thumbnail we get with searchAndGetIntros() or
                        -- getFullPage(). Normalize them to the size of the thumbnail,
                        -- so we can resize them all later with the same rules.
                        width = math.ceil(width/4.5)
                        height = math.ceil(height/4.5)
                        -- No need to adjust width in src url here, as it will be
                        -- done in addImages() anyway
                        -- src = src:gsub("(.*/)%d+(px-[^/]*)", "%1"..width.."%2")
                        logger.dbg("  size:", width, "x", height, "url:", src)
                        table.insert(images, {
                            source = src,
                            width = width,
                            height = height,
                            filename = filename,
                            caption = caption,
                        })
                    end
                end
            end
        end
    end
    return images
end

-- Function wrapped and plugged to image objects returned by :addImages()
local function image_load_bb_func(image, highres)
    local source, trap_widget
    if not highres then
        -- We use an invisible widget that will resend the dismiss event,
        -- so that image loading in TextBoxWdiget is unobtrusive and
        -- interruptible
        trap_widget = nil
        source = image.source
    else
        -- We need to let the user know image loading is happening,
        -- with a discreet TrapWidget
        trap_widget = _("Loading high-res image… (tap to cancel)")
        source = image.hi_source
    end
    -- Image may be big or take some time to be resized on wikipedia servers.
    -- As we use dismissableRunInSubprocess and can interrupt this loading,
    -- we can use quite high timeouts
    local timeout, maxtime = 60, 120

    logger.dbg("fetching", source)
    local Trapper = require("ui/trapper")
    -- We use dismissableRunInSubprocess with simple string return value to
    -- avoid serialization/deserialization of a long string of image bytes
    local completed, data = Trapper:dismissableRunInSubprocess(function()
        local success, data = getUrlContent(source, timeout, maxtime)
        -- With simple string value, we're not able to return the failure
        -- reason, so log it here
        if not success then
            logger.warn("failed fetching image from", source, ":", data)
        end
        return success and data or nil
    end, trap_widget, true) -- task_returns_simple_string=true

    local success = data and true or false -- guess success from data

    if not completed then
        logger.dbg("image fetching interrupted by user")
        return true -- let caller know it was interrupted
    end
    if not success then
        -- log it again (on Android, log from sub-process seem to not work)
        logger.warn("failed fetching image from", source)
        return
    end
    logger.dbg(" fetched", #data)

    local bb
    if not highres then
        -- For low-res, we should ensure the image we got from wikipedia is
        -- the right size, so it does not overflow our reserved area
        -- (TextBoxWidget may have adjusted image.width and height)
        -- We don't get animated GIF multiple frames to keep TextBoxWidget
        -- simple: they will be available when viewed in highres
        bb = RenderImage:renderImageData(data, #data, false, image.width, image.height)
    else
        -- We provide want_frames=true for highres images, so ImageViewer
        -- can display animated GIF
        -- No need for width and height for high-res
        bb = RenderImage:renderImageData(data, #data, true)
    end
    if not bb then
        logger.warn("failed building image from", source)
        return
    end
    if not highres then
        image.bb = bb
    else
        image.hi_bb = bb
    end
end

function Wikipedia:addImages(page, lang, more_images, image_size_factor, hi_image_size_factor)
    -- List of images, table with keys as expected by TextBoxWidget
    page.images = {}
    -- List of wikipedia images data structures (page.thumbnail and images
    -- extracted from html) made to have the same keys for common processing
    local wimages = {}

    -- We got what Wikipedia scored as the most interesting image for this
    -- page in page.thumbnail, and its filename in page.pageimage, ie:
    --  "thumbnail": {
    --    "source": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Reading_on_the_bus_train_or_transit.jpg/37px-Reading_on_the_bus_train_or_transit.jpg",
    --    "width": 37,
    --    "height": 50
    --  },
    --  "pageimage": "Reading_on_the_bus_train_or_transit.jpg"
    --
    local first_image_filename = nil
    if page.thumbnail and page.thumbnail.source then
        page.thumbnail.filename = page.pageimage
        first_image_filename = page.pageimage
        table.insert(wimages, page.thumbnail)
    end
    -- To get more images, we need to make a second request to wikipedia
    if more_images then
        local ok, images_or_err = pcall(Wikipedia.getFullPageImages, Wikipedia, page.title, lang)
        if not ok then
            logger.warn("error getting more images", images_or_err)
        else
            for _, wimage in ipairs(images_or_err) do
                if first_image_filename and wimage.filename == first_image_filename then
                    -- We got the same image as the thumbnail one, but it may have
                    -- a caption: replace thumbnail one with this one
                    table.remove(wimages, 1)
                    table.insert(wimages, 1, wimage)
                else
                    table.insert(wimages, wimage)
                end
            end
        end
    end

    -- All our wimages now have the keys: source, width, height, filename, caption
    for _, wimage in ipairs(wimages) do
        -- We trust wikipedia, and our x4.5 factor in :getFullPageImages(), for adequate
        -- and homogeneous images' sizes. We'll just scale them according to the
        -- provided 'image_size_factor' (which should account for screen size/DPI)
        local width = wimage.width or 100 -- in case we don't get any width or height
        local height = wimage.height or 100
        -- Give a little boost in size to thin images
        if width < height / 2 or height < width / 2 then
            width = math.floor(width * 1.3)
            height = math.floor(height * 1.3)
        end
        width = math.ceil(width * image_size_factor)
        height = math.ceil(height * image_size_factor)
        -- All wikipedia image urls like .../wikipedia/commons/A/BC/<filename>
        -- or .../wikipedia/commons/thumb/A/BC/<filename>/<width>px-<filename>
        -- can be transformed to another url with a requested new_width with the form:
        --   /wikipedia/commons/thumb/A/BC/<filename>/<new_width>px-<filename>
        -- (Additionally, the image format can be changed by appending .png,
        -- .jpg or .gif to it)
        -- The resize is so done on Wikipedia servers from the source image for
        -- the best quality.
        local source = wimage.source:gsub("(.*/)%d+(px-[^/]*)", "%1"..width.."%2")
        -- We build values for a high resolution version of the image, to be displayed
        -- with ImageViewer (x 4 by default)
        local hi_width = width * (hi_image_size_factor or 4)
        local hi_height = height * (hi_image_size_factor or 4)
        local hi_source = wimage.source:gsub("(.*/)%d+(px-[^/]*)", "%1"..hi_width.."%2")
        local title = wimage.filename
        if title then
            title = title:gsub("_", " ")
        end
        local image = {
            -- As expected by TextBoxWidget (with additional source and
            -- hi_source, that will be used by load_bb_func)
            title = title,
            caption = wimage.caption,
            source = source,
            width = width,
            height = height,
            bb = nil, -- will be loaded and build only if needed
            hi_source = hi_source,
            hi_width = hi_width,
            hi_height = hi_height,
            hi_bb = nil, -- will be loaded and build only if needed
        }
        -- If bb or hi_bb is nil, TextBoxWidget will call a method named "load_bb_func"
        image.load_bb_func = function(highres)
            return image_load_bb_func(image, highres)
        end
        table.insert(page.images, image)
    end
end

-- UTF8 of unicode geometrical shapes we can use to replace
-- the "=== title ===" of wkipedia plaintext pages
-- These chosen ones are available in most fonts (prettier symbols
-- exist in unicode, but are available in a few fonts only) and
-- have a quite consistent size/weight in all fonts.
local th1_sym = "\u{2588}"         -- full block (big black rectangle) (never met, only for web page title?)
local th2_sym = "\u{2589}"         -- big black square
local th3_sym = "\u{00A0}\u{25E4}" -- black upper left triangle (indented, nicer)
local th4_sym = "\u{25C6}"         -- black diamond
local th5_sym = "\u{273F}"         -- black florette
local th6_sym = "\u{2756}"         -- black diamond minus white x
-- Others available in most fonts
-- local thX_sym = "\u{271A}"         -- heavy greek cross
-- local thX_sym = "\u{25E2}"         -- black lower right triangle
-- local thX_sym = "\u{25C9}"         -- fish eye
-- local thX_sym = "\u{2597}"         -- quadrant lower right

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
    text = text:gsub("\n\n+\u{2014}", "\n\u{2014}") -- em dash, used for quote author, make it stick to prev text
    text = text:gsub("\n +\n", "\n")  -- trim lines full of only spaces (often seen in math formulas)
    text = text:gsub("^\n*", "")      -- trim new lines at start
    text = text:gsub("\n*$", "")      -- trim new lines at end
    text = text:gsub("\n\n+", "\n\n") -- shorten multiple new lines
    text = text:gsub("\a", "\n")      -- re-add our wished \n
    return text
end


-- UTF8 of unicode geometrical shapes we'll prepend to wikipedia section headers,
-- to help identifying hierarchy (otherwise, the small font size differences helps).
-- Best if identical to the ones used above for prettifying full plain text page.
-- These chosen ones are available in most fonts (prettier symbols
-- exist in unicode, but are available in a few fonts only) and
-- have a quite consistent size/weight in all fonts.
local h1_sym = "\u{2588}"     -- full block (big black rectangle) (never met, only for web page title?)
local h2_sym = "\u{2589}"     -- big black square
local h3_sym = "\u{25E4}"     -- black upper left triangle
local h4_sym = "\u{25C6}"     -- black diamond
local h5_sym = "\u{273F}"     -- black florette
local h6_sym = "\u{2756}"     -- black diamond minus white x
-- Other available ones in most fonts
-- local hXsym = "\u{271A}"     -- heavy greek cross
-- local hXsym = "\u{25E2}"     -- black lower right triangle
-- local hXsym = "\u{25C9}"     -- fish eye
-- local hXsym = "\u{2597}"     -- quadrant lower right

local ext_to_mimetype = {
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    webp = "image/webp",
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

-- Display from these Wikipedia should be RTL
-- The API looks like it does not give any info about the LTR/RTL
-- direction of the content it returns...
-- (list made by quickly and manually checking links from:
-- https://meta.wikimedia.org/wiki/List_of_Wikipedias )
local rtl_wiki_code = {
    fa  = "Persian",
    ar  = "Arabic",
    he  = "Hebrew",
    ur  = "Urdu",
    azb = "South Azerbaijani",
    pnb = "Western Punjabi",
    ckb = "Sorani",
    arz = "Egyptian Arabic",
    yi  = "Yiddish",
    sd  = "Sindhi",
    mzn = "Mazandarani",
    ps  = "Pashto",
    glk = "Gilaki",
    lrc = "Northern Luri",
    ug  = "Uyghur",
    dv  = "Divehi",
    arc = "Aramaic",
    ks  = "Kashmiri",
}

function Wikipedia:isWikipediaLanguageRTL(lang)
    if lang and rtl_wiki_code[lang:lower()] then
        return true
    end
    return false
end

-- Create an epub file (with possibly images)
function Wikipedia:createEpub(epub_path, page, lang, with_images)
    -- Use Trapper to display progress and ask questions through the UI.
    -- We need to have been Trapper.wrap()'ed for UI to be used, otherwise
    -- Trapper:info() and Trapper:confirm() will just use logger.
    local UI = require("ui/trapper")

    UI:info(_("Retrieving Wikipedia article…"))
    local ok, phtml = pcall(self.getFullPageHtml, self, page, lang)
    if not ok then
        UI:info(phtml) -- display error in InfoMessage
        -- Sleep a bit to make that error seen
        ffiutil.sleep(2)
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
    -- We need to encode plain '&' in those so we can put them in XML/HTML
    -- We wouldn't need to escape as many as util.htmlEntitiesToUtf8() does, but
    -- we need to to not mess existing ones ('&nbsp;' may happen) with our '&'
    -- encodes. (We don't escape < or > as these JSON strings may contain HTML tags)
    page_cleaned = util.htmlEntitiesToUtf8(page_cleaned):gsub("&", "&#38;")
    page_htmltitle = util.htmlEntitiesToUtf8(page_htmltitle):gsub("&", "&#38;")
    local sections = phtml.sections -- Wikipedia provided TOC
    local bookid = string.format("wikipedia_%s_%s_%s", lang, phtml.pageid, phtml.revid)
    -- Not sure if this bookid may ever be used by indexing software/calibre, but if it is,
    -- should it changes if content is updated (as now, including the wikipedia revisionId),
    -- or should it stays the same even if revid changes (content of the same book updated).

    -- We need to find images in HTML to tell how many when asking user if they should be included
    local images = {}
    local seen_images = {}
    local imagenum = 1
    local cover_imgid = nil -- best candidate for cover among our images
    local processImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            logger.info("no src found in ", img_tag)
            return nil
        end
        if src:sub(1,5) == "data:" then
            logger.dbg("skipping data URI", src)
            return nil
        end
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Wikipedia redirects from http to https, so use https
        elseif src:sub(1,1) == "/" then -- non absolute url
            src = wiki_base_url .. src
        end
        -- Some SVG urls don't have any extension, like:
        -- "/api/rest_v1/media/math/render/svg/154a342afea5a9f13caf1a5bb6acd5c4e69733b6""
        -- Furthermore, as of early 2018, it looks like most (all?) mathematical SVG
        -- obtained from such urls use features not supported by crengine's nanosvg
        -- renderer (so, they are displayed as a blank square).
        -- But we can get a PNG version of it thanks to wikipedia APIs :
        --   https://wikimedia.org/api/rest_v1/#!/Math/get_media_math_render_format_hash
        -- We tweak the url now (and fix the mimetype below), before checking for
        -- duplicates in seen_images.
        -- As of mid 2022, crengine has switched from using NanoSVG to LunaSVG extended,
        -- which makes it able to render such Wikipedia SVGs correctly.
        -- We need to keep the style= attribute, which usually specifies width and height
        -- in 'ex' units, and a vertical-align we want to keep to align baselines.
        local keep_style
        if src:find("/math/render/svg/") then
            -- src = src:gsub("/math/render/svg/", "/math/render/png/") -- no longer needed
            keep_style = true
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
                if src_ext:find("/math/render/svg/") then
                    ext = "svg"
                elseif src_ext:find("/math/render/png/") then
                    ext = "png"
                else
                    -- we won't know what mimetype to use, ignore it
                    logger.info("no file extension found in ", src)
                    return nil
                end
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
            if not cover_imgid and width and width > 50 and height and height > 50 and height > width then
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
        if keep_style then -- for /math/render/svg/
            style = img_tag:match([[style="([^"]*)"]])
        end
        return string.format([[<img src="%s" style="%s" alt=""/>]], cur_image.imgpath, style)
    end
    html = html:gsub("(<%s*img [^>]*>)", processImg)
    logger.dbg("Images found in html:", images)

    -- See what to do with images
    local include_images = G_reader_settings:readSetting("wikipedia_epub_include_images")
    local use_img_2x = G_reader_settings:readSetting("wikipedia_epub_highres_images")
    if with_images then
        -- If no UI (Trapper:wrap() not called), UI:confirm() will answer true
        if #images > 0 then
            if include_images == nil then
                include_images = UI:confirm(T(_("This article contains %1 images.\nWould you like to download and include them in the generated EPUB file?"), #images), _("Don't include"), _("Include"))
            end
            if include_images then
                if use_img_2x == nil then
                    use_img_2x = UI:confirm(_("Would you like to use slightly higher quality images? This will result in a bigger file size."), _("Standard quality"), _("Higher quality"))
                end
            end
        else
            UI:info(_("This article does not contain any images."))
            ffiutil.sleep(1) -- Let the user see that
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
    local Archiver = require("ffi/archiver")
    local epub = Archiver.Writer:new{}
    local epub_path_tmp = epub_path .. ".tmp"
    if not epub:open(epub_path_tmp, "epub") then
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
        local Version = require("version")
        koreader_version = "KOReader " .. Version:getCurrentRevision()
    end
    local content_opf_parts = {}
    -- head
    local meta_cover = "<!-- no cover image -->"
    if include_images and cover_imgid then
        meta_cover = string.format([[<meta name="cover" content="%s"/>]], cover_imgid)
    end
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
    %s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
    <item id="css" href="stylesheet.css" media-type="text/css"/>
]], page_cleaned, lang:upper(), bookid, lang, koreader_version, meta_cover))
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

    -- ----------------------------------------------------------------
    -- OEBPS/stylesheet.css
    -- crengine will use its own data/epub.css, we just add/fix a few styles
    -- to look more alike wikipedia web pages (that the user can ignore
    -- with "Embedded Style" off)
    epub:addFileFromMemory("OEBPS/stylesheet.css", [[
/* Generic styling picked from our epub.css (see it for comments),
   to give this epub a book look even if used with html5.css */
body {
  text-align: justify;
}
h1, h2, h3, h4, h5, h6 {
  margin-top: 0.7em;
  margin-bottom: 0.5em;
  hyphens: none;
}
h1 { font-size: 150%; }
h2 { font-size: 140%; }
h3 { font-size: 130%; }
h4 { font-size: 120%; }
h5 { font-size: 110%; }
h6 { font-size: 100%; }
p {
  text-indent: 1.2em;
  margin-top: 0;
  margin-bottom: 0;
}
blockquote {
  margin-top: 0.5em;
  margin-bottom: 0.5em;
  margin-left: 2em;
  margin-right: 1em;
}
blockquote:dir(rtl) {
  margin-left: 1em;
  margin-right: 2em;
}
dl {
  margin-left: 0;
}
dt {
  margin-left: 0;
  margin-top: 0.3em;
  font-weight: bold;
}
dd {
  margin-left: 1.3em;
}
dd:dir(rtl) {
  margin-left: unset;
  margin-right: 1.3em;
}
pre {
  text-align: left;
  margin-top: 0.5em;
  margin-bottom: 0.5em;
}
hr {
  border-style: solid;
}
table {
  font-size: 80%;
  margin: 3px 0;
  border-spacing: 1px;
}
table table { /* stop imbricated tables from getting smaller */
  font-size: 100%;
}
th, td {
  padding: 3px;
}
th {
  background-color: #DDD;
  text-align: center;
}
table caption {
  padding: 4px;
  background-color: #EEE;
}
sup { font-size: 70%; }
sub { font-size: 70%; }

/* Specific for our Wikipedia EPUBs */

/* Make section headers looks left aligned and avoid some page breaks */
h1, h2 {
    page-break-before: always;
    page-break-inside: avoid;
    page-break-after: avoid;
    text-align: start;
}
h3, h4, h5, h6 {
    page-break-before: auto;
    page-break-inside: avoid;
    page-break-after: avoid;
    text-align: start;
}
/* Styles for our centered titles on first page */
h1.koreaderwikifrontpage, h5.koreaderwikifrontpage {
    page-break-before: avoid;
    text-align: center;
    margin-top: 0;
}
p.koreaderwikifrontpage {
    font-style: italic;
    font-size: 90%;
    text-indent: 0;
    margin: 1em 2em 1em 2em;
}
hr.koreaderwikifrontpage {
    margin-left: 20%;
    margin-right: 20%;
    margin-bottom: 1.2em;
}
/* Have these HR get the same margins and position as our H2 */
hr.koreaderwikitocstart {
    page-break-before: always;
    font-size: 140%;
    margin: 0.7em 30% 1.5em;
    height: 0.22em;
    border: none;
    background-color: black;
}
hr.koreaderwikitocend {
    page-break-before: avoid;
    page-break-after: always;
    font-size: 140%;
    margin: 1.2em 30% 0;
    height: 0.22em;
    border: none;
    background-color: black;
}

/* So many links, make them look like normal text except for underline */
a {
    display: inline;
    text-decoration: underline;
    color: inherit;
    font-weight: inherit;
}
/* No underline for links without their href that we removed */
a.newwikinonexistent {
    text-decoration: none;
}

/* Don't waste left margin for TOC, notes and other lists */
ul, ol {
    margin: 0;
}
/* OL in Wikipedia pages may inherit their style-type from a wrapping div,
 * ensure they fallback to decimal with inheritance */
body {
    list-style-type: decimal;
}
ol.references {
    list-style-type: inherit;
    /* Allow hiding these pages as their content is available as footnotes */
    -cr-hint: non-linear;
}

/* Show a box around image thumbnails */
figure[typeof~='mw:File/Thumb'],
figure[typeof~='mw:File/Frame'] {
    display: table;
    border: dotted 1px black;
    margin:  0.5em 2.5em 0.5em 2.5em;
    padding: 0 0.5em 0 0.5em;
    padding-top: ]].. (include_images and "0.5em" or "0") .. [[;
    text-align: center;
    font-size: 90%;
    page-break-inside: avoid;
    -cr-only-if: float-floatboxes;
        max-width: 50vw; /* ensure we never take half of screen width */
    -cr-only-if: -float-floatboxes;
        width: 100% !important;
    -cr-only-if: legacy;
        display: block;
}
figure[typeof~='mw:File/Thumb'] > figcaption,
figure[typeof~='mw:File/Frame'] > figcaption {
    display: table-caption;
    caption-side: bottom;
    padding: 0.2em 0.5em 0.2em 0.5em;
    /* No padding-top if image, as the image's strut brings some enough spacing */
    padding-top: ]].. (include_images and "0" or "0.2em") .. [[;
    -cr-only-if: legacy;
        display: block;
}
/* Allow main thumbnails to float, preferably on the right */
body > div > figure[typeof~='mw:File/Thumb'],
body > div > figure[typeof~='mw:File/Frame'] {
    float: right !important;
    /* Change some of their styles when floating */
    -cr-only-if: float-floatboxes;
        clear: right;
        margin:  0 0 0.2em 0.5em !important;
        font-size: 80% !important;
    /* Ensure a fixed width when not in "web" render mode */
    -cr-only-if: float-floatboxes -allow-style-w-h-absolute-units;
        width: 33% !important;
}
/* invert if RTL */
body > div:dir(rtl) > figure[typeof~='mw:File/Thumb'],
body > div:dir(rtl) > figure[typeof~='mw:File/Frame'] {
    float: left !important;
    -cr-only-if: float-floatboxes;
        clear: left;
        margin:  0 0.5em 0.2em 0 !important;
}
/* Allow original mix of left/right floats in web mode */
body > div > figure[typeof~='mw:File/Thumb'].mw-halign-left,
body > div > figure[typeof~='mw:File/Frame'].mw-halign-left {
    -cr-only-if: float-floatboxes allow-style-w-h-absolute-units;
        float: left !important;
        clear: left;
        margin:  0 0.5em 0.2em 0 !important;
}
body > div > figure[typeof~='mw:File/Thumb'].mw-halign-right,
body > div > figure[typeof~='mw:File/Frame'].mw-halign-right {
    -cr-only-if: float-floatboxes allow-style-w-h-absolute-units;
        float: right !important;
        clear: right;
        margin:  0 0 0.2em 0.5em !important;
}
body > div > figure[typeof~='mw:File/Thumb'] > img,
body > div > figure[typeof~='mw:File/Frame'] > img {
    /* Make float's inner images 100% of their container's width when not in "web" mode */
    -cr-only-if: float-floatboxes -allow-style-w-h-absolute-units;
        width: 100% !important;
        height: 100% !important;
}
/* For centered figure, we need to reset a few things, and to not
 * use display:table if we want them wide and centered */
body > div > figure[typeof~='mw:File/Thumb'].mw-halign-center,
body > div > figure[typeof~='mw:File/Frame'].mw-halign-center {
    display: block;
    float: none !important;
    margin:  0.5em 2.5em 0.5em 2.5em !important;
    max-width: none;
}
body > div > figure[typeof~='mw:File/Thumb'].mw-halign-center > figcaption,
body > div > figure[typeof~='mw:File/Frame'].mw-halign-center > figcaption{
    display: block;
}

/* Style gallery and the galleryboxes it contains.
/* LI.galleryboxes about the same topic may be in multiple UL.gallery
 * containers, and Wikipedia may group them by 3 or 4 in each container.
 * We'd rather want them in a single group, so they can be laid out
 * taking the full width depending on render mode and screen dpi.
 * So, make UL.gallery inline, and all its children inline-block.
 * The consecutive inline UL.gallery will be wrapped by crengine
 * in a single autoBoxing element, that we style a bit, hoping
 * Wikipedia properly have all its 1st level elements "display:block"
 * and we do not style other autoBoxed inlines at this level. */
body > div > ul.gallery,
body > div > autoBoxing > ul.gallery {
    display: inline; /* keep them inline once autoBoxed */
}
body > div > autoBoxing { /* created by previous style */
    width: 100%;
    margin-top: 1em;
    margin-bottom: 1em;
    clear: both;
    /* Have non-full-width inline-blocks laid out centered */
    text-align: center;
}
body > div > ul.gallery > *,
body > div > autoBoxing > ul.gallery > * {
    /* Make all ul.gallery children inline-block and taking 100% width
     * so they feel like classically stacked display:block */
    display: inline-block;
    width: 100%;
    /* Have gallerycaption and galleryboxes content centered */
    text-align: center;
}
.gallerycaption {
    font-weight: bold;
    page-break-inside: avoid;
    page-break-after: avoid;
}
li.gallerybox {
    /* Style gallerybox just as main thumbs */
    list-style-type: none;
    border: dotted 1px black;
    margin:  0.5em 2.5em 0.5em 2.5em !important;
    padding: 0.5em 0.5em 0.2em 0.5em !important;
    padding-top: ]].. (include_images and "0.5em" or "0.15em") .. [[ !important;
    text-indent: 0;
    font-size: 90%;
    vertical-align: top; /* align them all to their top */
    /* No float here, but use these to distinguish flat/book/web modes */
    -cr-only-if: -float-floatboxes;
        width: 100% !important; /* flat mode: force full width */
    -cr-only-if: float-floatboxes;
        font-size: 80%;
        /* Remove our wide horizontal margins in book/web modes */
        margin:  0.5em 0.5em 0.5em 0.5em !important;
    -cr-only-if: float-floatboxes -allow-style-w-h-absolute-units;
        /* Set a fixed width when not in "web" mode */
        width: 25% !important; /* will allow rows of 3 */
    /* In web mode, allow the specified widths in HTML style attributes  */
}
li.gallerybox p {
    /* Reset indent as we have everything centered */
    text-indent: 0;
}
li.gallerybox div.thumb {
    /* Remove thumb styling, which we have set on the gallerybox */
    border: solid 1px white;
    margin: 0;
    padding: 0;
    height: auto !important;
}
li.gallerybox div.thumb div {
    /* Override this one often set in style="" with various values */
    margin: 0 !important;
}
li.gallerybox * {
    /* Have sub elements take the full container width when not in "web" mode */
    -cr-only-if: float-floatboxes -allow-style-w-h-absolute-units;
        width: 100% !important;
}
li.gallerybox div.thumb img {
    /* Make inline-block's inner images 100% of their container's width
     * when not in "web" mode (same as previous, but with height */
    -cr-only-if: float-floatboxes -allow-style-w-h-absolute-units;
        width:  100% !important;
        height: 100% !important;
}

table {
    margin-top: 1em;
    margin-bottom: 1em;
    /* Wikipedia tables are often set as float, make them full width When not floating */
    -cr-only-if: -float-floatboxes;
        width: 100% !important;
}

.citation {
    font-style: italic;
}
abbr.abbr {
    /* Prevent these from looking like a link */
    text-decoration: inherit;
}

/* hide some view/edit/discuss short links displayed as "v m d" */
.nv-view, .nv-edit, .nv-talk {
    display: none;
}
/* hiding .noprint may discard some interesting links */
]], mtime)

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
        -- Some chars in headings are converted to html entities in the
        -- wikipedia-generated HTML. We need to do the same in TOC links
        -- for the links to be valid.
        local s_anchor = s.anchor:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub(">", "&gt;"):gsub("<", "&lt;")
        local s_title = string.format("%s %s", s.number, s.line)
        -- Titles may include <i> and other html tags: let's remove them as
        -- our TOC can only display text
        s_title = (s_title:gsub("(%b<>)", ""))
        -- We need to do as for page_htmltitle above. But headings can contain
        -- html entities for < and > that we need to put back as html entities
        s_title = util.htmlEntitiesToUtf8(s_title):gsub("&", "&#38;"):gsub(">", "&gt;"):gsub("<", "&lt;")
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
    epub:addFileFromMemory("OEBPS/toc.ncx", table.concat(toc_ncx_parts), mtime)

    -- ----------------------------------------------------------------
    -- HTML table of content
    -- We used to have it in the HTML we got from Wikipedia, but we no longer do.
    -- So, build it from the 'sections' we got from the API.
    local toc_html_parts = {}
    -- Unfortunately, we don't and can't get any localized "Contents" or "Sommaire" to use
    -- as a heading. So, use some <hr> at start and at end to make this HTML ToC stand out.
    table.insert(toc_html_parts, '<hr class="koreaderwikitocstart"/>\n')
    cur_level = 0
    for isec, s in ipairs(sections) do
        -- Some chars in headings are converted to html entities in the
        -- wikipedia-generated HTML. We need to do the same in TOC links
        -- for the links to be valid.
        local s_anchor = s.anchor:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub(">", "&gt;"):gsub("<", "&lt;")
        local s_title = string.format("%s %s", s.number, s.line)
        local s_level = s.toclevel
        if s_level == cur_level then
            table.insert(toc_html_parts, "</li>")
        elseif s_level < cur_level then
            table.insert(toc_html_parts, "</li>")
            while cur_level > s_level do
                cur_level = cur_level - 1
                table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
                table.insert(toc_html_parts, "</ul>")
                table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
                table.insert(toc_html_parts, "</li>")
            end
        else -- s_level > cur_level
            while cur_level < s_level do
                table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
                table.insert(toc_html_parts, "<ul>")
                cur_level = cur_level + 1
            end
        end
        cur_level = s_level
        table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
        table.insert(toc_html_parts, string.format([[<li><div><a href="#%s">%s</a></div>]], s_anchor, s_title))
    end
    -- close nested <ul>
    table.insert(toc_html_parts, "</li>")
    while cur_level > 0 do
        cur_level = cur_level - 1
        table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
        table.insert(toc_html_parts, "</ul>")
        if cur_level > 0 then
            table.insert(toc_html_parts, "\n"..(" "):rep(cur_level))
            table.insert(toc_html_parts, "</li>")
        end
    end
    table.insert(toc_html_parts, '<hr class="koreaderwikitocend"/>\n')
    html = html:gsub([[<meta property="mw:PageProp/toc" />]], table.concat(toc_html_parts))

    -- ----------------------------------------------------------------
    -- OEBPS/content.html
    -- Some small fixes to Wikipedia HTML to make crengine and the user happier

    -- In some articles' HTML, we may get <link rel="mw-deduplicated-inline-style" href="mw-data...">
    -- (which, by specs, is an empty element) without the proper empty tag ending "/>", which
    -- would cause crengine's EPUB XHTML parser to wait for a proper </link>, hiding all the
    -- following content... So, just remove them, as we don't make any use of them.
    html = html:gsub("<link [^>]*>", "")

    -- Most images are in a link to the image info page, which is a useless
    -- external link for us, so let's remove this link.
    html = html:gsub("<a[^>]*>%s*(<%s*img [^>]*>)%s*</a>", "%1")

    -- crengine does not support the <math> family of tags for displaying formulas,
    -- which results in lots of space taken by individual character in the formula,
    -- each on a single line...
    -- Also, usually, these <math> tags are followed by a <img> tag pointing to a
    -- SVG version of the formula, that we took care earlier to change the url to
    -- point to a PNG version of the formula (which is still not perfect, as it does
    -- not adjust to the current html font size, but it is at least readable).
    -- So, remove the whole <math>...</math> content
    html = html:gsub([[<math xmlns="http://www.w3.org/1998/Math/MathML".-</math>]], "")

    -- Fix internal wikipedia links with full server url (including lang) so
    -- ReaderLink can notice them and deal with them with a LookupWikipedia event.
    -- We need to remove any "?somekey=somevalue" from url (a real "?" part of the
    -- wiki_page word would be encoded as %3F, but ReaderLink would get it decoded and
    -- would not be able to distinguish them).
    -- Do that first (need to be done first) for full links to other language wikipedias
    local cleanOtherLangWikiPageTitle = function(wiki_lang, wiki_page)
        wiki_page = wiki_page:gsub("%?.*", "")
        return string.format([[href="https://%s.wikipedia.org/wiki/%s"]], wiki_lang, wiki_page)
    end
    html = html:gsub([[href="https?://([^%.]+).wikipedia.org/wiki/([^"]*)"]], cleanOtherLangWikiPageTitle)
    -- Now, do it for same wikipedia short urls
    local cleanWikiPageTitle = function(wiki_page)
        wiki_page = wiki_page:gsub("%?.*", "")
        return string.format([[href="%s/wiki/%s"]], wiki_base_url, wiki_page)
    end
    html = html:gsub([[href="/wiki/([^"]*)"]], cleanWikiPageTitle)

    -- Remove href from links to nonexistent wiki page so they are not clickable :
    -- <a href="/w/index.php?title=PageTitle&amp;action=edit&amp;redlink=1" class="new"
    --          title="PageTitle">PageTitle____on</a>
    -- (removal of the href="" will make them non clickable)
    html = html:gsub([[<a[^>]* class="new"[^>]*>]], [[<a class="newwikinonexistent">]])

    -- Fix some other protocol-less links to wikipedia (href="//fr.wikipedia.org/w/index.php..)
    html = html:gsub([[href="//]], [[href="https://]])

    if self.wiki_prettify then
        -- Prepend some symbols to section titles for a better visual feeling of hierarchy
        html = html:gsub("(<h1[^>]*>)", "%1 "..h1_sym.." ")
        html = html:gsub("(<h2[^>]*>)", "%1 "..h2_sym.." ")
        html = html:gsub("(<h3[^>]*>)", "%1 "..h3_sym.." ")
        html = html:gsub("(<h4[^>]*>)", "%1 "..h4_sym.." ")
        html = html:gsub("(<h5[^>]*>)", "%1 "..h5_sym.." ")
        html = html:gsub("(<h6[^>]*>)", "%1 "..h6_sym.." ")
    end

    -- Note: in all the gsub patterns above, we used lowercase for tags and attributes
    -- because it's how they are in wikipedia HTML and it makes the pattern simple.
    -- If one day this changes, they'll have to be replaced with href => [Hh][Rr][Ee][Ff] ...

    -- We can finally build the final HTML with some header of our own
    local saved_on = T(_("Saved on %1"), os.date("%b %d, %Y %H:%M:%S"))
    local online_version_htmllink = string.format([[<a href="%s/wiki/%s">%s</a>]], wiki_base_url, page:gsub(" ", "_"), _("online version"))
    local see_online_version = T(_("See %1 for up-to-date content"), online_version_htmllink)
    -- Set dir= attribute on the HTML tag for RTL languages
    local html_dir = ""
    if self:isWikipediaLanguageRTL(lang) then
        html_dir = ' dir="rtl"'
    end
    epub:addFileFromMemory("OEBPS/content.html", string.format([[
<html xmlns="http://www.w3.org/1999/xhtml"%s>
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
]], html_dir, page_cleaned, page_htmltitle, lang:upper(), saved_on, see_online_version, html), mtime)

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
        for inum, img in ipairs(images) do
            -- Process can be interrupted every second between image downloads
            -- by tapping while the InfoMessage is displayed
            -- We use the fast_refresh option from image #2 for a quicker download
            local go_on
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()
                go_on = UI:info(T(_("Retrieving image %1 / %2 …"), inum, nb_images), inum >= 2)
                if not go_on then
                    cancelled = true
                    break
                end
            else
                UI:info(T(_("Retrieving image %1 / %2 …"), inum, nb_images), inum >= 2, true)
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
                -- Images do not need to be compressed, so spare some cpu cycles
                if img.mimetype ~= "image/svg+xml" then -- except for SVG images (which are XML text)
                    epub:setZipCompression("store")
                end
                epub:addFileFromMemory("OEBPS/"..img.imgpath, content, mtime)
                epub:setZipCompression("deflate")
            else
                go_on = UI:confirm(T(_("Downloading image %1 failed. Continue anyway?"), inum), _("Stop"), _("Continue"))
                if not go_on then
                    cancelled = true
                    break
                end
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
        UI:info(_("Packing EPUB…"))
    end
    epub:close()
    -- This was nearly a no-op, so sleep a bit to make that progress step seen
    ffiutil.usleep(300000)
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

    -- Force a GC to free the memory we used (the second call may help
    -- reclaim more memory).
    collectgarbage()
    collectgarbage()
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
