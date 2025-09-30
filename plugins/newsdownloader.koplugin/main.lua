local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local DownloadBackend = require("epubdownloadbackend")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local FeedView = require("feed_view")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local Persist = require("persist")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dateparser = require("lib.dateparser")
local http = require("socket.http")
local mime = require("mime")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local logger = require("logger")
local socket = require("socket")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local NewsDownloader = WidgetContainer:extend{
    name = "news_downloader",
    initialized = false,
    feed_config_file = "feed_config.lua",
    feed_config_path = nil,
    news_config_file = "news_settings.lua",
    settings = nil,
    download_dir_name = "news",
    download_dir = nil,
    file_extension = ".epub",
    config_key_custom_dl_dir = "custom_dl_dir",
    kv = nil, -- KeyValuePage
}

local FEED_TYPE_RSS = "rss"
local FEED_TYPE_ATOM = "atom"

-- If a title looks like <title>blabla</title> it'll just be feed.title.
-- If a title looks like <title attr="alb">blabla</title> then we get a table
-- where [1] is the title string and the attributes are also available.
function NewsDownloader.getFeedTitle(possible_title)
    if type(possible_title) == "string" then
        return util.htmlEntitiesToUtf8(possible_title)
    elseif possible_title[1] and type(possible_title[1]) == "string" then
        return util.htmlEntitiesToUtf8(possible_title[1])
    end
end

-- Returns a new empty field that can be modified by the caller
local function getEmptyFeed()
   return {
        [1] = "https://",
        limit = 5,
        download_full_article = false,
        include_images = true,
        enable_filter = false,
        filter_element = "",
        block_element = "",
        http_auth = { username = nil, password = nil },
    }
end

-- There can be multiple links.
-- For now we just assume the first link is probably the right one.
--- @todo Write unit tests.
-- Some feeds that can be used for unit test.
-- http://fransdejonge.com/feed/ for multiple links.
-- https://github.com/koreader/koreader/commits/master.atom for single link with attributes.
function NewsDownloader.getFeedLink(possible_link)
    local E = {}
    if type(possible_link) == "string" then
        return possible_link
    elseif (possible_link._attr or E).href then
        return possible_link._attr.href
    elseif ((possible_link[1] or E)._attr or E).href then
        return possible_link[1]._attr.href
    end
end

-- Look for author names that look like
-- <dc:creator>First Author, Second Author</dc:creator>
-- or
-- <author><name>First Author</name></author>
-- <author><name>Second Author</name></author>...
-- and return a byline or empty string
local function getByline(feed)
    if type(feed["dc:creator"]) == "string" then
        return feed["dc:creator"]
    end
    if type(feed["dc:creator"]) == "table" then
        local i = 0
        local authors = {}
        for _ in pairs(feed["dc:creator"]) do
            i = i + 1
            if feed["dc:creator"][i] == nil then
                break
            end
            authors[i] = feed["dc:creator"][i]
        end
        if #authors > 0 then
            return table.concat(authors, ", ")
        end
    end
    if feed.author then
        if type(feed.author.name) == "string" then -- single author
            return feed.author.name
        end
        if type(feed.author) == "table" then
            local i = 0
            local authors = {}
            for _ in pairs(feed.author) do -- multiple authors
                i = i + 1
                if feed.author[i] == nil then
                    break
                end
                authors[i] = feed.author[i].name
            end
            if #authors > 0 then
                return table.concat(authors, ", ")
            end
        end
    end
    return ""
end

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    menu_items.news_downloader = {
        text = _("News downloader (RSS/Atom)"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function NewsDownloader:getSubMenuItems()
    self:lazyInitialization()
    local sub_item_table
    sub_item_table = {
        {
            text = _("Go to news folder"),
            callback = function()
                self:openDownloadsFolder()
            end,
        },
        {
            text = _("Sync news feeds"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                NetworkMgr:runWhenOnline(function() self:loadConfigAndProcessFeedsWithUI(touchmenu_instance) end)
            end,
        },
        {
            text = _("Edit news feeds"),
            keep_menu_open = true,
            callback = function()
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                    self:viewFeedList()
                end)
            end,
        },
        {
            text = _("Settings"),
            sub_item_table = {
                {
                    text = _("Set download folder"),
                    keep_menu_open = true,
                    callback = function() self:setCustomDownloadDirectory() end,
                },
                {
                    text = _("Never download images"),
                    keep_menu_open = true,
                    checked_func = function()
                        return self.settings:isTrue("never_download_images")
                    end,
                    callback = function()
                        self.settings:toggle("never_download_images")
                        self.settings:flush()
                    end,
                },
                {
                    text = _("Delete all downloaded items"),
                    keep_menu_open = true,
                    callback = function()
                        local Trapper = require("ui/trapper")
                        Trapper:wrap(function()
                                local should_delete = Trapper:confirm(
                                    _("Are you sure you want to delete all downloaded items?"),
                                    _("Cancel"),
                                    _("Delete")
                                )
                                if should_delete then
                                    self:removeNewsButKeepFeedConfig()
                                    Trapper:reset()
                                else
                                    Trapper:reset()
                                end
                        end)
                    end,
                },
            },
        },
        {
            text = _("About"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                                   text = T(_("News downloader retrieves RSS and Atom news entries and stores them to:\n%1\n\nEach entry is a separate EPUB file that can be browsed by KOReader.\nFeeds can be configured with download limits and other customization through the Edit Feeds menu item."),
                                            BD.dirpath(self.download_dir))
                })
            end,
        },
    }
    return sub_item_table
end
-- lazyInitialization sets up variables that point to the
-- Downloads folder and the feeds configuration file.
function NewsDownloader:lazyInitialization()
    if not self.initialized then
        logger.dbg("NewsDownloader: obtaining news folder")
        self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.news_config_file))
        -- Check to see if a custom download directory has been set.
        if self.settings:has(self.config_key_custom_dl_dir) then
            self.download_dir = self.settings:readSetting(self.config_key_custom_dl_dir)
        else
            self.download_dir =
                ("%s/%s/"):format(
                    DataStorage:getFullDataDir(),
                    self.download_dir_name)
        end
        logger.dbg("NewsDownloader: Custom directory set to:", self.download_dir)
        -- If the directory doesn't exist we will create it.
        if not lfs.attributes(self.download_dir, "mode") then
            logger.dbg("NewsDownloader: Creating initial directory")
            lfs.mkdir(self.download_dir)
        end
        -- Now set the path to the feed configuration file.
        self.feed_config_path = self.download_dir .. self.feed_config_file
        -- If the configuration file doesn't exist create it.
        if not lfs.attributes(self.feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial feed config.")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, self.feed_config_file),
                             self.feed_config_path)
        end
        self.initialized = true
    end
end

function NewsDownloader:loadConfigAndProcessFeeds(touchmenu_instance)
    local UI = require("ui/trapper")
    logger.dbg("force repaint due to upcoming blocking calls")

    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- If the file contains no table elements, then the user hasn't set any feeds.
    if #feed_config <= 0 then
        logger.err("NewsDownloader: empty feed list.", self.feed_config_path)
        local should_edit_feed_list = UI:confirm(
            T(_("Feed list is empty. If you want to download news, you'll have to add a feed first.")),
            _("Close"),
            _("Edit feed list")
        )
        if should_edit_feed_list then
            -- Show the user a blank feed view so they can
            -- add a feed to their list.
            local feed_item_vc = FeedView:getItem(
                1,
                getEmptyFeed(),
                function(id, edit_key, value)
                    self:editFeedAttribute(id, edit_key, value)
                end
            )
            self:viewFeedItem(
                feed_item_vc
            )
        end
        return
    end

    local never_download_images = self.settings:isTrue("never_download_images")
    local unsupported_feeds_urls = {}
    local total_feed_entries = #feed_config
    local feed_message

    for idx, feed in ipairs(feed_config) do
        local url = feed[1]
        local limit = feed.limit
        local download_full_article = feed.download_full_article or false
        local include_images = not never_download_images and feed.include_images
        local enable_filter = feed.enable_filter or feed.enable_filter == nil
        local filter_element = feed.filter_element or feed.filter_element == nil
        local block_element = feed.block_element or feed.block_element == nil
        local credentials = feed.credentials
        local http_auth = feed.http_auth
        -- Check if the two required attributes are set.
        if url and limit then
            feed_message = T(_("Processing %1/%2:\n%3"), idx, total_feed_entries, BD.url(url))
            UI:info(feed_message)
            -- Process the feed source.
            self:processFeedSource(
                url,
                credentials,
                http_auth,
                tonumber(limit),
                unsupported_feeds_urls,
                download_full_article,
                include_images,
                feed_message,
                enable_filter,
                filter_element,
                block_element)
        else
            logger.warn("NewsDownloader: invalid feed config entry.", feed)
        end
    end

    if #unsupported_feeds_urls <= 0 then
        -- When no errors are present, we get a happy message.
        feed_message = _("Downloading news finished.")
    else
        -- When some errors are present, we get a sour message that includes
        -- information about the source of the error.
        local unsupported_urls = ""
        for key, value in pairs(unsupported_feeds_urls) do
            -- Create the error message.
            unsupported_urls = unsupported_urls .. " " .. value[1] .. " " .. value[2]
            -- Not sure what this does.
            if key ~= #unsupported_feeds_urls then
                unsupported_urls = BD.url(unsupported_urls) .. ", "
            end
        end
        -- Tell the user there were problems.
        feed_message = _("Downloading news finished with errors.")
        -- Display a dialogue that requires the user to acknowledge
        -- that errors occurred.
        UI:confirm(
            T(_([[
Could not process some feeds.
Unsupported format in: %1. Please
review your feed configuration file.]])
              , unsupported_urls),
            _("Continue"),
            ""
        )
    end
    -- Clear the info widgets before displaying the next ui widget.
    UI:clear()
    -- Check to see if this method was called from the menu. If it was,
    -- we will have gotten a touchmenu_instance. This will context gives the user
    -- two options about what to do next, which are handled by this block.
    if touchmenu_instance then
        -- Ask the user if they want to go to their downloads folder
        -- or if they'd rather remain at the menu.
        feed_message = feed_message.."\n\n".._("Go to download folder?")
        local should_go_to_downloads = UI:confirm(
            feed_message,
            _("Close"),
            _("Go to downloads")
        )
        if should_go_to_downloads then
            -- Go to downloads folder.
            UI:clear()
            self:openDownloadsFolder()
            touchmenu_instance:closeMenu()
            NetworkMgr:afterWifiAction()
            return
        else
            -- Return to the menu.
            NetworkMgr:afterWifiAction()
            return
        end
    end
    return
end

function NewsDownloader:loadConfigAndProcessFeedsWithUI(touchmenu_instance)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
            self:loadConfigAndProcessFeeds(touchmenu_instance)
    end)
end

function NewsDownloader:processFeedSource(url, credentials, http_auth, limit, unsupported_feeds_urls, download_full_article, include_images, message, enable_filter, filter_element, block_element)
    -- Check if we have a cached response first
    local cache = DownloadBackend:getCache()
    local cached_response = cache:check(url)
    local ok, error, response

    local cookies = nil
    local extra_headers = nil
    if credentials ~= nil then
        logger.dbg("Auth Cookies from ", credentials.url)
        cookies = DownloadBackend:getConnectionCookies(credentials.url, credentials.auth)
    end

    if http_auth and http_auth.username and http_auth.password then
        extra_headers = { ["Authorization"] = "Basic " .. mime.b64((http_auth.username or "") .. ":" .. (http_auth.password or "")) }
    end

    if cached_response then
        logger.dbg("NewsDownloader: Checking cache validity for:", url)
        local headers_cached = cached_response.headers
        logger.dbg("NewsDownloader: Cached response headers", headers_cached)

        local cache_control = headers_cached["cache-control"]
        local retry_after = headers_cached["retry-after"]
        if (cache_control and cache_control:find("max%-age")) or retry_after then
            local max_age = cache_control and tonumber(cache_control:match("max%-age=(%d+)")) or 0
            local retry = retry_after and tonumber(retry_after) or 0
            local timeout = math.min(43200, math.max(max_age, retry)) -- Limit to 12 hours.
            if timeout then
                local last_access = headers_cached["date"]
                if last_access then
                    logger.dbg("NewsDownloader: Checking cache validity for:", url, "last_access", last_access, "timeout", timeout)
                    local last_access_time = dateparser.parse(last_access)
                    if last_access_time then
                        local now = os.time()
                        local diff = now - last_access_time
                        if diff < timeout then
                            logger.dbg("NewsDownloader: Using cached response for:", url, "max-age:", max_age, "retry-after:", retry_after, "timeout:", timeout, "diff:", diff)
                            response = cached_response.content
                            ok = true
                        end
                    end
                end
            end
        end

        if not ok then
            local etag = headers_cached["etag"]
            local last_modified = headers_cached["last-modified"]
            if etag or last_modified then
                logger.dbg("NewsDownloader: requesting with If-Modified-Since:", last_modified, "If-None-Match:", etag, url)
                local response_body = {}
                local headers = {
                    ["If-Modified-Since"] = last_modified,
                    ["If-None-Match"] = etag,
                }
                if cookies then
                    headers["Cookie"] = cookies
                end
                if extra_headers and extra_headers["Authorization"] then
                    headers["Authorization"] = extra_headers["Authorization"]
                end
                local code, response_headers = socket.skip(1, http.request{
                    url = url,
                    headers = headers,
                    sink = ltn12.sink.table(response_body)
                })
                logger.dbg("NewsDownloader: If-Modified-Since/If-None-Match response", code, response_headers)
                if code == 304 then
                    ok = true
                    response = cached_response.content
                    -- Update cached headers.
                    cached_response.headers = response_headers
                    cache:insert(url, cached_response)
                elseif code == 200 then
                    ok = true
                    response = table.concat(response_body)
                    -- Update cached response.
                    cached_response.headers = response_headers
                    cached_response.content = response
                    cache:insert(url, cached_response)
                end
            end
        end
    end

    if not response then
        ok, response = pcall(function()
            return DownloadBackend:getResponseAsString(url, cookies, true, extra_headers)
        end)
    end

    local feeds, err
    -- Check to see if a response is available to deserialize.
    if ok then
        feeds, err = self:deserializeXMLString(response)
        if not feeds then
            logger.err("NewsDownloader: Error during feed deserialization:", err)
            logger.dbg("NewsDownloader: Response was:", response)
        end
    end
    -- If the response is not available (for a reason that we don't know),
    -- add the URL to the unsupported feeds list.
    if not ok or not feeds then
        local error_message
        if not ok then
            error_message = _("(Reason: Failed to download content)")
        else
            error_message = _("(Reason: Error during feed deserialization)")
        end
        table.insert(unsupported_feeds_urls, {
            url,
            error_message,
        })
        return
    end

    -- Check to see if the feed uses RSS.
    local is_rss = false
    if feeds.rss and feeds.rss.channel and feeds.rss.channel.title and feeds.rss.channel.item then
        if type(feeds.rss.channel.item) == "table" then
            -- Normalize data for single-item feeds.
            if not feeds.rss.channel.item[1] and feeds.rss.channel.item then
                local item = feeds.rss.channel.item
                feeds.rss.channel.item = {}
                feeds.rss.channel.item[1] = item
            end
            if feeds.rss.channel.item[1] and feeds.rss.channel.item[1].title and feeds.rss.channel.item[1].link then
                is_rss = true
            end
        end
    end

    -- Check to see if the feed uses Atom.
    local is_atom = false
    if feeds.feed and feeds.feed.title and feeds.feed.entry then
        if type(feeds.feed.entry) == "table" then
            -- Normalize data for single-item feeds.
            if not feeds.feed.entry[1] and feeds.feed.entry then
                local entry = feeds.feed.entry
                feeds.feed.entry = {}
                feeds.feed.entry[1] = entry
            end
            if feeds.feed.entry[1] and feeds.feed.entry[1].title and feeds.feed.entry[1].link then
                is_atom = true
            end
        end
    end

    -- Process the feeds accordingly.
    if is_atom then
        ok, error = pcall(function()
                return self:processFeed(
                    FEED_TYPE_ATOM,
                    feeds,
                    cookies,
                    http_auth,
                    limit,
                    download_full_article,
                    include_images,
                    message,
                    enable_filter,
                    filter_element,
                    block_element
                )
        end)
    elseif is_rss then
        ok, error = pcall(function()
                return self:processFeed(
                    FEED_TYPE_RSS,
                    feeds,
                    cookies,
                    http_auth,
                    limit,
                    download_full_article,
                    include_images,
                    message,
                    enable_filter,
                    filter_element,
                    block_element
                )
        end)
    end
    -- If the feed can't be processed, or it is neither
    -- Atom or RSS, then add it to the unsupported feeds list
    -- and return an error message.
    if not ok or (not is_rss and not is_atom) then
        local error_message
        if not ok then
            logger.err("NewsDownloader: Error processing feed", error)
            error_message = _("(Reason: Failed to download content)")
        elseif not is_rss then
            error_message = _("(Reason: Couldn't process RSS)")
        elseif not is_atom then
            error_message = _("(Reason: Couldn't process Atom)")
        end
        table.insert(unsupported_feeds_urls, {
            url,
            error_message
        })
    end
end

function NewsDownloader:deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENSE_LuaXML
    local treehdl = require("lib/handler")
    local libxml = require("lib/xml")
    -- Instantiate the object that parses the XML file as a Lua table.
    local xmlhandler = treehdl.simpleTreeHandler()

    -- Remove UTF-8 byte order mark, as it will cause LuaXML to fail
    xml_str = xml_str:gsub("^\xef\xbb\xbf", "", 1)

    -- Instantiate the object that parses the XML to a Lua table.
    local ok, err = pcall(function()
        libxml.xmlParser(xmlhandler):parse(xml_str)
    end)
    if not ok then return false, err end
    return xmlhandler.root
end

function NewsDownloader:processFeed(feed_type, feeds, cookies, http_auth, limit, download_full_article, include_images, message, enable_filter, filter_element, block_element)
    local feed_title
    local feed_item
    local total_items
    -- Setup the above vars based on feed type.
    if feed_type == FEED_TYPE_RSS then
        feed_title = util.htmlEntitiesToUtf8(feeds.rss.channel.title)
        feed_item = feeds.rss.channel.item
        total_items = (limit == 0)
            and #feeds.rss.channel.item
            or limit
        if feed_item[1] == nil and feed_item.title then
            -- Normalize data for single-item feeds.
            feed_item = {feed_item}
        end
    else
        feed_title = self.getFeedTitle(feeds.feed.title)
        feed_item = feeds.feed.entry
        total_items = (limit == 0)
            and #feeds.feed.entry
            or limit
        if feed_item[1] == nil and feed_item.title then
            -- Normalize data for single-item feeds.
            feed_item = {feed_item}
        end
    end
    -- Get the path to the output directory.
    local feed_output_dir = ("%s%s/"):format(
        self.download_dir,
        util.getSafeFilename(util.htmlEntitiesToUtf8(feed_title)))
    -- Create the output directory if it doesn't exist.
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end
    -- Download the feed
    for index, feed in pairs(feed_item) do
        -- If limit has been met, stop downloading feed.
        if limit ~= 0 and index - 1 == limit then
            break
        end
        -- Create a message to display during processing.
        local article_message = T(
            _("%1\n\nFetching article %2/%3:"),
            message,
            index,
            total_items
        )
        -- Get the feed description.
        local feed_description
        if feed_type == FEED_TYPE_RSS then
            feed_title = feed.title
            feed_description = feed.description and feed.description[1] or feed.description --- @todo This should select the one with type="html" if there is a choice.
            if feed["content:encoded"] ~= nil then
                -- Spec: https://web.resource.org/rss/1.0/modules/content/
                feed_description = feed["content:encoded"]
            end
        elseif feed_type == FEED_TYPE_ATOM then
            feed_title = feed.title and feed.title[1] or feed.title
            feed_description = feed.content and feed.content[1] or feed.content --- @todo This should select the one with type="html" if there is a choice.
        else
            feed_title = feed.title and feed.title[1] or feed.title
            feed_description = feed.summary
        end
        -- Download the article.
        if download_full_article then
            self:downloadFeed(
                feed,
                cookies,
                http_auth,
                feed_output_dir,
                include_images,
                article_message,
                enable_filter,
                filter_element,
                block_element
            )
        else
            self:createFromDescription(
                feed,
                feed_title,
                feed_description or "",
                feed_output_dir,
                include_images,
                article_message
            )
        end
    end
end

local function parseDate(dateTime)
    -- Uses lua-feedparser https://github.com/slact/lua-feedparser
    -- feedparser is available under the (new) BSD license.
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENCE_lua-feedparser
    logger.dbg("NewsDownloader: Parsing date:", dateTime)
    local date = dateparser.parse(dateTime)
    if type(date) == "number" then
        return os.date("%y-%m-%d_%H-%M_", date)
    end
    return dateTime
end

local function getTitleWithDate(feed)
    local title = util.getSafeFilename(NewsDownloader.getFeedTitle(feed.title))
    if feed.updated then
        title = parseDate(feed.updated) .. title
    elseif feed.pubDate then
        title = parseDate(feed.pubDate) .. title
    elseif feed.published then
        title = parseDate(feed.published) .. title
    end
    return title
end

function NewsDownloader:downloadFeed(feed, cookies, http_auth, feed_output_dir, include_images, message, enable_filter, filter_element, block_element)
    local title_with_date = getTitleWithDate(feed)
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                             title_with_date,
                                             self.file_extension)

    local file_mode = lfs.attributes(news_file_path, "mode")
    if file_mode == "file" then
        logger.dbg("NewsDownloader:", news_file_path, "already exists. Skipping")
    else
        logger.dbg("NewsDownloader: News file will be stored to :", news_file_path)
        local article_message = T(_("%1\n%2"), message, title_with_date)
        local link = self.getFeedLink(feed.link)
        local extra_headers = nil
        if http_auth and http_auth.username and http_auth.password then
            extra_headers = { ["Authorization"] = "Basic " .. mime.b64((http_auth.username or "") .. ":" .. (http_auth.password or "")) }
        end
        local html = DownloadBackend:loadPage(link, cookies, extra_headers)
        DownloadBackend:createEpub(news_file_path, html, link, include_images, article_message, enable_filter, filter_element, block_element)
    end
end

function NewsDownloader:createFromDescription(feed, title, content, feed_output_dir, include_images, message)
    local title_with_date = getTitleWithDate(feed)
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                             title_with_date,
                                             self.file_extension)
    local file_mode = lfs.attributes(news_file_path, "mode")
    if file_mode == "file" then
        logger.dbg("NewsDownloader:", news_file_path, "already exists. Skipping")
    else
        logger.dbg("NewsDownloader: News file will be stored to :", news_file_path)
        local article_message = T(_("%1\n%2"), message, title_with_date)
        local byline = getByline(feed)
        local footer = _("If this is only a summary, the full article can be downloaded by going to the News Downloader settings and changing 'Download full article' to 'true'.")

        local base_url = self.getFeedLink(feed.link)
        if base_url then
            if not base_url:match("/$") then
                base_url = base_url .. "/"
            end
            content = content:gsub('href="(.-)"', function(link)
                if link:match("^/") then
                    local base_url_domain_only = base_url:match("^(.-://[^/]+)/")
                    return 'href="' .. base_url_domain_only .. link .. '"'
                end
                if not link:match("^[a-zA-Z][a-zA-Z0-9+.-]*://") then
                    link = base_url .. link
                end
                return 'href="' .. link .. '"'
            end)
        end

        local html = string.format([[
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>%s</title>
</head>
<body>
<header><h1>%s</h1><p><address>%s</address></p></header>
<br>
<article>%s</article>
<br>
<footer><small>%s</small></footer>
</body>
</html>]], title, title, byline, content, footer)
        local link = self.getFeedLink(feed.link)
        DownloadBackend:createEpub(news_file_path, html, link, include_images, article_message)
    end
end

function NewsDownloader:removeNewsButKeepFeedConfig()
    logger.dbg("NewsDownloader: Removing news from :", self.download_dir)
    for entry in lfs.dir(self.download_dir) do
        if entry ~= "." and entry ~= ".." and entry ~= self.feed_config_file then
            local entry_path = self.download_dir .. "/" .. entry
            local entry_mode = lfs.attributes(entry_path, "mode")
            if entry_mode == "file" then
                os.remove(entry_path)
            elseif entry_mode == "directory" then
                FFIUtil.purgeDir(entry_path)
            end
        end
    end
    UIManager:show(InfoMessage:new{
        text = _("All downloaded news feed items deleted.")
    })
end

function NewsDownloader:setCustomDownloadDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("NewsDownloader: set download directory to: ", path)
            self.settings:saveSetting(self.config_key_custom_dl_dir, ("%s/"):format(path))
            self.settings:flush()

            logger.dbg("NewsDownloader: Coping to new download folder previous self.feed_config_file from: ", self.feed_config_path)
            FFIUtil.copyFile(self.feed_config_path, ("%s/%s"):format(path, self.feed_config_file))

            self.initialized = false
            self:lazyInitialization()
        end,
    }:chooseDir()
end

function NewsDownloader:viewFeedList()
    local UI = require("ui/trapper")
    UI:info(_("Loading news feed list…"))
    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        local change_feed_config = UI:confirm(
            _("Could not open feed list. Feeds configuration file is invalid."),
            _("Close"),
            _("View file")
        )
        if change_feed_config then
            self:changeFeedConfig()
        end
        return
    end
    UI:clear()
    -- See if the config file contains any feed items
    if #feed_config <= 0 then
        logger.err("NewsDownloader: empty feed list.", self.feed_config_path)
        -- Why not ask the user if they want to add one?
        -- Or, in future, move along to our list UI with an entry for new feeds

        --return
    end

    local view_content = FeedView:getList(
        feed_config,
        function(feed_item_vc)
            self:viewFeedItem(
                feed_item_vc
            )
        end,
        function(id, edit_key, value)
            self:editFeedAttribute(id, edit_key, value)
        end,
        function(id)
            self:deleteFeed(id)
        end
    )
    -- Add a "Add new feed" button with callback
    table.insert(
        view_content,
        {
            _("Add new feed"),
            "",
            callback = function()
                -- Prepare the view with all the callbacks for editing the attributes
                local feed_item_vc = FeedView:getItem(
                    #feed_config + 1,
                    getEmptyFeed(),
                    function(id, edit_key, value)
                        self:editFeedAttribute(id, edit_key, value)
                    end
                )
                self:viewFeedItem(
                    feed_item_vc
                )
            end
        }
    )
    -- Show the list of feeds.
    if self.kv then
        UIManager:close(self.kv)
    end
    self.kv = KeyValuePage:new{
        title = _("RSS/Atom feeds"),
        value_overflow_align = "right",
        kv_pairs = view_content,
        callback_return = function()
            UIManager:close(self.kv)
        end
    }
    UIManager:show(self.kv)
end

function NewsDownloader:viewFeedItem(data)
    if self.kv then
        UIManager:close(self.kv)
    end
    self.kv = KeyValuePage:new{
        title = _("Edit Feed"),
        value_overflow_align = "left",
        kv_pairs = data,
        callback_return = function()
            self:viewFeedList()
        end
    }
    UIManager:show(self.kv)
end

function NewsDownloader:editFeedAttribute(id, key, value)
    local kv = self.kv
    -- There are basically two types of values: string (incl. numbers)
    -- and booleans. This block chooses what type of value our
    -- attribute will need and displays the corresponding dialog.
    if key == FeedView.URL
        or key == FeedView.LIMIT
        or key == FeedView.FILTER_ELEMENT
        or key == FeedView.BLOCK_ELEMENT
        or key == FeedView.HTTP_AUTH_USERNAME
        or key == FeedView.HTTP_AUTH_PASSWORD then

        local title
        local input_type
        local description

        if key == FeedView.URL then
            title = _("Edit feed URL")
            input_type = "string"
        elseif key == FeedView.LIMIT then
            title = _("Edit feed limit")
            description = _("Set to 0 for no limit to how many items are downloaded")
            input_type = "number"
        elseif key == FeedView.FILTER_ELEMENT then
            title = _("Edit filter element.")
            description = _("Filter based on the given CSS selector. E.g.: name_of_css.element.class")
            input_type = "string"
        elseif key == FeedView.BLOCK_ELEMENT then
            title = _("Edit block element.")
            description = _("Block element based on the given CSS selector. E.g.: name_of_css.element.class")
            input_type = "string"
        elseif key == FeedView.HTTP_AUTH_USERNAME then
            title = _("HTTP auth username")
            input_type = "string"
        elseif key == FeedView.HTTP_AUTH_PASSWORD then
            title = _("HTTP auth password")
            input_type = "string"
        else
            return false
        end

        local input_dialog
        input_dialog = InputDialog:new{
            title = title,
            input = value,
            input_type = input_type,
            description = description,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(input_dialog)
                            UIManager:show(kv)
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(input_dialog)
                            self:updateFeedConfig(id, key, input_dialog:getInputValue())
                        end,
                    },
                }
            },
        }
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
        return true
    else
        local text
        if key == FeedView.DOWNLOAD_FULL_ARTICLE then
            text = _("Download full article?")
        elseif key == FeedView.INCLUDE_IMAGES then
            text = _("Include images?")
        elseif key == FeedView.ENABLE_FILTER then
            text = _("Enable CSS filter?")
        end

        local multi_box
        multi_box= MultiConfirmBox:new{
            text = text,
            choice1_text = _("Yes"),
            choice1_callback = function()
                UIManager:close(multi_box)
                self:updateFeedConfig(id, key, true)
            end,
            choice2_text = _("No"),
            choice2_callback = function()
                UIManager:close(multi_box)
                self:updateFeedConfig(id, key, false)
            end,
            cancel_callback = function()
                UIManager:close(multi_box)
                UIManager:show(kv)
            end,
        }
        UIManager:show(multi_box)
    end
end

function NewsDownloader:updateFeedConfig(id, key, value)
    local UI = require("ui/trapper")
    -- Because this method is called at the menu,
    -- we might not have an active view. So this conditional
    -- statement avoids closing a null reference.
    if self.kv then
        UIManager:close(self.kv)
    end
    -- It's possible that we will get a null value.
    -- This block catches that possibility.
    if id ~= nil and key ~= nil and value ~= nil then
        -- This logger is a bit opaque because T() wasn't playing nice with booleans
        logger.dbg("Newsdownloader: attempting to update config:")
    else
        logger.dbg("Newsdownloader: null value supplied to update. Not updating config")
        return
    end

    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- If the file contains no table elements, then the user hasn't set any feeds.
    if #feed_config <= 0 then
        logger.dbg("NewsDownloader: empty feed list.", self.feed_config_path)
    end

    -- Check to see if the id is larger than the number of feeds. If it is,
    -- then we know this is a new add. Insert the base array.
    if id > #feed_config then
        table.insert(
            feed_config,
            getEmptyFeed()
        )
    end

    local new_config = {}
    -- In this loop, we cycle through the feed items. A series of
    -- conditionals checks to see if we are at the right id
    -- and key (i.e.: the key that triggered this function.
    -- If we are at the right spot, we overwrite (or create) the value
    for idx, feed in ipairs(feed_config) do
        -- Check to see if this is the correct feed to update.
        if idx == id then
            if key == FeedView.URL then
                if feed[1] then
                    -- If the value exists, then it's been set. So all we do
                    -- is overwrite the value.
                    feed[1] = value
                else
                    -- If the value doesn't exist, then we need to set it.
                    -- So we insert it into the table.
                    table.insert(
                        feed,
                        {
                            value
                        }
                    )
                end
            elseif key == FeedView.LIMIT then
                if feed.limit then
                    feed.limit = value
                else
                    table.insert(
                        feed,
                        {
                            "limit",
                            value
                        }
                    )
                end
            elseif key == FeedView.DOWNLOAD_FULL_ARTICLE then
                if feed.download_full_article ~= nil then
                    feed.download_full_article = value
                else
                    table.insert(
                        feed,
                        {
                            "download_full_article",
                            value
                        }
                    )
                end
            elseif key == FeedView.INCLUDE_IMAGES then
                if feed.include_images ~= nil then
                    feed.include_images = value
                else
                    table.insert(
                        feed,
                        {
                            "include_images",
                            value
                        }
                    )
                end
            elseif key == FeedView.ENABLE_FILTER then
                if feed.enable_filter ~= nil then
                    feed.enable_filter = value
                else
                    table.insert(
                        feed,
                        {
                            "enable_filter",
                            value
                        }
                    )
                end
            elseif key == FeedView.FILTER_ELEMENT then
                if feed.filter_element then
                    feed.filter_element = value
                else
                    table.insert(
                        feed,
                        {
                            "filter_element",
                            value
                        }
                    )
                end
            elseif key == FeedView.BLOCK_ELEMENT then
                if feed.block_element then
                    feed.block_element = value
                else
                    table.insert(
                        feed,
                        {
                            "block_element",
                            value
                        }
                    )
                end
            elseif key == FeedView.HTTP_AUTH_USERNAME then
                feed.http_auth = feed.http_auth or { username = "", password = "" }
                feed.http_auth.username = value or ""
            elseif key == FeedView.HTTP_AUTH_PASSWORD then
                feed.http_auth = feed.http_auth or { username = "", password = "" }
                feed.http_auth.password = value or ""
            end
        end
        -- Now we insert the updated (or newly created) feed into the
        -- new config feed that we're building in this loop.
        table.insert(
            new_config,
            feed
        )
    end
    -- Save the config
    logger.dbg("NewsDownloader: config to save", new_config)
    self:saveConfig(new_config)
    -- Refresh the view
    local feed_item_vc = FeedView:getItem(
        id,
        new_config[id],
        function(cb_id, cb_edit_key, cb_value)
            self:editFeedAttribute(cb_id, cb_edit_key, cb_value)
        end
    )
    self:viewFeedItem(
        feed_item_vc
    )

end

function NewsDownloader:deleteFeed(id)
    local UI = require("ui/trapper")
    logger.dbg("Newsdownloader: attempting to delete feed")
    -- Check to see if we can get the config file.
    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- In this loop, we cycle through the feed items. A series of
    -- conditionals checks to see if we are at the right id
    -- and key (i.e.: the key that triggered this function.
    -- If we are at the right spot, we overwrite (or create) the value
    local new_config = {}
    for idx, feed in ipairs(feed_config) do
        -- Check to see if this is the correct feed to update.
        if idx ~= id then
            table.insert(
                new_config,
                feed
            )
        end
    end
    -- Save the config
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
            logger.dbg("NewsDownloader: config to save", new_config)
            self:saveConfig(new_config)
    end)
    -- Refresh the view
    self:viewFeedList()
end

function NewsDownloader:saveConfig(config)
    local UI = require("ui/trapper")
    UI:info(_("Saving news feed list…"))
    local persist = Persist:new{
        path = self.feed_config_path
    }
    local ok = persist:save(config)
    if not ok then
        UI:info(_("Could not save news feed config."))
    else
        UI:info(_("News feed config updated successfully."))
    end
    UI:reset()
end

function NewsDownloader:changeFeedConfig()
    local config = ""
    local feed_config_file = io.open(self.feed_config_path, "rb")
    if feed_config_file then
        config = feed_config_file:read("*all")
        feed_config_file:close()
    end
    local config_editor
    logger.info("NewsDownloader: opening configuration file", self.feed_config_path)
    config_editor = InputDialog:new{
        title = T(_("Config: %1"), BD.filepath(self.feed_config_path)),
        input = config,
        input_type = "string",
        para_direction_rtl = false, -- force LTR
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = function()
            return config
        end,
        save_callback = function(content)
            if content and #content > 0 then
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local syntax_okay, syntax_error = loadstring(content)
                    feed_config_file = io.open(self.feed_config_path, "w")
                    if syntax_okay and feed_config_file then
                        feed_config_file:write(content)
                        feed_config_file:close()
                        return true, _("Configuration saved")
                    else
                        return false, T(_("Configuration invalid: %1"), syntax_error)
                    end
                else
                    return false, T(_("Configuration invalid: %1"), parse_error)
                end
            end
            return false, _("Configuration empty")
        end,
    }
    UIManager:show(config_editor)
    config_editor:onShowKeyboard()
end
function NewsDownloader:openDownloadsFolder()
    local FileManager = require("apps/filemanager/filemanager")
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(self.download_dir)
    else
        FileManager:showFiles(self.download_dir)
    end
end

function NewsDownloader:onCloseDocument()
    local document_full_path = self.ui.document.file
    -- NOTE: this is partially broken by the lazy initialization shenanigans, in case someone considers this a feature. self.download_dir can be nil.
    if document_full_path and self.download_dir and self.download_dir == string.sub(document_full_path, 1, #self.download_dir) then
        logger.dbg("NewsDownloader: document_full_path:", document_full_path)
        logger.dbg("NewsDownloader: self.download_dir:", self.download_dir)
        logger.dbg("NewsDownloader: removing NewsDownloader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
        local doc_dir = util.splitFilePathName(document_full_path)
        self.ui:setLastDirForFileBrowser(doc_dir)
    end
end

return NewsDownloader
