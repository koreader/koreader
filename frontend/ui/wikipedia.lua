local JSON = require("json")
local Screen = require("device").screen
local ffiutil = require("ffi/util")
local logger = require("logger")
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
       gsrlimit = 20, -- max nb of results to get
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
       -- we only need the following informations
       prop = "text|sections|displaytitle|revid",
       -- page = nil, -- text to lookup, will be added below
       -- disabletoc = "", -- if we want to remove toc IN html
       disablelimitreport = "",
       disableeditsection = "",
   },
   -- Full article, parsed to output HTML, for images extraction
   -- (used with full article as text, if "show more images" enabled)
   wiki_images_params = { -- same as previous one, with just text html
       action = "parse",
       format = "json",
       -- we only need the following informations
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

-- Codes that getUrlContent may get from requester.request()
local TIMEOUT_CODE = "timeout" -- from socket.lua
local MAXTIME_CODE = "maxtime reached" -- from sink_table_with_maxtime

-- Sink that stores into a table, aborting if maxtime has elapsed
local function sink_table_with_maxtime(t, maxtime)
    -- Start counting as soon as this sink is created
    local start_secs, start_usecs = ffiutil.gettime()
    local starttime = start_secs + start_usecs/1000000
    t = t or {}
    local f = function(chunk, err)
        local secs, usecs = ffiutil.gettime()
        if secs + usecs/1000000 - starttime > maxtime then
            return nil, MAXTIME_CODE
        end
        if chunk then table.insert(t, chunk) end
        return 1
    end
    return f, t
end

-- Get URL content
local function getUrlContent(url, timeout, maxtime)
    local socket = require('socket')
    local ltn12 = require('ltn12')
    local http = require('socket.http')
    local https = require('ssl.https')

    local requester
    if url:sub(1,7) == "http://" then
        requester = http
    elseif url:sub(1,8) == "https://" then
        requester = https
    else
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 10 end
    -- timeout needs to be set to 'http', even if we use 'https'
    http.TIMEOUT, https.TIMEOUT = timeout, timeout

    local request = {}
    local sink = {}
    request['url'] = url
    request['method'] = 'GET'
    -- 'timeout' delay works on socket, and is triggered when
    -- that time has passed trying to connect, or after connection
    -- when no data has been read for this time.
    -- On a slow connection, it may not be triggered (as we could read
    -- 1 byte every 1 second, not triggering any timeout).
    -- 'maxtime' can be provided to overcome that, and we start counting
    -- as soon as the first content byte is received (but it is checked
    -- for only when data is received).
    -- Setting 'maxtime' and 'timeout' gives more chance to abort the request when
    -- it takes too much time (in the worst case: in timeout+maxtime seconds).
    -- But time taken by DNS lookup cannot easily be accounted for, so
    -- a request may (when dns lookup takes time) exceed timeout and maxtime...
    if maxtime then
        request['sink'] = sink_table_with_maxtime(sink, maxtime)
    else
        request['sink'] = ltn12.sink.table(sink)
    end

    local code, headers, status = socket.skip(1, requester.request(request))
    local content = table.concat(sink) -- empty or content accumulated till now
    -- logger.dbg("code:", code)
    -- logger.dbg("headers:", headers)
    -- logger.dbg("status:", status)
    -- logger.dbg("#content:", #content)

    if code == TIMEOUT_CODE or code == MAXTIME_CODE then
        logger.warn("request interrupted:", code)
        return false, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", code, status)
        return false, "Network or remote server unavailable"
    end
    if not code or string.sub(code, 1, 1) ~= "2" then -- all 200..299 HTTP codes are OK
        logger.warn("HTTP status not okay:", code, status)
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
    local url = require('socket.url')
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
        local timeout, maxtime = 10, 60
        success, content = getUrlContent(built_url, timeout, maxtime)
    end
    if not success then
        error(content)
    end

    if content ~= "" and string.sub(content, 1,1) == "{" then
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
        -- We first try to catch images in <div class=thumbinner>, which should exclude
        -- wikipedia icons, flags... These seem to all end with a double </div>.
        for thtml in html:gmatch([[<div class="thumbinner".-</div>%s*</div>]]) do
            table.insert(thumbs, thtml)
        end
        -- We then also try to catch images in galleries (which often are less
        -- interesting than those in thumbinner) as a 2nd set.
        for thtml in html:gmatch([[<li class="gallerybox".-<div class="thumb".-</div>%s*</div>%s*<div class="gallerytext">.-</div>%s*</div>]]) do
            table.insert(thumbs, thtml)
        end
        -- We may miss some interesting images in the page's top right table, but
        -- there's no easy way to distinguish them from icons/flags in this table...

        for _, thtml in ipairs(thumbs) do
            -- We get <a href="/wiki/File:real_file_name.jpg (or /wiki/Fichier:real_file_name.jpg
            -- depending on Wikipedia lang)
            local filename = thtml:match([[<a href="/wiki/[^:]*:([^"]*)" class="image"]])
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
                    -- Ignore img without width and height, which should exlude
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
        trap_widget = false
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
    -- avoid dump()/load() a long string of image bytes
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

    -- Use mupdf to render image to blitbuffer
    local mupdf = require("ffi/mupdf")
    local ok, bb_or_error
    if not highres then
        -- For low-res, we should ensure the image we got from wikipedia is
        -- the right size, so it does not overflow our reserved area
        -- (TextBoxWidget may have adjusted image.width and height)
        ok, bb_or_error = pcall(mupdf.renderImage, data, #data, image.width, image.height)
    else
        -- No need for width and height for high-res
        ok, bb_or_error = pcall(mupdf.renderImage, data, #data)
    end
    if not ok then
        logger.warn("failed building image from", source, ":", bb_or_error)
        return
    end
    if not highres then
        image.bb = bb_or_error
    else
        image.hi_bb = bb_or_error
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
            width = width * 1.3
            height = height * 1.3
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
            include_images = UI:confirm(T(_("This article contains %1 images.\nWould you like to download and include them in the generated EPUB file?"), #images), _("Don't include"), _("Include"))
            if include_images then
                use_img_2x = UI:confirm(_("Would you like to use slightly higher quality images? This will result in a bigger file size."), _("Standard quality"), _("Higher quality"))
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
/* avoid a line with a standalone bullet */
li.gallerybox {
    display: inline;
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

    -- TODO: do something for <li class="gallerybox"...> so they are no more
    -- a <li> (crengine displays them one above the other) and can be displayed
    -- side by side

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
    -- Do that first (need to be done first) for full links to other language wikipedias
    local fixEncodedOtherLangWikiPageTitle = function(wiki_lang, wiki_page)
        -- First, remove any "?otherkey=othervalue" from url (a real "?" part of the wiki_page word
        -- would be encoded as %3f), that could cause problem when used.
        wiki_page = wiki_page:gsub("%?.*", "")
        wiki_page = wiki_page:gsub("%%(%x%x)", hex_to_char)
        return string.format([[href="https://%s.wikipedia.org/wiki/%s"]], wiki_lang, wiki_page)
    end
    html = html:gsub([[href="https?://([^%.]+).wikipedia.org/wiki/([^"]*)"]], fixEncodedOtherLangWikiPageTitle)
    -- Now, do it for same wikipedia short urls
    local fixEncodedWikiPageTitle = function(wiki_page)
        wiki_page = wiki_page:gsub("%?.*", "")
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
            local go_on = UI:info(T(_("Retrieving image %1 / %2 …"), inum, nb_images), inum >= 2)
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
